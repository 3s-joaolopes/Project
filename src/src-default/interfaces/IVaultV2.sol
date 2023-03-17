// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { IVault } from "./IVault.sol";
import { ILayerZeroReceiver } from "@layerZero/interfaces/ILayerZeroReceiver.sol";

interface IVaultV2 is IVault, ILayerZeroReceiver {
    event LogOmnichainDeposit(
        uint256 srcChainId_, address fromAddress_, uint256 shares_, uint256 depositTime_, uint256 expiretime_
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
}
