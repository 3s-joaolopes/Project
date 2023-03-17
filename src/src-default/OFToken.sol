// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IOFT} from "@layerZero/token/oft/IOFT.sol";
import {OFTCore} from "@layerZero/token/oft/OFTCore.sol";

// override decimal() function is needed
contract OFToken is OFTCore, ERC20, IOFT {
    address private _owner;

    error UnauthorizedError();

    modifier onlyOwner_() {
        if (msg.sender != _owner) revert UnauthorizedError();
        _;
    }

    constructor(address owner_, string memory _name, string memory _symbol, address _lzEndpoint)
        ERC20(_name, _symbol)
        OFTCore(_lzEndpoint)
    {
        _owner = owner_;
    }

    /// @dev Mint tokens to receiver
    /// @param receiver_ Receiver of the tokens
    /// @param amount_   Amount of tokens to mint
    function mintRewards(address receiver_, uint256 amount_) external onlyOwner_ {
        _mint(receiver_, amount_);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(OFTCore, IERC165) returns (bool) {
        return interfaceId == type(IOFT).interfaceId || interfaceId == type(IERC20).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function token() public view virtual override returns (address) {
        return address(this);
    }

    function circulatingSupply() public view virtual override returns (uint256) {
        return totalSupply();
    }

    function _debitFrom(address _from, uint16, bytes memory, uint256 _amount)
        internal
        virtual
        override
        returns (uint256)
    {
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        _burn(_from, _amount);
        return _amount;
    }

    function _creditTo(uint16, address _toAddress, uint256 _amount) internal virtual override returns (uint256) {
        _mint(_toAddress, _amount);
        return _amount;
    }
}
