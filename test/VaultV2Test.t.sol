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

        VaultV2 vaultImplementation_chain1 = new VaultV2();
        VaultV2 vaultImplementation_chain2 = new VaultV2();

        vm.startPrank(deployer);
        // Deploy and initialize vaultv2 on chain 1
        bytes memory initializeData =
            abi.encodeWithSignature("initialize(address,address)", address(LPtoken), address(endpoint1));
        vaultv2_chain1 = VaultV2(address(new UUPSProxy(address(vaultImplementation_chain1), initializeData)));
        rewardToken_chain1 = vaultv2_chain1.rewardToken();

        // Deploy and initialize vaultv2 on chain 2
        initializeData =
            abi.encodeWithSignature("initialize(address,address)", address(LPtoken), address(endpoint2));
        vaultv2_chain2 = VaultV2(address(new UUPSProxy(address(vaultImplementation_chain2), initializeData)));
        rewardToken_chain2 = vaultv2_chain2.rewardToken();

        bytes memory trustedRemoteAddress = abi.encodePacked(address(vaultv2_chain2), address(vaultv2_chain2));
        vaultv2_chain1.addTrustedRemoteAddress(CHAIN_ID_2, trustedRemoteAddress);
        trustedRemoteAddress = abi.encodePacked(address(vaultv2_chain1), address(vaultv2_chain1));
        vaultv2_chain2.addTrustedRemoteAddress(CHAIN_ID_1, trustedRemoteAddress);

        endpoint1.setDestLzEndpoint(address(vaultv2_chain2), address(endpoint2));
        endpoint2.setDestLzEndpoint(address(vaultv2_chain1), address(endpoint1));

        vm.stopPrank();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(address(vaultv2_chain1), 100 ether);
        vm.deal(address(vaultv2_chain2), 100 ether);
    }

    function testOFToken_transfer() external {
        OFToken token_chain1 = new OFToken(alice, "Token", "TKN", address(endpoint1));
        OFToken token_chain2 = new OFToken(deployer, "Token", "TKN", address(endpoint2));

        // mint rewards without authorization
        vm.startPrank(bob);
        vm.expectRevert(OFToken.UnauthorizedError.selector);
        token_chain1.mintRewards(alice, 10);
        vm.stopPrank();

        // single-chain transfer
        vm.startPrank(alice);
        token_chain1.mintRewards(alice, 10);
        require(token_chain1.balanceOf(alice) == 10, "Failed to mint OFToken");
        token_chain1.transfer(bob, 10);
        require(token_chain1.balanceOf(bob) == 10, "Failed single-chain transfer of OFToken");
        vm.stopPrank();

        // multi-chain transfer
        vm.startPrank(alice);
        token_chain1.mintRewards(alice, 10);
        bytes memory remoteAndLocalAddresses = abi.encodePacked(bob, address(token_chain2));
        token_chain1.sendFrom(alice, CHAIN_ID_2, remoteAndLocalAddresses, 10, payable(alice), address(0x0), bytes(""));
        require(token_chain2.balanceOf(bob) == 10, "Failed multi-chain transfer of OFToken");
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

    function testVaultV2_MultiChainDeposit() external {
        vm.warp(time);

        // Alice deposits all her LPtokens on chain1 for 6 months 
        vm.startPrank(alice);
        uint256 monthsLocked = 6;
        uint256 hint = vaultv2_chain1.getInsertPosition(block.timestamp + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vaultv2_chain1), ALICE_INITIAL_LP_BALANCE);
        vaultv2_chain1.deposit(ALICE_INITIAL_LP_BALANCE, monthsLocked, hint);
        require(LPtoken.balanceOf(alice) == 0, "Failed to assert alice balance after deposit");
        vm.stopPrank();

        // bob deposits all his LPtokens on chain2 for 12 months
        vm.startPrank(bob);
        monthsLocked = 12;
        hint = vaultv2_chain2.getInsertPosition(block.timestamp + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vaultv2_chain2), BOB_INITIAL_LP_BALANCE);
        vaultv2_chain2.deposit(BOB_INITIAL_LP_BALANCE, monthsLocked, hint);
        require(LPtoken.balanceOf(bob) == 0, "Failed to assert bob balance after deposit");
        vm.stopPrank();

        uint256 totalShares_chain1 = uint256(vm.load(address(vaultv2_chain1), bytes32(uint256(102))));
        uint256 totalShares_chain2 = uint256(vm.load(address(vaultv2_chain2), bytes32(uint256(102))));
        console.log("Number of shares:", totalShares_chain1, "<->", totalShares_chain2);

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        /*
        // Alice withdraws her deposit and claims her rewards
        vm.startPrank(alice);
        vaultv2_chain1.withdraw();
        uint256[] memory depositIds = vaultv2_chain1.getDepositIds(alice);
        vaultv2_chain1.claimRewards(depositIds);
        uint256 expectedValue = REWARDS_PER_MONTH * 6;
        require(similar(rewardToken_chain1.balanceOf(alice), expectedValue), "Incorrect rewards"); 
        vm.stopPrank();*/
    }
}


        /*
        vm.record();
        contract.variable();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(contract));
        console.log("reads size:", uint256(reads.length));
        console.log("reads 0:", uint256(reads[0]));
        console.log("reads 1:", uint256(reads[1]));*/