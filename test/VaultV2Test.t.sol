// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol";
import { UUPSProxy } from "src/src-default/UUPSProxy.sol";
import { VaultFixture } from "./utils/VaultFixture.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { IVaultV2 } from "src/src-default/interfaces/IVaultV2.sol";
import { Vault } from "src/src-default/Vault.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { OFToken } from "src/src-default/OFToken.sol";

contract VaultV2Test is Test, VaultFixture {
    address public lzEndpoint;

    function setUp() public override {
        super.setUp();

        lzEndpoint = address(0);

        VaultV2 vaultImplementation = new VaultV2();
        bytes memory initializeData =
            abi.encodeWithSignature("initialize(address,address)", address(LPtoken), lzEndpoint);
        vm.startPrank(deployer);
        vault = Vault(address(new UUPSProxy(address(vaultImplementation), initializeData)));
        vm.stopPrank();
        rewardToken = vault.rewardToken();
    }

    function testOFToken_transfer() external {
        OFToken token = new OFToken(alice, "Token", "TKN", lzEndpoint);

        vm.startPrank(bob);
        vm.expectRevert(OFToken.UnauthorizedError.selector);
        token.mintRewards(alice, 10);
        vm.stopPrank();

        vm.startPrank(alice);
        token.mintRewards(alice, 10);
        require(token.balanceOf(alice) == 10, "Failed to setup OFToken");
        token.transfer(bob, 10);
        require(token.balanceOf(bob) == 10, "Failed to setup OFToken");
        vm.stopPrank();
    }

    function testVaultV2_Deposit() external {
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
