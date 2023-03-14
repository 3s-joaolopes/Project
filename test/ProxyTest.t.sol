// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol";

import { UUPSProxy } from "src/src-default/UUPSProxy.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { VaultFixture } from "./utils/VaultFixture.sol";
import { Vault } from "src/src-default/Vault.sol";
import { VaultTest } from "./VaultTest.t.sol";


contract ProxyTest is Test, VaultFixture {
    Vault vaultImplementation;

    function setUp() public override {
        super.setUp();

        vaultImplementation = new Vault();
        bytes memory initializeData = abi.encodeWithSignature("initialize(address)", address(LPtoken));
        vm.startPrank(deployer);
        vault = Vault(address(new UUPSProxy(address(vaultImplementation), initializeData)));
        vm.stopPrank();
        rewardToken = vault.rewardToken();
    }

    function testProxy_Unauthorized() external {
        vm.startPrank(alice);
        vm.expectRevert(IVault.Unauthorized.selector);
        vault.upgradeTo(address(0));
        vm.stopPrank();
    }

    function testVault_AlreadyInitialized() external {
        vm.startPrank(alice);
        vm.expectRevert(IVault.AlreadyInitializedError.selector);
        vault.initialize(address(0));
        vm.stopPrank();
    }

    function testProxy_Upgrade() external {
        Vault vaultImplementationUpgrade = new Vault();
        vm.startPrank(deployer);
        vault.upgradeTo(address(vaultImplementationUpgrade));
        vm.stopPrank();
    }

    function testProxy_Deposit() external {
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
}
