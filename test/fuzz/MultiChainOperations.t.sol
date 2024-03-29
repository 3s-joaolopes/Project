// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { UUPSProxy } from "src/src-default/UUPSProxy.sol";
import { UniswapHelper } from "./../utils/UniswapHelper.sol";
import { LayerZeroHelper } from "./../utils/LayerZeroHelper.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { IVaultV2 } from "src/src-default/interfaces/IVaultV2.sol";
import { Vault } from "src/src-default/Vault.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { OFToken } from "src/src-default/OFToken.sol";
import { LZEndpointMock } from "@layerZero/mocks/LZEndpointMock.sol";
import { Lib } from "test/utils/Library.sol";

contract MultiChainOperationsFuzzTests is Test, LayerZeroHelper {
    uint64 constant SECONDS_IN_30_DAYS = 2_592_000;
    uint128 constant REWARDS_PER_SECOND = 317;
    uint128 constant REWARDS_PER_MONTH = REWARDS_PER_SECOND * SECONDS_IN_30_DAYS;
    uint128 constant MIN_DEPOSIT = 1000;
    uint256 constant STARTING_TIME = 1000;
    uint256 constant MIN_CHAINS = 1;
    uint256 constant MAX_CHAINS = 7;
    uint128 constant DEPOSIT = 1 ether;
    address constant DEPOSITOR = address(3);
    uint64 constant MONTHS_LOCKED = 12;
    uint64 constant RANDOM_HINT = 3;

    uint256 numberOfVaults;
    uint256 expectedRewards;
    uint256 public time = STARTING_TIME;

    function setUp() public override {
        super.setUp();
    }

    function testFuzz_LayerZeroFunctionality_SkipCI(uint16[] calldata chainIds_) external {
        // Initial setup
        vm.assume(chainIds_.length > 0);
        numberOfVaults = bound(chainIds_.length, MIN_CHAINS, MAX_CHAINS);
        chainIds_ = chainIds_[0:numberOfVaults];
        vm.assume(Lib.repeatedEntries(chainIds_) == false);
        for (uint256 i = 0; i < numberOfVaults; i++) {
            vm.assume(chainIds_[i] != 998);
        }
        giveLPtokens(DEPOSITOR, numberOfVaults * DEPOSIT);

        // Deploy and connect vaults
        (address[] memory vaultsv2_, address[] memory endpoints_, address[] memory rewardTokens_) =
            deployBatchOnChain(chainIds_);
        connectVaults(chainIds_, vaultsv2_, endpoints_);

        // Start simulation
        vm.warp(time);
        vm.startPrank(DEPOSITOR);

        // Make deposits
        for (uint256 i = 0; i < numberOfVaults; i++) {
            LPtoken.approve(vaultsv2_[i], uint256(DEPOSIT));
            IVaultV2(vaultsv2_[i]).deposit(DEPOSIT, MONTHS_LOCKED, RANDOM_HINT);
        }
        assert(LPtoken.balanceOf(DEPOSITOR) == 0);

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Withdraw deposits
        for (uint256 i = 0; i < numberOfVaults; i++) {
            IVaultV2(vaultsv2_[i]).withdraw();
        }
        assert(LPtoken.balanceOf(DEPOSITOR) == numberOfVaults * DEPOSIT);

        // Claim rewards
        expectedRewards = uint256(REWARDS_PER_MONTH) * 12 / numberOfVaults;
        for (uint256 i = 0; i < numberOfVaults; i++) {
            uint64[] memory depositIds = IVaultV2(vaultsv2_[i]).getDepositIds(DEPOSITOR);
            IVaultV2(vaultsv2_[i]).claimRewards(depositIds);
            assert(Lib.similar(OFToken(rewardTokens_[i]).balanceOf(DEPOSITOR), expectedRewards));
        }

        vm.stopPrank();
    }
}
