// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Token } from "./Token.sol";
import { IVault } from "./interfaces/IVault.sol";
import { UUPSUpgradeable } from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Vault is IVault, UUPSUpgradeable {
    uint256 constant REWARD_PRECISION = 1 ether;
    uint256 constant REWARDS_PER_SECOND = 317 * REWARD_PRECISION; // 10^10 / 365.25 days (in seconds)
    uint256 constant SECONDS_IN_30_DAYS = 2_592_000;
    uint256 constant LIST_START_ID = 1;
    uint256 constant MINIMUM_DEPOSIT_AMOUNT = 1000;

    address private _owner;
    uint256 private _totalShares;
    uint256 private _lastRewardUpdateTime;
    uint256 private _lastRewardsPerShare;
    uint256 private _idCounter;
    bool private _initialized;

    mapping(address => uint256) private _withdrawableAssets;
    mapping(address => int256) private _pendingRewards; //can be negative
    mapping(uint256 => Deposit) private _depositList;

    IERC20 public asset;
    Token public rewardToken;

    modifier onlyOwner() {
        if (msg.sender != _owner) revert UnauthorizedError();
        _;
    }

    /// @dev Acts as the constructor
    function initialize(address asset_) external {
        if (_initialized) revert AlreadyInitializedError();
        _initialized = true;

        rewardToken = new Token(address(this));
        asset = IERC20(asset_);
        _owner = msg.sender;

        _idCounter = 2;
        _lastRewardUpdateTime = block.timestamp;
    }

    function deposit(uint256 amount_, uint256 monthsLocked_, uint256 hint_) external override {
        if (monthsLocked_ != 6 && monthsLocked_ != 12 && monthsLocked_ != 24 && monthsLocked_ != 48) {
            revert InvalidLockPeriodError();
        }
        if (amount_ < MINIMUM_DEPOSIT_AMOUNT) revert InsuficientDepositAmountError();

        maintainDepositList();
        uint256 expireTime = block.timestamp + monthsLocked_ * SECONDS_IN_30_DAYS;
        uint256 hint = isValid(expireTime, hint_) ? hint_ : getInsertPosition(expireTime);
        uint256 shares = amount_ * (monthsLocked_ / 6);
        asset.transferFrom(msg.sender, address(this), amount_);

        //this seems slow
        _depositList[_idCounter].expireTime = expireTime;
        _depositList[_idCounter].depositor = msg.sender;
        _depositList[_idCounter].deposit = amount_;
        _depositList[_idCounter].shares = shares;
        _depositList[_idCounter].rewardsPerShare = updateRewardsPerShare(shares, true, block.timestamp);
        _depositList[_idCounter].nextId = _depositList[hint].nextId;

        _depositList[hint].nextId = _idCounter;
        _idCounter++;

        emit LogDeposit(msg.sender, amount_, monthsLocked_);
    }

    function withdraw() external override {
        maintainDepositList();
        uint256 amount = _withdrawableAssets[msg.sender];
        _withdrawableAssets[msg.sender] = 0;
        if (amount != 0) asset.transfer(msg.sender, amount);
        else revert NoAssetToWithdrawError();

        emit LogWithdraw(msg.sender, amount);
    }

    //would calling msg.sender only 1 improve performance ?
    function claimRewards(uint256[] calldata depositIds_) external override {
        maintainDepositList();
        uint256 amount = getclaimableRewards(msg.sender, depositIds_);
        if (amount == 0) revert NoRewardsToClaimError();
        _pendingRewards[msg.sender] -= int256(amount * REWARD_PRECISION);
        rewardToken.mintRewards(msg.sender, amount);

        emit LogClaimRewards(msg.sender, amount);
    }

    function getclaimableRewards(address depositor_, uint256[] calldata depositIds_)
        public
        view
        override
        returns (uint256 amount_)
    {
        int256 amount;
        for (uint256 i = 0; i < depositIds_.length; i++) {
            uint256 id = depositIds_[i];
            if (_depositList[id].depositor != depositor_) revert InvalidHintError();
            if (_depositList[id].expireTime >= block.timestamp) {
                amount += int256(
                    (getRewardsPerShare(block.timestamp) - _depositList[id].rewardsPerShare) * _depositList[id].shares
                );
            } else {
                amount += int256(
                    (getRewardsPerShare(_depositList[id].expireTime) - _depositList[id].rewardsPerShare)
                        * _depositList[id].shares
                );
            }
        }
        amount += _pendingRewards[depositor_];

        amount_ = uint256(amount) / REWARD_PRECISION;
    }

    function getInsertPosition(uint256 expireTime_) public view override returns (uint256 hint_) {
        hint_ = LIST_START_ID;
        uint256 nextId = _depositList[hint_].nextId;
        while (nextId != 0) {
            if (_depositList[nextId].expireTime >= expireTime_) break;
            hint_ = nextId;
            nextId = _depositList[hint_].nextId;
        }
    }

    function getDepositIds(address depositor_) external view override returns (uint256[] memory depositIds_) {
        uint256 id = _depositList[LIST_START_ID].nextId;
        uint256 arraysize;
        while (id != 0) {
            if (_depositList[id].depositor == depositor_) arraysize++;
            id = _depositList[id].nextId;
        }
        depositIds_ = new uint256[](arraysize);

        id = _depositList[LIST_START_ID].nextId;
        uint256 i;
        while (id != 0) {
            if (_depositList[id].depositor == depositor_) {
                depositIds_[i] = id;
                i++;
            }
            id = _depositList[id].nextId;
        }
    }

    function maintainDepositList() internal {
        uint256 id = _depositList[LIST_START_ID].nextId;
        while (id != 0 && _depositList[id].expireTime <= block.timestamp) {
            uint256 rewardsPerShare = updateRewardsPerShare(_depositList[id].shares, false, _depositList[id].expireTime);
            uint256 rewards = (rewardsPerShare - _depositList[id].rewardsPerShare) * _depositList[id].shares;
            _pendingRewards[_depositList[id].depositor] += int256(rewards);

            _withdrawableAssets[_depositList[id].depositor] += _depositList[id].deposit;
            emit LogExpiredDeposit(_depositList[id].depositor, _depositList[id].deposit, rewards);

            uint256 nextId = _depositList[id].nextId;
            delete _depositList[id];

            id = nextId;
            _depositList[LIST_START_ID].nextId = nextId;
        }
    }

    function getRewardsPerShare(uint256 timestamp_) internal view returns (uint256 rewardsPerShare_) {
        rewardsPerShare_ =
            _lastRewardsPerShare + (timestamp_ - _lastRewardUpdateTime) * REWARDS_PER_SECOND / _totalShares;
    }

    function isValid(uint256 expireTime_, uint256 hint_) internal view returns (bool valid_) {
        if (
            _depositList[hint_].expireTime <= expireTime_
                && _depositList[_depositList[hint_].nextId].expireTime >= expireTime_
        ) {
            valid_ = true;
        }
    }

    function updateRewardsPerShare(uint256 shareVariation_, bool positiveVariation_, uint256 timeStamp_)
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
