// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    address private _owner;

    error UnauthorizedError();

    modifier onlyOwner() {
        if (msg.sender != _owner) revert UnauthorizedError();
        _;
    }

    constructor(address owner_) ERC20("Token", "TKN") {
        _owner = owner_;
    }

    /// @dev Mint tokens to receiver
    /// @param receiver_ Receiver of the tokens
    /// @param amount_   Amount of tokens to mint
    function mintRewards(address receiver_, uint256 amount_) external onlyOwner {
        _mint(receiver_, amount_);
    }
}
