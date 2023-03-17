// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OFToken } from "./OFToken.sol";
import { IVaultV2 } from "./interfaces/IVaultV2.sol";
import { UUPSUpgradeable } from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ILayerZeroEndpoint } from "@layerZero/interfaces/ILayerZeroEndpoint.sol";

//import { NonblockingLzApp } from "@layerZero/lzApp/NonblockingLzApp.sol";

contract VaultV2 is IVaultV2, UUPSUpgradeable {
    uint256 constant REWARD_PRECISION = 1 ether;
    uint256 constant REWARDS_PER_SECOND = 317 * REWARD_PRECISION; // 10^10 / 365.25 days (in seconds)
    uint256 constant SECONDS_IN_30_DAYS = 2_592_000;
    uint256 constant DEPOSIT_LIST_START_ID = 1;
    uint256 constant MINIMUM_DEPOSIT_AMOUNT = 1000;
    uint256 constant SEND_VALUE = 1 ether;
    uint16 constant CHAIN_LIST_SEPARATOR = 998;

    address private _owner;
    uint256 private _totalShares;
    uint256 private _lastRewardUpdateTime;
    uint256 private _lastRewardsPerShare;
    uint256 private _idCounter;
    bool private _initialized;

    mapping(address => uint256) private _withdrawableAssets;
    mapping(address => int256) private _pendingRewards; // can be negative
    mapping(uint256 => Deposit) private _depositList;

    IERC20 public asset;
    OFToken public rewardToken;

    // New storage variables
    mapping(uint16 => bytes) private _trustedRemoteLookup;
    mapping(uint16 => uint16) private _chainIdList;

    ILayerZeroEndpoint private _lzEndpoint;

    modifier onlyOwner() {
        if (msg.sender != _owner) revert UnauthorizedError();
        _;
    }

    /// @dev Acts as the constructor
    function initialize(address asset_, address lzEndpoint_) external {
        if (_initialized) revert AlreadyInitializedError();
        _initialized = true;

        rewardToken = new OFToken(address(this), "Token", "TKN", lzEndpoint_);
        asset = IERC20(asset_);
        _lzEndpoint = ILayerZeroEndpoint(lzEndpoint_);
        _owner = msg.sender;

        _chainIdList[CHAIN_LIST_SEPARATOR] = CHAIN_LIST_SEPARATOR;

        _idCounter = 2;
        _lastRewardUpdateTime = block.timestamp;
    }

    // @inheritdoc IVaultV2
    function deposit(uint256 amount_, uint256 monthsLocked_, uint256 hint_) external override {
        if (monthsLocked_ != 6 && monthsLocked_ != 12 && monthsLocked_ != 24 && monthsLocked_ != 48) {
            revert InvalidLockPeriodError();
        }
        if (amount_ < MINIMUM_DEPOSIT_AMOUNT) revert InsuficientDepositAmountError();

        _maintainDepositList();
        uint256 expireTime_ = block.timestamp + monthsLocked_ * SECONDS_IN_30_DAYS;
        uint256 insertPosition_ = _isValid(expireTime_, hint_) ? hint_ : getInsertPosition(expireTime_);
        uint256 shares_ = amount_ * (monthsLocked_ / 6);
        asset.transferFrom(msg.sender, address(this), amount_);

        _depositList[_idCounter].expireTime = expireTime_;
        _depositList[_idCounter].depositor = msg.sender;
        _depositList[_idCounter].deposit = amount_;
        _depositList[_idCounter].shares = shares_;
        _depositList[_idCounter].rewardsPerShare = _updateRewardsPerShare(shares_, true, block.timestamp);
        _depositList[_idCounter].nextId = _depositList[insertPosition_].nextId;

        _depositList[insertPosition_].nextId = _idCounter;
        _idCounter++;

        _broadcastDeposit(shares_, expireTime_);

        emit LogDeposit(msg.sender, amount_, monthsLocked_);
    }

    function withdraw() external override {
        _maintainDepositList();
        uint256 amount_ = _withdrawableAssets[msg.sender];
        _withdrawableAssets[msg.sender] = 0;
        if (amount_ != 0) asset.transfer(msg.sender, amount_);
        else revert NoAssetToWithdrawError();

        emit LogWithdraw(msg.sender, amount_);
    }

    //would calling msg.sender only 1 improve performance ?
    function claimRewards(uint256[] calldata depositIds_) external override {
        _maintainDepositList();
        uint256 amount_ = getclaimableRewards(msg.sender, depositIds_);
        if (amount_ == 0) revert NoRewardsToClaimError();
        _pendingRewards[msg.sender] -= int256(amount_ * REWARD_PRECISION);
        rewardToken.mintRewards(msg.sender, amount_);

        emit LogClaimRewards(msg.sender, amount_);
    }

    function lzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64, bytes calldata _payload)
        external
        override
    {
        if (msg.sender != address(_lzEndpoint)) revert NotEndpointError();
        bytes memory trustedRemote_ = _trustedRemoteLookup[_srcChainId];
        if (
            _srcAddress.length != trustedRemote_.length || trustedRemote_.length == 0
                || keccak256(_srcAddress) != keccak256(trustedRemote_)
        ) {
            revert NotTrustedSourceError();
        }
        _maintainDepositList();

        address fromAddress_;
        assembly {
            fromAddress_ := mload(add(_srcAddress, 20))
        }
        (uint256 shares_, uint256 depositTime_, uint256 expireTime_) = abi.decode(_payload, (uint256, uint256, uint256));
        uint256 hint_ = getInsertPosition(expireTime_);
        _depositList[_idCounter].expireTime = expireTime_;
        _depositList[_idCounter].shares = shares_;
        _updateRewardsPerShare(shares_, true, depositTime_);

        _depositList[hint_].nextId = _idCounter;
        _idCounter++;

        emit LogOmnichainDeposit(_srcChainId, fromAddress_, shares_, depositTime_, expireTime_);
    }

    function addTrustedRemoteAddress(uint16 remoteChainId_, bytes calldata remoteAddress_) external onlyOwner {
        if (remoteChainId_ == CHAIN_LIST_SEPARATOR) revert InvalidChainIdError();
        if (_chainIdList[remoteChainId_] != 0) revert DuplicatingChainIdError();
        _chainIdList[remoteChainId_] = _chainIdList[CHAIN_LIST_SEPARATOR];
        _chainIdList[CHAIN_LIST_SEPARATOR] = remoteChainId_;
        _trustedRemoteLookup[remoteChainId_] = remoteAddress_;

        emit LogTrustedRemoteAddress(remoteChainId_, remoteAddress_);
    }

    function getclaimableRewards(address depositor_, uint256[] calldata depositIds_)
        public
        view
        override
        returns (uint256 amount_)
    {
        int256 claimableRewards_;
        for (uint256 i = 0; i < depositIds_.length; i++) {
            uint256 id = depositIds_[i];
            if (_depositList[id].depositor != depositor_) revert InvalidHintError();
            if (_depositList[id].expireTime >= block.timestamp) {
                claimableRewards_ += int256(
                    (_getRewardsPerShare(block.timestamp) - _depositList[id].rewardsPerShare) * _depositList[id].shares
                );
            } else {
                claimableRewards_ += int256(
                    (_getRewardsPerShare(_depositList[id].expireTime) - _depositList[id].rewardsPerShare)
                        * _depositList[id].shares
                );
            }
        }
        claimableRewards_ += _pendingRewards[depositor_];

        amount_ = uint256(claimableRewards_) / REWARD_PRECISION;
    }

    function getInsertPosition(uint256 expireTime_) public view override returns (uint256 hint_) {
        hint_ = DEPOSIT_LIST_START_ID;
        uint256 nextId_ = _depositList[hint_].nextId;
        while (nextId_ != 0) {
            if (_depositList[nextId_].expireTime >= expireTime_) break;
            hint_ = nextId_;
            nextId_ = _depositList[hint_].nextId;
        }
    }

    function getDepositIds(address depositor_) external view override returns (uint256[] memory depositIds_) {
        uint256 id_ = _depositList[DEPOSIT_LIST_START_ID].nextId;
        uint256 arraysize_;
        while (id_ != 0) {
            if (_depositList[id_].depositor == depositor_) arraysize_++;
            id_ = _depositList[id_].nextId;
        }
        depositIds_ = new uint256[](arraysize_);

        id_ = _depositList[DEPOSIT_LIST_START_ID].nextId;
        uint256 i_;
        while (id_ != 0) {
            if (_depositList[id_].depositor == depositor_) {
                depositIds_[i_] = id_;
                i_++;
            }
            id_ = _depositList[id_].nextId;
        }
    }

    function _maintainDepositList() internal {
        uint256 id_ = _depositList[DEPOSIT_LIST_START_ID].nextId;
        while (id_ != 0 && _depositList[id_].expireTime <= block.timestamp) {
            uint256 rewardsPerShare = _updateRewardsPerShare(_depositList[id_].shares, false, _depositList[id_].expireTime);

            //deposit made on this chain
            if (_depositList[id_].deposit != 0) {
                uint256 rewards = (rewardsPerShare - _depositList[id_].rewardsPerShare) * _depositList[id_].shares;
                _pendingRewards[_depositList[id_].depositor] += int256(rewards);
                _withdrawableAssets[_depositList[id_].depositor] += _depositList[id_].deposit;
                emit LogExpiredDeposit(_depositList[id_].depositor, _depositList[id_].deposit, rewards);
            }
            uint256 nextId = _depositList[id_].nextId;
            delete _depositList[id_];

            id_ = nextId;
            _depositList[DEPOSIT_LIST_START_ID].nextId = nextId;
        }
    }

    function _broadcastDeposit(uint256 shares, uint256 expireTime) internal {
        bytes memory payload_ = abi.encodePacked(shares, block.timestamp, expireTime);

        uint16 chainId_ = _chainIdList[CHAIN_LIST_SEPARATOR];

        while (chainId_ != CHAIN_LIST_SEPARATOR) {
            bytes memory trustedRemote = _trustedRemoteLookup[chainId_];

            _lzEndpoint.send{ value: SEND_VALUE }(
                chainId_, // destination LayerZero chainId
                trustedRemote, // send to this address on the destination
                payload_, // bytes payload
                payable(msg.sender), // refund address
                address(0x0), // future parameter
                bytes("") // adapterParams (see "Advanced Features")
            );
            chainId_ = _chainIdList[chainId_];
        }
    }

    function _getRewardsPerShare(uint256 timestamp_) internal view returns (uint256 rewardsPerShare_) {
        rewardsPerShare_ =
            _lastRewardsPerShare + (timestamp_ - _lastRewardUpdateTime) * REWARDS_PER_SECOND / _totalShares;
    }

    function _isValid(uint256 expireTime_, uint256 hint_) internal view returns (bool valid_) {
        if (
            _depositList[hint_].expireTime <= expireTime_
                && _depositList[_depositList[hint_].nextId].expireTime >= expireTime_
        ) {
            valid_ = true;
        }
    }

    function _updateRewardsPerShare(uint256 shareVariation_, bool positiveVariation_, uint256 timeStamp_)
        internal
        returns (uint256 rewardsPerShare_)
    {
        if (_totalShares != 0) {
            _lastRewardsPerShare += (timeStamp_ - _lastRewardUpdateTime) * REWARDS_PER_SECOND / _totalShares;
        }
        _lastRewardUpdateTime = timeStamp_;
        if (positiveVariation_) _totalShares += shareVariation_;
        else _totalShares -= shareVariation_;

        rewardsPerShare_ = _lastRewardsPerShare;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
}
