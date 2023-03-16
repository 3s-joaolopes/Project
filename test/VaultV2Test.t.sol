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
import { LZEndpointMock } from "@layerZero/mocks/LZEndpointMock.sol";

contract VaultV2Test is Test, VaultFixture {
    uint16 constant CHAIN_ID_1 = 1;
    uint16 constant CHAIN_ID_2 = 2;

    LZEndpointMock endpoint1;
    LZEndpointMock endpoint2;

    VaultV2 public vaultv2_chain1;
    VaultV2 public vaultv2_chain2;

    OFToken public rewardToken_chain1;
    OFToken public rewardToken_chain2;

    function setUp() public override {
        super.setUp();

        endpoint1 = new LZEndpointMock(CHAIN_ID_1);
        endpoint2 = new LZEndpointMock(CHAIN_ID_2);
        endpoint1.setDestLzEndpoint(address(vaultv2_chain2), address(endpoint1));
        endpoint2.setDestLzEndpoint(address(vaultv2_chain1), address(endpoint2));

        VaultV2 vaultImplementation = new VaultV2();

        vm.startPrank(deployer);
        bytes memory initializeData =
            abi.encodeWithSignature("initialize(address,address)", address(LPtoken), address(endpoint1));
        vaultv2_chain1 = VaultV2(address(new UUPSProxy(address(vaultImplementation), initializeData)));
        rewardToken_chain1 = vaultv2_chain1.rewardToken();
        vm.stopPrank();
    }

    function testOFToken_transfer() external {
        OFToken token = new OFToken(alice, "Token", "TKN", address(endpoint1));

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
        uint256 hint = vaultv2_chain1.getInsertPosition(block.timestamp + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vaultv2_chain1), ALICE_INITIAL_LP_BALANCE);
        vaultv2_chain1.deposit(ALICE_INITIAL_LP_BALANCE, monthsLocked, hint);
        require(LPtoken.balanceOf(alice) == 0, "Failed to assert alice balance after deposit");

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Alice withdraws her deposit and claims her rewards
        vaultv2_chain1.withdraw();
        uint256[] memory depositIds = vaultv2_chain1.getDepositIds(alice);
        vaultv2_chain1.claimRewards(depositIds);
        uint256 expectedValue = REWARDS_PER_MONTH * 6;
        require(similar(rewardToken_chain1.balanceOf(alice), expectedValue), "Incorrect rewards");
        vm.stopPrank();
    }
}
