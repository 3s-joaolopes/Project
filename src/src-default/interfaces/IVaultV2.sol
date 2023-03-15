// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { IVault } from "./IVault.sol";

interface IVaultV2 is IVault {
    event LogOmnichainDeposit(
        uint256 srcChainId_, address fromAddress_, uint256 shares_, uint256 depositTime_, uint256 expiretime_
    );

    error NotEndpoint();
    error NotTrustedVault();
}
