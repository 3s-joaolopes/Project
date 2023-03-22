// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol";
import { UUPSProxy } from "src/src-default/UUPSProxy.sol";
import { VaultFixture } from "./../utils/VaultFixture.sol";
import { LayerZeroHelper } from "./../utils/LayerZeroHelper.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { IVaultV2 } from "src/src-default/interfaces/IVaultV2.sol";
import { Vault } from "src/src-default/Vault.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { OFToken } from "src/src-default/OFToken.sol";
import { LZEndpointMock } from "@layerZero/mocks/LZEndpointMock.sol";

contract BaseOperationsFuzzTests is Test, LayerZeroHelper {
    uint16 constant CHAIN_ID = 1;

    VaultV2 public vaultv2;
    LZEndpointMock public endpoint;
    OFToken public rewardToken;

    function setUp() public override {
        super.setUp();

        (address vaultv2Addr, address endpointAddr, address rewardTokenAddr) = deployOnChain(CHAIN_ID);
        vaultv2 = VaultV2(vaultv2Addr);
        endpoint = LZEndpointMock(endpointAddr);
        rewardToken = OFToken(rewardTokenAddr);
    }

    function testFuzz_Deposit(address depositor_, uint128 deposit_, uint64 monthsLocked_, uint64 hint_) external {
        vm.assume(depositor_ != address(0));
        vm.assume(depositor_ != router);
        deposit_ = uint128(bound(deposit_, 0, 1_000_000 ether));
        monthsLocked_ = uint64(bound(monthsLocked_, 0, 50));

        giveLPtokens(depositor_, uint256(deposit_));
        vm.warp(time);

        // Deposit
        vm.startPrank(depositor_);
        LPtoken.approve(address(vaultv2), deposit_);
        if (monthsLocked_ != 6 && monthsLocked_ != 12 && monthsLocked_ != 24 && monthsLocked_ != 48) {
            vm.expectRevert(IVault.InvalidLockPeriodError.selector);
            vaultv2.deposit(uint128(deposit_), monthsLocked_, hint_);
            return;
        }
        if (deposit_ < 1000) {
            vm.expectRevert(IVault.InsuficientDepositAmountError.selector);
            vaultv2.deposit(uint128(deposit_), monthsLocked_, hint_);
            return;
        }
        vaultv2.deposit(uint128(deposit_), monthsLocked_, hint_);
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
        deposit(address(vaultv2), depositor_, deposit_, monthsLocked_);

        // Fast-forward
        vm.warp(time += timeToWithdraw_);
        // Someone else deposits tokens updating the list
        deposit(address(vaultv2), address(1), 1000, 6);

        // Withdraw
        vm.startPrank(depositor_);
        if (timeToWithdraw_ < monthsLocked_ * SECONDS_IN_30_DAYS) {
            vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
            vaultv2.withdraw();
            return;
        } else {
            uint256 withdrawableAmount = vaultv2.getWithdrawableAmount(depositor_);
            vaultv2.withdraw();
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
        deposit(address(vaultv2), depositor_, deposit_, monthsLocked_);

        // Fast-forward
        vm.warp(time += timeInterval_);
        // Someone else deposits tokens updating the list
        deposit(address(vaultv2), address(1), 1000, 6);

        // Claim Rewards
        vm.startPrank(depositor_);
        uint64[] memory depositIds_ = vaultv2.getDepositIds(depositor_);
        uint128 expectedValue;
        uint128 claimableRewards = vaultv2.getClaimableRewards(depositor_, depositIds_);
        if ((uint256(timeInterval_) * uint256(REWARDS_PER_SECOND) * 1 ether / uint256(deposit_)) == 0) {
            // not enough time for rewards
            vm.expectRevert(IVault.NoRewardsToClaimError.selector);
            vaultv2.claimRewards(depositIds_);
            return;
        } else if (timeInterval_ < monthsLocked_ * SECONDS_IN_30_DAYS) {
            expectedValue = REWARDS_PER_SECOND * timeInterval_;
        } else {
            expectedValue = REWARDS_PER_MONTH * monthsLocked_;
        }
        vaultv2.claimRewards(depositIds_);
        emit log_uint(expectedValue);
        assert(similar(uint256(claimableRewards), uint256(expectedValue)));
        assert(similar(rewardToken.balanceOf(depositor_), uint256(expectedValue)));

        vm.stopPrank();
    }
}