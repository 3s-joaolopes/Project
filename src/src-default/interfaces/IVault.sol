// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IVault {
    struct Deposit {
        address depositor;
        uint128 deposit;
        uint128 shares; //deposit x multiplier
        uint128 rewardsPerShare;
        uint64 expireTime;
        uint64 nextId;
    }

    event LogDeposit(address indexed address_, uint128 amount_, uint64 monthsLocked_);
    event LogWithdraw(address indexed address_, uint128 amount_);
    event LogClaimRewards(address indexed address_, uint128 amount_);
    event LogExpiredDeposit(address indexed address_, uint128 deposit_, uint128 rewards_);

    error UnauthorizedError();
    error AlreadyInitializedError();
    error NoAssetToWithdrawError();
    error NoRewardsToClaimError();
    error InvalidHintError();
    error InvalidLockPeriodError();
    error InsuficientDepositAmountError();
    error AssetTransferError();

    /// @notice Deposit Uniswap LP tokens and lock them to earn rewards
    /// @param amount_        Amount of Uniswap LP tokens to deposit
    /// @param monthsLocked_  Locking period, in months: 6, 12, 24 or 48
    /// @param hint_          Hint for insert position on the sorted list
    function deposit(uint128 amount_, uint64 monthsLocked_, uint64 hint_) external;

    /// @notice Withdraw LP tokens after lock period has expired
    function withdraw() external;

    /// @notice Transfer claimable rewards to msg.sender
    /// @param  depositIds_  Ids of the deposits held by msg.sender
    function claimRewards(uint64[] calldata depositIds_) external;

    /// @notice The amount of asset a depositor can withdraw
    /// @dev    Since the deposit list isn't updated, the result isn't garanteed to be fully up-to-date
    /// @param  depositor_    address of the depositor
    /// @return amount_       amount that can be withdrawn
    function getWithdrawableAmount(address depositor_) external view returns (uint128 amount_);

    /// @notice The amount of reward tokens that can be claimed by a depositor
    /// @dev    Since the deposit list isn't updated, the result isn't garanteed to be fully up-to-date
    /// @param  depositor_   address of the depositor
    /// @param  depositIds_  Ids of the deposits held by depositor_
    /// @return amount_      amount that can be claimed
    function getClaimableRewards(address depositor_, uint64[] calldata depositIds_)
        external
        view
        returns (uint128 amount_);

    /// @notice The insert position on the sorted list
    /// @param  expireTime_   the expire time of a deposit
    /// @return hint_       insert position on the sorted list
    function getInsertPosition(uint64 expireTime_) external view returns (uint64 hint_);

    /// @notice The deposit ids of all the active deposits held by a depositor
    /// @param  depositor_    address of the depositor
    /// @return depositIds_   deposit ids
    function getDepositIds(address depositor_) external view returns (uint64[] memory depositIds_);
}
