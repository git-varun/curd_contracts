//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712MetaTransaction} from "./extension/EIP712MetaTransaction.sol";

contract CurdRedemption is
    Ownable,
    Pausable,
    ReentrancyGuard,
    EIP712MetaTransaction
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event TokenAdded(address indexed stableToken, uint256 amount);
    event TokenRemoved(address indexed stableToken, uint256 amount);
    event CurdTokenLimitUpdated(uint256 newCurdTokenLimit);
    event PayTokenUpdated(address indexed payToken, bool status);
    event CurdAdminUpdated(address indexed curdAdmin);
    event CoinReedemed(
        uint256 reedemAmount,
        uint256 curdToken,
        address indexed user
    );
    event BalanceTransferred(bool status, bytes data);

    error ZeroAddress();
    error ZeroAmount();
    error SameStatus();
    error InvalidPayToken();
    error InvalidCaller(address curdAdmin, address caller);
    error InsufficientBalance(uint256 required, uint256 current);
    error InsufficientPayToken(uint256 required, uint256 current);

    mapping(address => bool) private _payToken;

    uint256 private _tokenLimit;
    address private _curdAdmin;
    address private _token;
    uint256 private _basePrice;

    constructor(
        uint256 tokenLimit,
        address[] memory payTokens,
        address curdToken,
        uint256 basePrice,
        address curdAdmin
    ) EIP712MetaTransaction("CurdRedemption", "1") {
        _tokenLimit = tokenLimit;
        _token = curdToken;
        _basePrice = basePrice;
        _curdAdmin = curdAdmin;

        for (uint16 i = 0; i < payTokens.length; i++) {
            _payToken[payTokens[i]] = true;
        }
    }

    function redeemCoin(
        uint256 _amount,
        address payToken
    ) external whenNotPaused nonReentrant {
        _redeemCurdToken(_amount, payToken, _msgSender(), _msgSender());
    }

    function appRedeemCoin(
        uint256 _amount,
        address payToken,
        address user,
        address to
    ) external whenNotPaused nonReentrant {
        if (_msgSender() != _curdAdmin)
            revert InvalidCaller(_curdAdmin, _msgSender());
        if (user == address(0) || to == address(0)) revert ZeroAddress();

        _redeemCurdToken(_amount, payToken, user, to);
    }

    function _redeemCurdToken(
        uint256 _amount,
        address payToken,
        address user,
        address to
    ) internal {
        if (_amount < _tokenLimit)
            revert InsufficientBalance(_tokenLimit, _amount);

        if (!_payToken[payToken]) revert InvalidPayToken();

        uint256 userBalance = IERC20(_token).balanceOf(user);
        if (_amount > userBalance)
            revert InsufficientBalance(_amount, userBalance);

        uint256 redemptionAmount = _basePrice.mul(_amount).div(
            10 ** (36 - ERC20(payToken).decimals())
        );

        if (IERC20(payToken).balanceOf(address(this)) < redemptionAmount)
            revert InsufficientPayToken(
                redemptionAmount,
                IERC20(payToken).balanceOf(address(this))
            );

        IERC20(_token).safeTransferFrom(user, address(this), _amount);
        IERC20(payToken).safeTransfer(to, redemptionAmount);

        emit CoinReedemed(redemptionAmount, _amount, to);
    }

    function addToken(
        address token,
        uint256 _amount
    ) external whenPaused onlyOwner {
        if (token == address(0x0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(_msgSender(), address(this), _amount);

        emit TokenAdded(token, _amount);
    }

    function removeToken(
        address token,
        uint256 _amount,
        address _to
    ) external whenPaused onlyOwner {
        if (token == address(0x0) || _to == address(0x0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();

        IERC20(token).safeTransfer(_to, _amount);

        emit TokenRemoved(token, _amount);
    }

    function setPayTokenStatus(
        address payToken,
        bool _status
    ) external whenPaused onlyOwner {
        if (payToken == address(0x0)) revert ZeroAddress();
        if (_payToken[payToken] == _status) revert SameStatus();

        _payToken[payToken] = _status;

        emit PayTokenUpdated(payToken, _payToken[payToken]);
    }

    function setTokenLimit(uint256 tokenLimit) external whenPaused onlyOwner {
        if (tokenLimit == 0) revert ZeroAmount();
        if (tokenLimit == _tokenLimit) revert SameStatus();

        _tokenLimit = tokenLimit;

        emit CurdTokenLimitUpdated(_tokenLimit);
    }

    function setCurdAdmin(address curdAdmin) external whenPaused onlyOwner {
        if (curdAdmin == address(0x0)) revert ZeroAddress();
        if (curdAdmin == _curdAdmin) revert SameStatus();

        _curdAdmin = curdAdmin;

        emit CurdAdminUpdated(_curdAdmin);
    }

    function withdrawMatic(address payable _to) external payable onlyOwner {
        if (address(_to).balance == 0) revert ZeroAmount();
        if (_to == address(0x0)) revert ZeroAddress();

        (bool status, bytes memory data) = _to.call{
            value: address(this).balance
        }("");
        if (!status) revert();

        emit BalanceTransferred(status, data);
    }

    function pause() external whenNotPaused onlyOwner {
        _pause();
    }

    function unpause() external whenPaused onlyOwner {
        _unpause();
    }

    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function isValidPayToken(address token) external view returns (bool) {
        return _payToken[token];
    }

    function getTokenLimit() external view returns (uint256) {
        return _tokenLimit;
    }

    function getBasePrice() external view returns (uint256) {
        return _basePrice;
    }

    function getCurdToken() external view returns (address) {
        return _token;
    }

    receive() external payable {}

    fallback() external payable {}

    function _msgSender() internal view override returns (address) {
        address sender;

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
