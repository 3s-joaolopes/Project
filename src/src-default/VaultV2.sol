// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OFToken } from "./OFToken.sol";
import { UUPSUpgradeable } from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ILayerZeroEndpoint } from "@layerZero/interfaces/ILayerZeroEndpoint.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IVaultV2 } from "./interfaces/IVaultV2.sol";
import { ILayerZeroReceiver } from "./interfaces/dependencies/ILayerZeroReceiver.sol";
import { VaultV2Storage } from "./storage/VaultV2Storage.sol";

contract VaultV2 is IVaultV2, UUPSUpgradeable, VaultV2Storage {
    //------------------------------------------------------------------------------------------------------------------------------------//
    // Constants -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    uint128 constant REWARD_PRECISION = 1 ether;
    uint128 constant REWARDS_PER_SECOND = 317 * REWARD_PRECISION; // 10^10 / 365.25 days (in seconds)
    uint128 constant MINIMUM_DEPOSIT_AMOUNT = 1000;
    uint64 constant SECONDS_IN_30_DAYS = 2_592_000;
    uint64 constant DEPOSIT_LIST_START_ID = 1;
    uint64 constant SEND_VALUE = 2 ether;
    uint16 constant CHAIN_LIST_SEPARATOR = 998;

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Modifiers -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    modifier onlyOwner() {
        if (msg.sender != _owner) revert UnauthorizedError();
        _;
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Proxy Initializer -----------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    /// @dev Acts as the constructor
    function initialize(address asset_, address lzEndpoint_) external {
        if (_initialized) revert AlreadyInitializedError();
        _initialized = true;

        rewardToken = new OFToken(address(this), "Token", "TKN", lzEndpoint_);
        asset = IERC20(asset_);
        lzEndpoint = ILayerZeroEndpoint(lzEndpoint_);
        _owner = msg.sender;

        _chainIdList[CHAIN_LIST_SEPARATOR] = CHAIN_LIST_SEPARATOR;

        _idCounter = 2;
        _lastRewardUpdateTime = uint64(block.timestamp);
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Base User Calls -------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    /// @inheritdoc IVault
    function deposit(uint128 amount_, uint64 monthsLocked_, uint64 hint_) external override {
        if (monthsLocked_ != 6 && monthsLocked_ != 12 && monthsLocked_ != 24 && monthsLocked_ != 48) {
            revert InvalidLockPeriodError();
        }
        if (amount_ < MINIMUM_DEPOSIT_AMOUNT) revert InsuficientDepositAmountError();

        _maintainDepositList();
        uint64 expireTime_ = uint64(block.timestamp) + monthsLocked_ * SECONDS_IN_30_DAYS;
        uint64 insertPosition_ = _isValid(expireTime_, hint_) ? hint_ : getInsertPosition(expireTime_);
        uint128 shares_ = amount_ * (monthsLocked_ / 6);
        if (asset.transferFrom(msg.sender, address(this), amount_) == false) revert AssetTransferError();

        _depositList[_idCounter] = Deposit({
            depositor: msg.sender,
            deposit: amount_,
            shares: shares_,
            rewardsPerShare: _updateRewardsPerShare(shares_, true, uint64(block.timestamp)),
            expireTime: expireTime_,
            nextId: _depositList[insertPosition_].nextId
        });

        _depositList[insertPosition_].nextId = _idCounter;
        _idCounter++;

        _broadcastDeposit(shares_, expireTime_);

        emit LogDeposit(msg.sender, amount_, monthsLocked_);
    }

    /// @inheritdoc IVault
    function withdraw() external override {
        _maintainDepositList();
        uint128 amount_ = _withdrawableAssets[msg.sender];
        _withdrawableAssets[msg.sender] = 0;
        if (amount_ != 0) asset.transfer(msg.sender, amount_);
        else revert NoAssetToWithdrawError();

        emit LogWithdraw(msg.sender, amount_);
    }

    /// @inheritdoc IVault
    function claimRewards(uint64[] calldata depositIds_) external override {
        _maintainDepositList();
        uint128 amount_ = getClaimableRewards(msg.sender, depositIds_);
        if (amount_ == 0) revert NoRewardsToClaimError();
        _pendingRewards[msg.sender] -= int128(amount_ * REWARD_PRECISION);
        rewardToken.mintRewards(msg.sender, amount_);

        emit LogClaimRewards(msg.sender, amount_);
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // LayerZero Calls  ------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(uint16 srcChainId_, bytes memory srcAddress_, uint64, bytes calldata payload_)
        external
        override
    {
        if (msg.sender != address(lzEndpoint)) revert NotEndpointError();
        bytes memory trustedRemote_ = _trustedRemoteLookup[srcChainId_];
        if (
            srcAddress_.length != trustedRemote_.length || trustedRemote_.length == 0
                || keccak256(srcAddress_) != keccak256(trustedRemote_)
        ) {
            revert NotTrustedSourceError();
        }
        _maintainDepositList();

        address fromAddress_;
        assembly {
            fromAddress_ := mload(add(srcAddress_, 20))
        }
        //(uint128 shares_, uint64 depositTime_, uint64 expireTime_) = abi.decode(payload_, (uint128, uint64, uint64));
        uint256 compacted_ = abi.decode(payload_, (uint256));
        uint128 shares_ = uint128(compacted_ >> 128);
        uint64 depositTime_ = uint64((compacted_ >> 64) & 0xffffffffffffffff);
        uint64 expireTime_ = uint64(compacted_ & 0xffffffffffffffff);
        uint64 insertPosition_ = getInsertPosition(expireTime_);

        _depositList[_idCounter] = Deposit({
            depositor: address(0),
            deposit: 0,
            shares: shares_,
            rewardsPerShare: 0,
            expireTime: expireTime_,
            nextId: _depositList[insertPosition_].nextId
        });
        _updateRewardsPerShare(shares_, true, depositTime_);

        _depositList[insertPosition_].nextId = _idCounter;
        _idCounter++;

        emit LogOmnichainDeposit(srcChainId_, fromAddress_, shares_, depositTime_, expireTime_);
    }

    /// @inheritdoc IVaultV2
    function addTrustedRemoteAddress(uint16 remoteChainId_, bytes calldata remoteAddress_)
        external
        override
        onlyOwner
    {
        if (remoteChainId_ == CHAIN_LIST_SEPARATOR) revert InvalidChainIdError();
        if (_chainIdList[remoteChainId_] != 0) revert DuplicatingChainIdError();
        _chainIdList[remoteChainId_] = _chainIdList[CHAIN_LIST_SEPARATOR];
        _chainIdList[CHAIN_LIST_SEPARATOR] = remoteChainId_;
        _trustedRemoteLookup[remoteChainId_] = remoteAddress_;

        emit LogTrustedRemoteAddress(remoteChainId_, remoteAddress_);
    }

    /// @inheritdoc IVaultV2
    function resetTrustedRemoteAddresses() external override onlyOwner {
        if (_chainIdList[CHAIN_LIST_SEPARATOR] != 0) {
            uint16 chainId_ = _chainIdList[CHAIN_LIST_SEPARATOR];
            while (chainId_ != CHAIN_LIST_SEPARATOR) {
                chainId_ = _chainIdList[chainId_];
                _chainIdList[chainId_] = 0;
            }
        }
        _chainIdList[CHAIN_LIST_SEPARATOR] = CHAIN_LIST_SEPARATOR;
    }

    /// @inheritdoc IVaultV2
    function setLzEndpoint(address lzEndpoint_) external override onlyOwner {
        lzEndpoint = ILayerZeroEndpoint(lzEndpoint_);
        emit LogNewLzEndpoint(lzEndpoint_);
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // View Functions  -------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    /// @inheritdoc IVault
    function getWithdrawableAmount(address depositor_) external view override returns (uint128 amount_) {
        amount_ = _withdrawableAssets[depositor_];
    }

    /// @inheritdoc IVault
    function getClaimableRewards(address depositor_, uint64[] calldata depositIds_)
        public
        view
        override
        returns (uint128 amount_)
    {
        int128 claimableRewards_;
        for (uint64 i = 0; i < depositIds_.length; i++) {
            uint64 id = depositIds_[i];
            if (_depositList[id].depositor != depositor_) revert InvalidHintError();
            if (_depositList[id].expireTime >= uint64(block.timestamp)) {
                //deposit hasn't expired
                claimableRewards_ += int128(
                    (_getRewardsPerShare(uint64(block.timestamp)) - _depositList[id].rewardsPerShare)
                        * _depositList[id].shares
                );
            } else {
                //deposit has expired
                claimableRewards_ += int128(
                    (_getRewardsPerShare(_depositList[id].expireTime) - _depositList[id].rewardsPerShare)
                        * _depositList[id].shares
                );
            }
        }
        claimableRewards_ += _pendingRewards[depositor_];

        amount_ = uint128(claimableRewards_) / REWARD_PRECISION;
    }

    /// @inheritdoc IVault
    function getInsertPosition(uint64 expireTime_) public view override returns (uint64 hint_) {
        hint_ = DEPOSIT_LIST_START_ID;
        uint64 nextId_ = _depositList[hint_].nextId;
        while (nextId_ != 0) {
            if (_depositList[nextId_].expireTime >= expireTime_) break;
            hint_ = nextId_;
            nextId_ = _depositList[hint_].nextId;
        }
    }

    /// @inheritdoc IVault
    function getDepositIds(address depositor_) external view override returns (uint64[] memory depositIds_) {
        uint64 id_ = _depositList[DEPOSIT_LIST_START_ID].nextId;
        uint64 arraysize_;
        while (id_ != 0) {
            if (_depositList[id_].depositor == depositor_ && _depositList[id_].expireTime > block.timestamp) {
                arraysize_++;
            }
            id_ = _depositList[id_].nextId;
        }
        depositIds_ = new uint64[](arraysize_);

        id_ = _depositList[DEPOSIT_LIST_START_ID].nextId;
        uint64 i_;
        while (id_ != 0) {
            if (_depositList[id_].depositor == depositor_ && _depositList[id_].expireTime > block.timestamp) {
                depositIds_[i_] = id_;
                i_++;
            }
            id_ = _depositList[id_].nextId;
        }
    }

    function _maintainDepositList() internal {
        uint64 id_ = _depositList[DEPOSIT_LIST_START_ID].nextId;
        while (id_ != 0 && _depositList[id_].expireTime <= block.timestamp) {
            uint128 rewardsPerShare =
                _updateRewardsPerShare(_depositList[id_].shares, false, _depositList[id_].expireTime);

            //deposit made on this chain
            if (_depositList[id_].deposit != 0) {
                uint128 rewards = (rewardsPerShare - _depositList[id_].rewardsPerShare) * _depositList[id_].shares;
                _pendingRewards[_depositList[id_].depositor] += int128(rewards);
                _withdrawableAssets[_depositList[id_].depositor] += _depositList[id_].deposit;
                emit LogExpiredDeposit(_depositList[id_].depositor, _depositList[id_].deposit, rewards);
            }
            uint64 nextId = _depositList[id_].nextId;
            delete _depositList[id_];

            id_ = nextId;
            _depositList[DEPOSIT_LIST_START_ID].nextId = nextId;
        }
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Internal Functions ----------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function _broadcastDeposit(uint128 shares, uint64 expireTime) internal {
        bytes memory payload_ = abi.encodePacked(shares, uint64(block.timestamp), expireTime);

        uint16 chainId_ = _chainIdList[CHAIN_LIST_SEPARATOR];

        while (chainId_ != CHAIN_LIST_SEPARATOR) {
            bytes memory trustedRemote = _trustedRemoteLookup[chainId_];

            lzEndpoint.send{ value: SEND_VALUE }(
                chainId_, trustedRemote, payload_, payable(_owner), address(0x0), bytes("")
            );
            chainId_ = _chainIdList[chainId_];
        }
    }

    function _updateRewardsPerShare(uint128 shareVariation_, bool positiveVariation_, uint64 timeStamp_)
        internal
        returns (uint128 rewardsPerShare_)
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

    function _getRewardsPerShare(uint64 timestamp_) internal view returns (uint128 rewardsPerShare_) {
        rewardsPerShare_ =
            _lastRewardsPerShare + (timestamp_ - _lastRewardUpdateTime) * REWARDS_PER_SECOND / _totalShares;
    }

    function _isValid(uint64 expireTime_, uint64 hint_) internal view returns (bool valid_) {
        if (
            _depositList[hint_].expireTime <= expireTime_
                && _depositList[_depositList[hint_].nextId].expireTime >= expireTime_
        ) {
            valid_ = true;
        }
    }
}
