// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { OFT } from "@layerZero/token/oft/OFT.sol";

contract OFToken is OFT {
    address private _owner;

    error UnauthorizedError();

    modifier onlyOwner_() {
        if (msg.sender != _owner) revert UnauthorizedError();
        _;
    }

    constructor(address owner_, string memory name_, string memory symbol_, address lzEndpoint_)
        OFT(name_, symbol_, lzEndpoint_)
    {
        _owner = owner_;
    }

    /// @dev Mint tokens to receiver
    /// @param receiver_ Receiver of the tokens
    /// @param amount_   Amount of tokens to mint
    function mintRewards(address receiver_, uint256 amount_) external onlyOwner_ {
        _mint(receiver_, amount_);
    }
}
