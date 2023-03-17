// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OFToken } from "../OFToken.sol";
import { IVault } from "../interfaces/IVault.sol";

contract VaultStorage {
    uint128 internal _totalShares; // The total number of outstanding vault shares
    uint128 internal _lastRewardsPerShare; // The amount of rewards per share on the last list update
    uint64 internal _lastRewardUpdateTime; // The unix time of the last deposit list update
    uint64 internal _idCounter; // The internal counter the generate a nonce for every deposit
    address internal _owner; // The address of the owner of the vault
    bool internal _initialized; // The status of the contract

    mapping(address => uint128) internal _withdrawableAssets; // The amount of asset a depositor can withdraw
    mapping(address => int128) internal _pendingRewards; // The amount of rewards a depositor can claim. It can be negative as it decreases everytime rewards are claimed but only increases when the deposit expires
    mapping(uint64 => IVault.Deposit) internal _depositList; // The sorted list of deposits

    IERC20 public asset; // The ERC20 token to use as the asset for deposits
    OFToken public rewardToken; // The ERC20 token used to distribute rewards
}
