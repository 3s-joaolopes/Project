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
    event LogExpiredDeposit(address indexed address_, uint256 deposit, uint256 rewards);

    error Unauthorized();
    error AlreadyInitializedError();
    error NoAssetToWithdrawError();
    error NoRewardsToClaimError();
    error InvalidHintError();
    error InvalidLockPeriodError();
    error InsuficientDepositAmountError();

    /// @notice Deposit Uniswap LP tokens and lock them to earn rewards
    /// @param amount_        Amount of Uniswap LP tokens to deposit
    /// @param monthsLocked_  Locking period, in months: 6, 12, 24 or 48
    /// @param hint_          Hint for insert position on the sorted list
    function deposit(uint256 amount_, uint256 monthsLocked_, uint256 hint_) external;

    /// @notice Withdraw LP tokens after lock period has expired
    function withdraw() external;

    /// @notice Transfer claimable rewards to msg.sender
    function claimRewards(uint256[] calldata depositIds_) external;

    /// @notice The amount of reward tokens that can be claimed by depositor_
    function claimableRewards(address depositor_, uint256[] calldata depositIds_)
        external
        view
        returns (uint256 amount_);

    /// @notice The insert position on the sorted list
    function getInsertPosition(uint256 expireTime_) external view returns (uint256 hint_);

    /// @notice The deposits held by a depositor
    function getDepositIds(address depositor_) external view returns (uint256[] memory depositIds_);

    /// @notice Upgrade delegate implementation
    function upgrade(address newImplementation_) external;

    /// @dev Check if a hint is valid
    //function isValid(uint256 expireTime_, uint256 hint_) internal view returns (bool valid_);

    /// @dev Mint reward tokens based on time since lastMintTime
    //function mintRewardTokens() internal;

    /// @dev Close all deposits that have expired
    //function maintainDepositList() internal;

    /// @dev Verify if the insert positoin in valid
    //function validPosition(uint256 expireTime_, uint256 hint_) external view returns (bool);
}
