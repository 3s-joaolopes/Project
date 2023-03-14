// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol"; // to get console.log

import { VaultFixture } from "./utils/VaultFixture.sol";
import { Vault } from "src/src-default/Vault.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";

contract VaultTest is Test, VaultFixture {

    function setUp() public override {
        super.setUp();

        vault = new Vault();
        vault.initialize(address(LPtoken));
        rewardToken = vault.rewardToken();
    }

    function testVault_AlreadyInitialized() external {
        vm.startPrank(alice);
        vm.expectRevert(IVault.AlreadyInitializedError.selector);
        vault.initialize(address(0));
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
        uint256[] memory depositIds = vault.getDepositIds(alice);
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
        uint256 monthsLocked = 10;
        uint256 hint = vault.getInsertPosition(block.timestamp + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vm.expectRevert(IVault.InvalidLockPeriodError.selector);
        vault.deposit(ALICE_INITIAL_LP_BALANCE, monthsLocked, hint);
        vm.stopPrank();
    }

    function testVault_Deposit() external {
        uint256 monthsLocked;
        uint256 hint;
        uint256[] memory depositIds;

        vm.warp(time);

        // Alice deposits all her LPtokens for 6 months
        vm.startPrank(alice);
        monthsLocked = 6;
        hint = vault.getInsertPosition(block.timestamp + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vault.deposit(ALICE_INITIAL_LP_BALANCE, monthsLocked, hint);
        require(LPtoken.balanceOf(alice) == 0, "Failed to assert alice balance after deposit");

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Alice checks claimable rewards
        uint256 expectedValue = 317 * SECONDS_IN_30_DAYS * 6;
        depositIds = vault.getDepositIds(alice);
        console.log(
            "Alice 6 month rewards:",
            vault.claimableRewards(alice, depositIds),
            "->",
            expectedValue
        );
        require( similar(vault.claimableRewards(alice, depositIds), expectedValue), "Incorrect claimableRewards");

        // Alice withdraws her deposit and claims her rewards
        vault.withdraw();
        depositIds = vault.getDepositIds(alice);
        vault.claimRewards(depositIds);
        require(similar(rewardToken.balanceOf(alice), expectedValue), "Incorrect rewards 2");
        vm.stopPrank();
    }

    function testVault_Scenario1() external {
        uint256 monthsLocked;
        uint256 hint;
        uint256[] memory depositIds;
        uint256 expectedValue;

        vm.warp(time);

        // Alice deposits all her LPtokens for 6 months
        vm.startPrank(alice);
        monthsLocked = 6;
        hint = vault.getInsertPosition(block.timestamp + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vault.deposit(ALICE_INITIAL_LP_BALANCE, monthsLocked, hint);
        require(LPtoken.balanceOf(alice) == 0, "Failed to assert alice balance after deposit");
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
        vault.deposit(BOB_INITIAL_LP_BALANCE, monthsLocked, 100);
        require(LPtoken.balanceOf(bob) == 0, "Failed to assert bob balance after deposit");
        vm.stopPrank();

        // Alice claims her rewards and tries to withdraw before lock period
        vm.startPrank(alice);
        depositIds = vault.getDepositIds(alice);
        vault.claimRewards(depositIds);
        console.log("Month 3. Alice rewards:", rewardToken.balanceOf(alice), "->", 317 * SECONDS_IN_30_DAYS * 3);
        require(similar(rewardToken.balanceOf(alice), 317 * SECONDS_IN_30_DAYS * 3), "Incorrect rewards 1");
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
        expectedValue = 317 * SECONDS_IN_30_DAYS * 3 + 317 * SECONDS_IN_30_DAYS * 3 / 5;
        console.log(
            "Month 8. Alice rewards:",
            rewardToken.balanceOf(alice),
            "->",
            expectedValue
        );
        require(similar(rewardToken.balanceOf(alice), expectedValue), "Incorrect rewards 2");
        vm.stopPrank();

        // Bob claims rewards and tries to withdraw deposit
        vm.startPrank(bob);
        depositIds = vault.getDepositIds(bob);
        vault.claimRewards(depositIds);
        expectedValue = 317 * SECONDS_IN_30_DAYS * 3 * 4 / 5 + 317 * SECONDS_IN_30_DAYS * 2;
        console.log(
            "Month 8. Bob rewards:",
            rewardToken.balanceOf(bob),
            "->",
            expectedValue
        );
        require(similar(rewardToken.balanceOf(bob), expectedValue), "Incorrect rewards 2");
        vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Alice tries to claim bob's rewards
        vm.startPrank(alice);
        depositIds = vault.getDepositIds(bob);
        vm.expectRevert(IVault.InvalidHintError.selector);
        vault.claimRewards(depositIds);
        vm.stopPrank();

        // Bob withdraws deposit and claims rewards
        vm.startPrank(bob);
        vault.withdraw();
        depositIds = vault.getDepositIds(bob);
        vault.claimRewards(depositIds);
        vm.stopPrank();

        // Print reward token balances
        expectedValue = 317 * SECONDS_IN_30_DAYS * 3 + 317 * SECONDS_IN_30_DAYS * 3 / 5;
        console.log(
            "Month 20. Alice rewards:",
            rewardToken.balanceOf(alice),
            "->",
            expectedValue
        );
        require(similar(rewardToken.balanceOf(alice), expectedValue), "Incorrect rewards 3");
        expectedValue = 317 * SECONDS_IN_30_DAYS * 3 * 4 / 5 + 317 * SECONDS_IN_30_DAYS * 9;
        console.log(
            "Month 20. Bob rewards:",
            rewardToken.balanceOf(bob),
            "->",
            expectedValue
        );
        require(similar(rewardToken.balanceOf(bob), expectedValue), "Incorrect rewards 4");
        expectedValue = 317 * SECONDS_IN_30_DAYS * 15;
        console.log(
            "Total rewards:",
            rewardToken.balanceOf(alice) + rewardToken.balanceOf(bob),
            "->",
            expectedValue
        );
        require(similar(rewardToken.balanceOf(alice) + rewardToken.balanceOf(bob), expectedValue), "Incorrect rewards 4");

        // Check if withdrawls were successful
        uint256 balance = LPtoken.balanceOf(alice);
        require(balance == ALICE_INITIAL_LP_BALANCE, "Failed to assert alice's balance");

        balance = LPtoken.balanceOf(bob);
        require(balance == BOB_INITIAL_LP_BALANCE, "Failed to assert bob's balance");
    }
}