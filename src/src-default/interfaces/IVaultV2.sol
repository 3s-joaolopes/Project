// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { IVault } from "./IVault.sol";
import { ILayerZeroReceiver } from "./dependencies/ILayerZeroReceiver.sol";

interface IVaultV2 is IVault, ILayerZeroReceiver {
    event LogOmnichainDeposit(
        uint16 srcChainId_, address fromAddress_, uint128 shares_, uint64 depositTime_, uint64 expiretime_
    );
    event LogTrustedRemoteAddress(uint16 _remoteChainId, bytes _remoteAddress);

    error NotEndpointError();
    error NotTrustedSourceError();
    error InvalidChainIdError();
    error DuplicatingChainIdError();

    /// @notice Add a vault on a remote chain as a trusted source of information
    /// @param remoteChainId_   identifier of the remote chain
    /// @param remoteAddress_   address of the vault on the remote chain
    function addTrustedRemoteAddress(uint16 remoteChainId_, bytes calldata remoteAddress_) external;

    /// @notice Set the LayerZero endpoint for inter-chain communication
    /// @param lzEndpoint_   address of thw new endpoint
    function setLzEndpoint(address lzEndpoint_) external;
}
