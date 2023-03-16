// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol";

import { UUPSProxy } from "src/src-default/UUPSProxy.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { VaultFixture } from "./utils/VaultFixture.sol";
import { Vault } from "src/src-default/Vault.sol";
import { VaultTest } from "./VaultTest.t.sol";

contract ProxyTest is Test, VaultFixture {
    function setUp() public override {
        super.setUp();

        Vault vaultImplementation = new Vault();
        bytes memory initializeData = abi.encodeWithSignature("initialize(address)", address(LPtoken));
        vm.startPrank(deployer);
        vault = Vault(address(new UUPSProxy(address(vaultImplementation), initializeData)));
        vm.stopPrank();
        rewardToken = vault.rewardToken();
    }

    function testProxy_Unauthorized() external {
        vm.startPrank(alice);
        vm.expectRevert(IVault.UnauthorizedError.selector);
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
        vm.expectRevert(IVault.AlreadyInitializedError.selector);
        vault.initialize(address(LPtoken));
        vm.stopPrank();
    }

    function testProxy_Deposit() external {
        vm.warp(time);

        // Alice deposits all her LPtokens for 6 months
        vm.startPrank(alice);
        uint256 monthsLocked = 6;
        uint256 hint = vault.getInsertPosition(block.timestamp + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vault.deposit(ALICE_INITIAL_LP_BALANCE, monthsLocked, hint);
        require(LPtoken.balanceOf(alice) == 0, "Failed to assert alice balance after deposit");

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Alice withdraws her deposit and claims her rewards
        vault.withdraw();
        uint256[] memory depositIds = vault.getDepositIds(alice);
        vault.claimRewards(depositIds);
        uint256 expectedValue = REWARDS_PER_MONTH * 6;
        require(similar(rewardToken.balanceOf(alice), expectedValue), "Incorrect rewards");
        vm.stopPrank();
    }
}
