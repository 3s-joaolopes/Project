// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    address private _owner;

    error Unauthorized();

    modifier onlyOwner() {
        if (msg.sender != _owner) revert Unauthorized();
        _;
    }

    constructor(address owner_) ERC20("Token", "TKN") {
        _owner = owner_;
     }

    /// @dev Mint tokens to receiver
    /// @param amount_ Amount of tokens to mint
    function mintRewards(address receiver_, uint256 amount_) external onlyOwner {
        _mint(receiver_, amount_);
    }
}

/// @dev Mint tokens to contract owner
/// @param amount_ Amount of tokens to mint
//function mintRewards(uint256 amount_) external onlyOwner { }
