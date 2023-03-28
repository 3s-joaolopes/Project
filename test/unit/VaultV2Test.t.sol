// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { console2 } from "@forge-std/console2.sol";
import { UUPSProxy } from "src/src-default/UUPSProxy.sol";
import { VaultFixture } from "./../utils/VaultFixture.sol";
import { LayerZeroHelper } from "./../utils/LayerZeroHelper.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { IVaultV2 } from "src/src-default/interfaces/IVaultV2.sol";
import { Vault } from "src/src-default/Vault.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { OFToken } from "src/src-default/OFToken.sol";
import { LZEndpointMock } from "@layerZero/mocks/LZEndpointMock.sol";
import { Lib } from "test/utils/Library.sol";

contract VaultV2Test is Test, LayerZeroHelper {
    uint256 public constant ALICE_INITIAL_LP_BALANCE = 1 ether;
    uint256 public constant BOB_INITIAL_LP_BALANCE = 2 ether;
    uint16 constant CHAIN_ID_1 = 1;
    uint16 constant CHAIN_ID_2 = 2;

    VaultV2 public vaultv2_chain1;
    VaultV2 public vaultv2_chain2;

    LZEndpointMock endpoint1;
    LZEndpointMock endpoint2;

    OFToken public rewardToken_chain1;
    OFToken public rewardToken_chain2;

    function setUp() public override {
        super.setUp();

        giveLPtokens(alice, ALICE_INITIAL_LP_BALANCE);
        giveLPtokens(bob, BOB_INITIAL_LP_BALANCE);

        uint16[] memory chainIds_ = new uint16[](2);
        chainIds_[0] = CHAIN_ID_1;
        chainIds_[1] = CHAIN_ID_2;
        (address[] memory vaultsv2_, address[] memory endpoints_, address[] memory rewardTokens_) =
            this.deployBatchOnChain(chainIds_);
        connectVaults(chainIds_, vaultsv2_, endpoints_);

        vaultv2_chain1 = VaultV2(vaultsv2_[0]);
        endpoint1 = LZEndpointMock(endpoints_[0]);
        rewardToken_chain1 = OFToken(rewardTokens_[0]);

        vaultv2_chain2 = VaultV2(vaultsv2_[1]);
        endpoint2 = LZEndpointMock(endpoints_[1]);
        rewardToken_chain2 = OFToken(rewardTokens_[1]);
    }

    function testVaultV2_UpgradeFromV1() external {
        vm.warp(time);

        // Initialize vaultv1
        vm.startPrank(deployer);
        Vault vaultImplementation = new Vault();
        bytes memory initializeData =
            abi.encodeWithSignature("initialize(address,address)", address(LPtoken), address(endpoint1));
        Vault vault = Vault(address(new UUPSProxy(address(vaultImplementation), initializeData)));
        OFToken rewardToken = vault.rewardToken();
        vm.stopPrank();

        // Alice deposits all her LPtokens for 6 months
        vm.startPrank(alice);
        uint64 monthsLocked = 6;
        uint64 hint = vault.getInsertPosition(uint64(block.timestamp) + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vault.deposit(uint128(ALICE_INITIAL_LP_BALANCE), monthsLocked, hint);
        assert(LPtoken.balanceOf(alice) == 0);
        vm.stopPrank();

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Upgrade to vault v2
        vm.startPrank(deployer);
        VaultV2 vaultV2Implementation = new VaultV2();
        vault.upgradeTo(address(vaultV2Implementation));
        VaultV2 vaultv2 = VaultV2(address(vault));
        vaultv2.resetTrustedRemoteAddresses();
        bytes memory trustedRemoteAddress = abi.encodePacked(address(vaultv2_chain2), address(vaultv2));
        vaultv2.addTrustedRemoteAddress(CHAIN_ID_2, trustedRemoteAddress);
        vm.stopPrank();

        // Alice withdraws her deposit and claims her rewards
        vm.startPrank(alice);
        vaultv2.withdraw();
        uint64[] memory depositIds = vaultv2.getDepositIds(alice);
        vaultv2.claimRewards(depositIds);
        uint128 expectedValue = REWARDS_PER_MONTH * 6;
        assert(Lib.similar(rewardToken.balanceOf(alice), uint256(expectedValue)));
        vm.stopPrank();
    }

    function testVaultV2_Deposit() external {
        vm.warp(time);

        // Alice deposits all her LPtokens for 6 months
        vm.startPrank(alice);
        uint64 monthsLocked = 6;
        uint64 hint = vaultv2_chain1.getInsertPosition(uint64(block.timestamp) + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vaultv2_chain1), ALICE_INITIAL_LP_BALANCE);
        vaultv2_chain1.deposit(uint128(ALICE_INITIAL_LP_BALANCE), monthsLocked, hint);
        assert(LPtoken.balanceOf(alice) == 0);

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Alice withdraws her deposit and claims her rewards
        vaultv2_chain1.withdraw();
        uint64[] memory depositIds = vaultv2_chain1.getDepositIds(alice);
        vaultv2_chain1.claimRewards(depositIds);
        uint128 expectedValue = REWARDS_PER_MONTH * 6;
        assert(Lib.similar(rewardToken_chain1.balanceOf(alice), uint256(expectedValue)));
        vm.stopPrank();
    }

    function testVaultV2_MultiChainDeposit() external {
        vm.warp(time);

        // Alice deposits all her LPtokens on chain 1 for 6 months
        vm.startPrank(alice);
        uint64 monthsLocked = 6;
        uint64 hint = vaultv2_chain1.getInsertPosition(uint64(block.timestamp) + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vaultv2_chain1), ALICE_INITIAL_LP_BALANCE);
        vaultv2_chain1.deposit(uint128(ALICE_INITIAL_LP_BALANCE), monthsLocked, hint);
        assert(LPtoken.balanceOf(alice) == 0);
        vm.stopPrank();

        // Fast-forward 3 months
        vm.warp(time += 3 * SECONDS_IN_30_DAYS);

        // Bob deposits all his LPtokens on chain 2 for 12 months
        vm.startPrank(bob);
        monthsLocked = 12;
        hint = vaultv2_chain2.getInsertPosition(uint64(block.timestamp) + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vaultv2_chain2), BOB_INITIAL_LP_BALANCE);
        vaultv2_chain2.deposit(uint128(BOB_INITIAL_LP_BALANCE), monthsLocked, hint);
        assert(LPtoken.balanceOf(bob) == 0);
        vm.stopPrank();

        // Check if vaults are in sync
        uint256 totalShares_chain1 = uint256(vm.load(address(vaultv2_chain1), bytes32(uint256(101))));
        totalShares_chain1 = totalShares_chain1 & 0xffffffffffffffffffffffffffffffff;
        uint256 totalShares_chain2 = uint256(vm.load(address(vaultv2_chain2), bytes32(uint256(101))));
        totalShares_chain2 = totalShares_chain2 & 0xffffffffffffffffffffffffffffffff;
        console2.log("Number of shares in both chains:", totalShares_chain1, "<->", totalShares_chain2);
        uint128 expectedValue = uint128(ALICE_INITIAL_LP_BALANCE + BOB_INITIAL_LP_BALANCE * 2);
        assert(totalShares_chain1 == totalShares_chain2 && totalShares_chain2 == expectedValue);

        // Fast-forward 5 months
        vm.warp(time += 5 * SECONDS_IN_30_DAYS);

        // Alice withdraws her deposit and claims her rewards
        vm.startPrank(alice);
        vaultv2_chain1.withdraw();
        uint64[] memory depositIds = vaultv2_chain1.getDepositIds(alice);
        vaultv2_chain1.claimRewards(depositIds);
        expectedValue = REWARDS_PER_MONTH * 3 + REWARDS_PER_MONTH * 3 / 5;
        assert(Lib.similar(rewardToken_chain1.balanceOf(alice), uint256(expectedValue)));
        vm.stopPrank();

        // Bob claims rewards and tries to withdraw deposit
        vm.startPrank(bob);
        depositIds = vaultv2_chain2.getDepositIds(bob);
        vaultv2_chain2.claimRewards(depositIds);
        expectedValue = REWARDS_PER_MONTH * 3 * 4 / 5 + REWARDS_PER_MONTH * 2;
        console2.log("Bob rewards:", rewardToken_chain2.balanceOf(bob), "<->", uint256(expectedValue));
        assert(Lib.similar(rewardToken_chain2.balanceOf(bob), uint256(expectedValue)));
        vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
        vaultv2_chain2.withdraw();
        vm.stopPrank();

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Bob withdraws deposit and claims rewards
        vm.startPrank(bob);
        vaultv2_chain2.withdraw();
        depositIds = vaultv2_chain2.getDepositIds(bob);
        vaultv2_chain2.claimRewards(depositIds);
        vm.stopPrank();

        // Check if withdrawals were successful
        uint256 balance = LPtoken.balanceOf(alice);
        assert(balance == ALICE_INITIAL_LP_BALANCE);
        balance = LPtoken.balanceOf(bob);
        assert(balance == BOB_INITIAL_LP_BALANCE);
    }
}

/*
        //Change variable to public
        vm.record();
        contract.variable();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(contract));
        console2.log("reads size:", uint256(reads.length));
        console2.log("reads 0:", uint256(reads[0]));
        console2.log("reads 1 (should be the slot):", uint256(reads[1]));*/
