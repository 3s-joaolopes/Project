// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { UUPSProxy } from "src/src-default/UUPSProxy.sol";
import { VaultFixture } from "./../utils/VaultFixture.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { IVaultV2 } from "src/src-default/interfaces/IVaultV2.sol";
import { Vault } from "src/src-default/Vault.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { OFToken } from "src/src-default/OFToken.sol";
import { LZEndpointMock } from "@layerZero/mocks/LZEndpointMock.sol";

contract LayerZeroHelper is Test, VaultFixture {
    function setUp() public virtual override {
        super.setUp();
    }

    function deployOnChain(uint16 chainId_)
        public
        isDeployer
        returns (address vaultv2_, address endpoint_, address rewardToken_)
    {
        VaultV2 vaultImplementation = new VaultV2();
        endpoint_ = address(new LZEndpointMock(chainId_));

        // Deploy and initialize vaultv2
        bytes memory initializeData =
            abi.encodeWithSignature("initialize(address,address)", address(LPtoken), endpoint_);
        vaultv2_ = address(new UUPSProxy(address(vaultImplementation), initializeData));
        rewardToken_ = address(VaultV2(vaultv2_).rewardToken());

        // To cover LayerZero fees
        vm.deal(address(vaultv2_), 100 ether);
    }

    function deployBatchOnChain(uint16[] calldata chainIds_)
        public
        isDeployer
        returns (address[] memory vaultsv2_, address[] memory endpoints_, address[] memory rewardTokens_)
    {
        vaultsv2_ = new address[](chainIds_.length);
        endpoints_ = new address[](chainIds_.length);
        rewardTokens_ = new address[](chainIds_.length);

        for (uint256 i = 0; i < chainIds_.length; i++) {
            VaultV2 vaultImplementation = new VaultV2();
            endpoints_[i] = address(new LZEndpointMock(chainIds_[i]));

            // Deploy and initialize vaultv2
            bytes memory initializeData =
                abi.encodeWithSignature("initialize(address,address)", address(LPtoken), endpoints_[i]);
            vaultsv2_[i] = address(new UUPSProxy(address(vaultImplementation), initializeData));
            rewardTokens_[i] = address(VaultV2(vaultsv2_[i]).rewardToken());

            // To cover LayerZero fees
            vm.deal(address(vaultsv2_[i]), 100 ether);
        }
    }

    function connectVaults(uint16[] memory chainIds_, address[] memory vaultsv2_, address[] memory endpoints_)
        public
        isDeployer
    {
        assert(vaultsv2_.length == chainIds_.length);
        assert(vaultsv2_.length == endpoints_.length);

        for (uint256 i = 0; i < vaultsv2_.length; i++) {
            for (uint256 j = 0; j < vaultsv2_.length; j++) {
                if (i != j) {
                    assert(chainIds_[i] != chainIds_[j]);
                    bytes memory trustedRemoteAddress = abi.encodePacked(address(vaultsv2_[j]), address(vaultsv2_[i]));
                    VaultV2(vaultsv2_[i]).addTrustedRemoteAddress(chainIds_[j], trustedRemoteAddress);
                    LZEndpointMock(endpoints_[i]).setDestLzEndpoint(vaultsv2_[j], endpoints_[j]);
                }
            }
        }
    }
}
