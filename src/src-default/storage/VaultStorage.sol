// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OFToken } from "../OFToken.sol";
import { IVault } from "../interfaces/IVault.sol";

contract VaultStorage {

    uint128 internal _totalShares;
    uint128 internal _lastRewardsPerShare;
    uint64 internal _lastRewardUpdateTime;
    uint64 internal _idCounter;
    address internal _owner;
    bool internal _initialized;

    mapping(address => uint128) internal _withdrawableAssets;
    mapping(address => int128) internal _pendingRewards; //can be negative
    mapping(uint64 => IVault.Deposit) internal _depositList;

    IERC20 public asset;
    OFToken public rewardToken;
}
