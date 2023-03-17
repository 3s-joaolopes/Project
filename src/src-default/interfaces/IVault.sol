// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IVault {
    struct Deposit {
        uint256 expireTime;
        address depositor;
        uint256 deposit;
        uint256 shares; //deposit x multiplier
        uint256 rewardsPerShare;
        uint256 nextId;
    }

    event LogDeposit(address indexed address_, uint256 amount_, uint256 monthsLocked_);
    event LogWithdraw(address indexed address_, uint256 amount_);
    event LogClaimRewards(address indexed address_, uint256 amount_);
    event LogExpiredDeposit(address indexed address_, uint256 deposit_, uint256 rewards_);

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
    function deposit(uint256 amount_, uint256 monthsLocked_, uint256 hint_) external;

    /// @notice Withdraw LP tokens after lock period has expired
    function withdraw() external;

    /// @notice Transfer claimable rewards to msg.sender
    /// @param  depositIds_  Ids of the deposits held by msg.sender
    function claimRewards(uint256[] calldata depositIds_) external;

    /// @notice Get the deposit ids of the deposits held by a depositor
    /// @param  depositor_    address of the depositor
    /// @return amount_   deposit ids
    function getWithdrawableAmount(address depositor_) external view returns (uint256 amount_);

    /// @notice Get amount of reward tokens that can be claimed by depositor_
    /// @param  depositor_   address of the depositor
    /// @param  depositIds_  Ids of the deposits held by depositor_
    /// @return amount_      amount that can be claimed
    function getclaimableRewards(address depositor_, uint256[] calldata depositIds_)
        external
        view
        returns (uint256 amount_);

    /// @notice Get the insert position on the sorted list
    /// @param  expireTime_   the expire time of a deposit
    /// @return hint_       insert position on the sorted list
    function getInsertPosition(uint256 expireTime_) external view returns (uint256 hint_);

    /// @notice Get the deposit ids of the deposits held by a depositor
    /// @param  depositor_    address of the depositor
    /// @return depositIds_   deposit ids
    function getDepositIds(address depositor_) external view returns (uint256[] memory depositIds_);
}
