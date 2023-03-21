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

contract MultiChainOperationsFuzzTests is Test, LayerZeroHelper {
    uint256 numberOfChains;

    function setUp() public override {
        super.setUp();
    }

    function _testFuzz_LayerZeroFunctionality(uint16[] memory chainIds_) external {
        //Check for repeated entries
        numberOfChains = chainIds_.length;
        for (uint256 i = 0; i < numberOfChains; i++) {
            vm.assume(chainIds_[i] != 998);
        }
        uint128 deposit_ = 1 ether;
        address depositor_ = alice;
        uint64 monthsLocked_ = 12;
        uint64 randomHint_ = 3;
        giveLPtokens(depositor_, numberOfChains * deposit_);

        (address[] memory vaultsv2_, address[] memory endpoints_, address[] memory rewardTokens_) =
            deployBatchOnChain(chainIds_);
        connectVaults(chainIds_, vaultsv2_, endpoints_);

        // Make deposits
        for (uint256 i = 0; i < numberOfChains; i++) {
            vm.startPrank(depositor_);
            LPtoken.approve(vaultsv2_[i], uint256(deposit_));
            IVaultV2(vaultsv2_[i]).deposit(deposit_, monthsLocked_, randomHint_);
            vm.stopPrank();
        }
    }
}
