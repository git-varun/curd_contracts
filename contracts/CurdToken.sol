//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {EIP712MetaTransaction} from "./extension/EIP712MetaTransaction.sol";

contract CURD is
    ERC20,
    AccessControl,
    ERC20Burnable,
    ERC20Pausable,
    EIP712MetaTransaction
{
    uint256 public constant MAX_CAP = 1000000000 * (10 ** 18); // 1,000,000,000 tokens

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(
        address _defaultOwner
    ) ERC20("CURD", "CURD") EIP712MetaTransaction("CURD", "1") {
        _mint(_msgSender(), MAX_CAP);
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultOwner);

        _grantRole(BURNER_ROLE, _defaultOwner);
        _grantRole(PAUSER_ROLE, _defaultOwner);
    }

    function pause() external whenNotPaused onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external whenPaused onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function burn(
        uint256 amount
    ) public override whenNotPaused onlyRole(BURNER_ROLE) {
        super.burn(amount);
    }

    function burnFrom(
        address account,
        uint256 amount
    ) public override whenNotPaused onlyRole(BURNER_ROLE) {
        super.burnFrom(account, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Pausable) {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _msgSender()
        internal
        view
        virtual
        override
        returns (address sender)
    {
        if (msg.sender == address(this)) {
            bytes memory array = msg.data;
            uint256 index = msg.data.length;
            assembly {
                // Load the 32 bytes word from memory with the address on the lower 20 bytes, and mask those.
                sender := and(
                    mload(add(array, index)),
                    0xffffffffffffffffffffffffffffffffffffffff
                )
            }
        } else {
            sender = msg.sender;
        }
        return sender;
    }
}
