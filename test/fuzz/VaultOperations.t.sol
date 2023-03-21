// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol";
import { UUPSProxy } from "src/src-default/UUPSProxy.sol";
import { VaultFixture } from "./../utils/VaultFixture.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { IVaultV2 } from "src/src-default/interfaces/IVaultV2.sol";
import { Vault } from "src/src-default/Vault.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { OFToken } from "src/src-default/OFToken.sol";
import { LZEndpointMock } from "@layerZero/mocks/LZEndpointMock.sol";

contract DepositFuzzTests is Test, VaultFixture {
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
        initializeData = abi.encodeWithSignature("initialize(address,address)", address(LPtoken), address(endpoint2));
        vaultv2_chain2 = VaultV2(address(new UUPSProxy(address(vaultImplementation_chain2), initializeData)));
        rewardToken_chain2 = vaultv2_chain2.rewardToken();

        bytes memory trustedRemoteAddress = abi.encodePacked(address(vaultv2_chain2), address(vaultv2_chain1));
        vaultv2_chain1.addTrustedRemoteAddress(CHAIN_ID_2, trustedRemoteAddress);
        trustedRemoteAddress = abi.encodePacked(address(vaultv2_chain1), address(vaultv2_chain2));
        vaultv2_chain2.addTrustedRemoteAddress(CHAIN_ID_1, trustedRemoteAddress);

        endpoint1.setDestLzEndpoint(address(vaultv2_chain2), address(endpoint2));
        endpoint2.setDestLzEndpoint(address(vaultv2_chain1), address(endpoint1));

        vm.stopPrank();

        // To cover LayerZero fees
        vm.deal(address(vaultv2_chain1), 100 ether);
        vm.deal(address(vaultv2_chain2), 100 ether);
    }

    function testFuzz_Deposit(address depositor_, uint128 deposit_, uint64 monthsLocked_) external {
        vm.assume(depositor_ != address(0));
        vm.assume(depositor_ != router);
        deposit_ = uint128(bound(deposit_, 0, 1_000_000 ether));
        monthsLocked_ = uint64(bound(monthsLocked_, 0, 50));

        giveLPtokens(depositor_, uint256(deposit_));
        vm.warp(time);

        // Deposit
        vm.startPrank(depositor_);
        uint64 hint = vaultv2_chain1.getInsertPosition(uint64(block.timestamp) + monthsLocked_ * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vaultv2_chain1), deposit_);
        if (monthsLocked_ != 6 && monthsLocked_ != 12 && monthsLocked_ != 24 && monthsLocked_ != 48) {
            vm.expectRevert(IVault.InvalidLockPeriodError.selector);
            vaultv2_chain1.deposit(uint128(deposit_), monthsLocked_, hint);
            return;
        }
        if (deposit_ < 1000) {
            vm.expectRevert(IVault.InsuficientDepositAmountError.selector);
            vaultv2_chain1.deposit(uint128(deposit_), monthsLocked_, hint);
            return;
        }
        vaultv2_chain1.deposit(uint128(deposit_), monthsLocked_, hint);
        assert(LPtoken.balanceOf(depositor_) == 0);
        vm.stopPrank();
    }

    function testFuzz_Withdraw(address depositor_, uint128 deposit_, uint64 monthsLocked_, uint64 timeToWithdraw_)
        external
    {
        vm.assume(depositor_ != address(0));
        vm.assume(depositor_ != address(1));
        vm.assume(depositor_ != router);
        deposit_ = uint128(bound(deposit_, 1000, 100_000 ether));
        monthsLocked_ = uint64(bound(monthsLocked_, 6, 48));
        vm.assume(monthsLocked_ == 6 || monthsLocked_ == 12 || monthsLocked_ == 24 || monthsLocked_ == 48);
        giveLPtokens(depositor_, uint256(deposit_));
        giveLPtokens(address(1), uint256(deposit_));

        vm.warp(time);
        deposit(address(vaultv2_chain1), depositor_, deposit_, monthsLocked_);

        // Fast-forward
        vm.warp(time += timeToWithdraw_);
        // Someone else deposits tokens updating the list
        deposit(address(vaultv2_chain1), address(1), 1000, 6);

        // Withdraw
        vm.startPrank(depositor_);
        if (timeToWithdraw_ < monthsLocked_ * SECONDS_IN_30_DAYS) {
            vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
            vaultv2_chain1.withdraw();
            return;
        } else {
            uint256 withdrawableAmount = vaultv2_chain1.getWithdrawableAmount(depositor_);
            vaultv2_chain1.withdraw();
            uint256 balance = LPtoken.balanceOf(depositor_);
            assert(balance == deposit_);
            assert(balance == withdrawableAmount);
        }
        vm.stopPrank();
    }

    function testFuzz_ClaimRewards(address depositor_, uint128 deposit_, uint64 monthsLocked_, uint64 timeInterval_)
        external
    {
        vm.assume(depositor_ != address(0));
        vm.assume(depositor_ != address(1));
        vm.assume(depositor_ != router);
        deposit_ = uint128(bound(deposit_, 1 ether, 100_000 ether));
        monthsLocked_ = uint64(bound(monthsLocked_, 6, 48));
        timeInterval_ = uint64(bound(timeInterval_, 7 days, 1000 ether));
        vm.assume(monthsLocked_ == 6 || monthsLocked_ == 12 || monthsLocked_ == 24 || monthsLocked_ == 48);
        giveLPtokens(depositor_, uint256(deposit_));
        giveLPtokens(address(1), uint256(deposit_));

        vm.warp(time);
        deposit(address(vaultv2_chain1), depositor_, deposit_, monthsLocked_);

        // Fast-forward
        vm.warp(time += timeInterval_);
        // Someone else deposits tokens updating the list
        deposit(address(vaultv2_chain1), address(1), 1000, 6);

        // Claim Rewards
        vm.startPrank(depositor_);
        uint64[] memory depositIds_ = vaultv2_chain1.getDepositIds(depositor_);
        uint128 expectedValue;
        uint128 claimableRewards = vaultv2_chain1.getClaimableRewards(depositor_, depositIds_);
        if ((uint256(timeInterval_) * uint256(REWARDS_PER_SECOND) * 1 ether / uint256(deposit_)) == 0) {
            // not enough time for rewards
            vm.expectRevert(IVault.NoRewardsToClaimError.selector);
            vaultv2_chain1.claimRewards(depositIds_);
            return;
        } else if (timeInterval_ < monthsLocked_ * SECONDS_IN_30_DAYS) {
            expectedValue = REWARDS_PER_SECOND * timeInterval_;
        } else {
            expectedValue = REWARDS_PER_MONTH * monthsLocked_;
        }
        vaultv2_chain1.claimRewards(depositIds_);
        emit log_uint(expectedValue);
        assert(similar(uint256(claimableRewards), uint256(expectedValue)));
        assert(similar(rewardToken_chain1.balanceOf(depositor_), uint256(expectedValue)));

        vm.stopPrank();
    }
}
