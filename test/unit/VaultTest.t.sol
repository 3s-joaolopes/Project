// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { console2 } from "@forge-std/console2.sol";
import { UniswapHelper } from "./../utils/UniswapHelper.sol";
import { Vault } from "src/src-default/Vault.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { OFToken } from "src/src-default/OFToken.sol";
import { Lib } from "test/utils/Library.sol";

contract VaultTest is Test, UniswapHelper {
    uint64 constant SECONDS_IN_30_DAYS = 2_592_000;
    uint128 constant REWARDS_PER_SECOND = 317;
    uint128 constant REWARDS_PER_MONTH = REWARDS_PER_SECOND * SECONDS_IN_30_DAYS;
    uint128 constant MIN_DEPOSIT = 1000;
    uint256 constant STARTING_TIME = 1000;

    uint256 public time = STARTING_TIME;
    uint256 public constant ALICE_INITIAL_LP_BALANCE = 1 ether;
    uint256 public constant BOB_INITIAL_LP_BALANCE = 2 ether;

    address public alice = vm.addr(1500);
    address public bob = vm.addr(1501);

    OFToken public rewardToken;
    Vault public vault;

    function setUp() public override {
        super.setUp();

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");

        giveLPtokens(alice, ALICE_INITIAL_LP_BALANCE);
        giveLPtokens(bob, BOB_INITIAL_LP_BALANCE);

        vault = new Vault();
        vault.initialize(address(LPtoken), address(0));
        rewardToken = vault.rewardToken();
    }

    function testVault_AlreadyInitialized() external {
        vm.startPrank(alice);
        vm.expectRevert(IVault.AlreadyInitializedError.selector);
        vault.initialize(address(0), address(0));
        vm.stopPrank();
    }

    function testVault_NotDelegateCall() external {
        vm.startPrank(alice);
        vm.expectRevert(bytes("Function must be called through delegatecall"));
        vault.upgradeTo(address(0));
        vm.stopPrank();
    }

    function testVault_NoDeposit() external {
        // Alice tries to claim rewards and withdraw deposit without depositing
        vm.startPrank(alice);
        uint64[] memory depositIds = vault.getDepositIds(alice);
        vm.expectRevert(IVault.NoRewardsToClaimError.selector);
        vault.claimRewards(depositIds);
        vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();
    }

    function testVault_InsuficientDepositAmount() external {
        vm.startPrank(alice);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vm.expectRevert(IVault.InsuficientDepositAmountError.selector);
        vault.deposit(1, 6, 100);
        vm.stopPrank();
    }

    function testVault_InvalidLockPeriod() external {
        // Alice tries to make a deposit locked for 10 months
        vm.startPrank(alice);
        uint64 monthsLocked = 10;
        uint64 hint = vault.getInsertPosition(uint64(block.timestamp) + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vm.expectRevert(IVault.InvalidLockPeriodError.selector);
        vault.deposit(uint128(ALICE_INITIAL_LP_BALANCE), monthsLocked, hint);
        vm.stopPrank();
    }

    function testVault_Deposit() external {
        uint64 monthsLocked;
        uint64 hint;
        uint64[] memory depositIds;

        vm.warp(time);

        // Alice deposits all her LPtokens for 6 months
        vm.startPrank(alice);
        monthsLocked = 6;
        hint = vault.getInsertPosition(uint64(block.timestamp) + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vault.deposit(uint128(ALICE_INITIAL_LP_BALANCE), monthsLocked, hint);
        assert(LPtoken.balanceOf(alice) == 0);

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Alice withdraws her deposit
        vault.withdraw();
        uint256 balance = LPtoken.balanceOf(alice);
        assert(balance == ALICE_INITIAL_LP_BALANCE);

        // Alice claims her rewards
        uint128 expectedValue = REWARDS_PER_MONTH * 6;
        depositIds = vault.getDepositIds(alice);
        assert(Lib.similar(vault.getClaimableRewards(alice, depositIds), uint256(expectedValue)));
        vault.claimRewards(depositIds);
        assert(Lib.similar(rewardToken.balanceOf(alice), uint256(expectedValue)));
        vm.stopPrank();
    }

    function testVault_TwoDeposits() external {
        uint64 monthsLocked;
        uint64 hint;
        uint64[] memory depositIds;

        vm.warp(time);

        // Bob deposits half his LPtokens for 6 months
        vm.startPrank(bob);
        monthsLocked = 6;
        hint = vault.getInsertPosition(uint64(block.timestamp) + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), BOB_INITIAL_LP_BALANCE / 2);
        vault.deposit(uint128(BOB_INITIAL_LP_BALANCE / 2), monthsLocked, hint);
        assert(LPtoken.balanceOf(bob) == BOB_INITIAL_LP_BALANCE / 2);

        // Fast-forward 3 months
        vm.warp(time += 3 * SECONDS_IN_30_DAYS);

        // Bob makes another deposit for half his LPtokens (this time locked for 12 months)
        monthsLocked = 12;
        hint = vault.getInsertPosition(uint64(block.timestamp) + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), BOB_INITIAL_LP_BALANCE / 2);
        vault.deposit(uint128(BOB_INITIAL_LP_BALANCE / 2), monthsLocked, hint);
        assert(LPtoken.balanceOf(bob) == 0);

        // Bob claims rewards
        depositIds = vault.getDepositIds(bob);
        vault.claimRewards(depositIds);
        uint128 expectedValue = REWARDS_PER_MONTH * 3;
        assert(Lib.similar(rewardToken.balanceOf(bob), uint256(expectedValue)));

        // Fast-forward 9 months
        vm.warp(time += 9 * SECONDS_IN_30_DAYS);

        // Bob withdraws 1st deposit and claims rewards
        vault.withdraw();
        depositIds = vault.getDepositIds(bob);
        vault.claimRewards(depositIds);
        expectedValue = REWARDS_PER_MONTH * 12;
        assert(Lib.similar(rewardToken.balanceOf(bob), uint256(expectedValue)));

        // Fast-forward 6 months
        vm.warp(time += 3 * SECONDS_IN_30_DAYS);

        // Bob withdraws 2nd deposit and claims rewards
        vault.withdraw();
        depositIds = vault.getDepositIds(bob);
        vault.claimRewards(depositIds);
        expectedValue = REWARDS_PER_MONTH * 15;
        assert(Lib.similar(rewardToken.balanceOf(bob), uint256(expectedValue)));

        vm.stopPrank();
    }

    function testVault_Scenario1() external {
        uint64 monthsLocked;
        uint64 hint;
        uint64[] memory depositIds;
        uint128 expectedValue;

        vm.warp(time);

        // Alice deposits all her LPtokens for 6 months
        vm.startPrank(alice);
        monthsLocked = 6;
        hint = vault.getInsertPosition(uint64(block.timestamp) + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vault.deposit(uint128(ALICE_INITIAL_LP_BALANCE), monthsLocked, hint);
        assert(LPtoken.balanceOf(alice) == 0);
        vm.stopPrank();

        // Fast-forward 3 months
        vm.warp(time += 3 * SECONDS_IN_30_DAYS);

        // Bob tries to claim rewards and withdraw deposit
        vm.startPrank(bob);
        depositIds = vault.getDepositIds(bob);
        vm.expectRevert(IVault.NoRewardsToClaimError.selector);
        vault.claimRewards(depositIds);
        vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();

        // Bob deposits all his LPtokens for 1 year using invalid hint
        vm.startPrank(bob);
        monthsLocked = 12;
        LPtoken.approve(address(vault), BOB_INITIAL_LP_BALANCE);
        vault.deposit(uint128(BOB_INITIAL_LP_BALANCE), monthsLocked, 100);
        assert(LPtoken.balanceOf(bob) == 0);
        vm.stopPrank();

        // Alice claims her rewards and tries to withdraw before lock period
        vm.startPrank(alice);
        depositIds = vault.getDepositIds(alice);
        vault.claimRewards(depositIds);
        assert(Lib.similar(rewardToken.balanceOf(alice), uint256(REWARDS_PER_MONTH * 3)));
        vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();

        // Fast-forward 5 months
        vm.warp(time += 5 * SECONDS_IN_30_DAYS);

        // Alice withdraws her deposit and claims her rewards
        vm.startPrank(alice);
        vault.withdraw();
        depositIds = vault.getDepositIds(alice);
        vault.claimRewards(depositIds);
        expectedValue = REWARDS_PER_MONTH * 3 + REWARDS_PER_MONTH * 3 / 5;
        assert(Lib.similar(rewardToken.balanceOf(alice), uint256(expectedValue)));
        vm.stopPrank();

        // Bob claims rewards and tries to withdraw deposit
        vm.startPrank(bob);
        depositIds = vault.getDepositIds(bob);
        vault.claimRewards(depositIds);
        expectedValue = REWARDS_PER_MONTH * 3 * 4 / 5 + REWARDS_PER_MONTH * 2;
        assert(Lib.similar(rewardToken.balanceOf(bob), uint256(expectedValue)));
        vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();

        // Alice tries to claim bob's rewards
        vm.startPrank(alice);
        depositIds = vault.getDepositIds(bob);
        vm.expectRevert(IVault.InvalidHintError.selector);
        vault.claimRewards(depositIds);
        vm.stopPrank();

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Bob withdraws deposit and claims rewards
        vm.startPrank(bob);
        vault.withdraw();
        depositIds = vault.getDepositIds(bob);
        vault.claimRewards(depositIds);
        vm.stopPrank();

        // Print reward token balances
        expectedValue = REWARDS_PER_MONTH * 3 + REWARDS_PER_MONTH * 3 / 5;
        assert(Lib.similar(rewardToken.balanceOf(alice), uint256(expectedValue)));
        expectedValue = REWARDS_PER_MONTH * 3 * 4 / 5 + REWARDS_PER_MONTH * 9;
        assert(Lib.similar(rewardToken.balanceOf(bob), uint256(expectedValue)));
        expectedValue = REWARDS_PER_MONTH * 15;
        assert(Lib.similar(rewardToken.balanceOf(alice) + rewardToken.balanceOf(bob), uint256(expectedValue)));

        // Check if withdrawls were successful
        uint256 balance = LPtoken.balanceOf(alice);
        assert(balance == ALICE_INITIAL_LP_BALANCE);
        balance = LPtoken.balanceOf(bob);
        assert(balance == BOB_INITIAL_LP_BALANCE);
    }
}
