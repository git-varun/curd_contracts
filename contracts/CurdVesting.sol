//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interface/ICurdDistribution.sol";
import "./library/BokkyPooBahsDateTimeLibrary.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CurdVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using BokkyPooBahsDateTimeLibrary for uint256;

    event BeneficiaryAdded(
        address indexed beneficiary,
        uint256 allotment,
        ICurdDistribution.PoolType indexed pool,
        uint256 startTime
    );
    event BeneficiaryModified(
        address indexed beneficiary,
        ICurdDistribution.PoolType indexed pool,
        uint256 amount
    );
    event BeneficiaryRevoked(
        address indexed beneficiary,
        ICurdDistribution.PoolType indexed pool
    );
    event TokensRedeemed(
        address indexed beneficiary,
        ICurdDistribution.PoolType indexed pool,
        uint256 amount
    );
    event TokensRedeemedFromAllPools(
        address indexed beneficiary,
        uint256 amount
    );

    error InsufficientBalance(uint256 required, uint256 current);
    error UserNotExist();
    error RevokedUser();
    error UnRenounceable();
    error UnModifiable();
    error Initialized();
    error InvalidInput();
    error UserExist();
    error UnInitialized();
    error ZeroAddress();
    error ZeroAmount();

    struct VestingInfo {
        uint256 allocated;
        uint256 withdrawn;
        uint256 startTime;
        address user;
        bool isRevoked;
    }

    mapping(ICurdDistribution.PoolType => mapping(address => VestingInfo))
        private _beneficiaryInfo;

    bool private _initialized;
    uint256 private _initTimestamp;
    IERC20 private _token;
    ICurdDistribution private _distribution;

    modifier isInitialized() {
        if (_initialized == false) revert UnInitialized();
        _;
    }

    constructor(IERC20 token) {
        if (address(token) == address(0x0)) revert ZeroAddress();

        _token = token;
        _initialized = false;
    }

    function initialize(
        ICurdDistribution _curdDistribution
    ) external onlyOwner {
        if (_initialized == true) revert Initialized();
        if (address(_curdDistribution) == address(0x0)) revert ZeroAddress();

        _initTimestamp = getCurrentTime();
        _initialized = true;
        _distribution = _curdDistribution;
    }

    function addBeneficiary(
        address[] calldata _user,
        uint256[] calldata _amount,
        ICurdDistribution.PoolType[] calldata _pool
    ) external onlyOwner isInitialized {
        if (_user.length != _amount.length || _amount.length != _pool.length)
            revert InvalidInput();

        for (uint256 i = 0; i < _user.length; i++) {
            if (_user[i] == address(0x0)) revert ZeroAddress();
            if (_amount[i] == 0) revert ZeroAmount();
            if (_beneficiaryInfo[_pool[i]][_user[i]].allocated != 0)
                revert UserExist();

            _addBeneficiary(_user[i], _amount[i], _pool[i]);
        }
    }

    function _addBeneficiary(
        address _user,
        uint256 _amount,
        ICurdDistribution.PoolType _pool
    ) internal {
        // Update The Distribution Mapping.
        ICurdDistribution.PoolInfo memory properties = _distribution
            .getDistribution(_pool);
        uint256 poolBalance = properties.totalAmountAllocated -
            properties.userAllocatedAmount;

        if (_amount > poolBalance)
            revert InsufficientBalance(_amount, poolBalance);

        properties.totalAmountAllocated -= _amount;
        properties.userAllocatedAmount += _amount;
        _distribution.setDistribution(_pool, properties);

        // Update The User Mapping.
        _beneficiaryInfo[_pool][_user].user = _user;
        _beneficiaryInfo[_pool][_user].allocated += _amount;

        _beneficiaryInfo[_pool][_user].startTime = getCurrentTime();
        _beneficiaryInfo[_pool][_user].isRevoked = false;
        _beneficiaryInfo[_pool][_user].withdrawn = 0;

        emit BeneficiaryAdded(
            _user,
            _amount,
            _pool,
            _beneficiaryInfo[_pool][_user].startTime
        );
    }

    function modifyBeneficiary(
        address _user,
        ICurdDistribution.PoolType _pool,
        uint256 _amount
    ) external onlyOwner isInitialized {
        if (_user == address(0x0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();

        if (_beneficiaryInfo[_pool][_user].isRevoked) revert RevokedUser();
        if (_beneficiaryInfo[_pool][_user].allocated == 0)
            revert UserNotExist();

        ICurdDistribution.PoolInfo memory properties = _distribution
            .getDistribution(_pool);
        uint256 afterCliffTime = _beneficiaryInfo[_pool][_user]
            .startTime
            .addMonths(properties.cliffPeriod);
        uint256 poolBalance = properties.totalAmountAllocated -
            properties.userAllocatedAmount;

        if (afterCliffTime < getCurrentTime()) revert UnModifiable();
        if (_amount == 0 && _amount > poolBalance)
            revert InsufficientBalance(_amount, poolBalance);

        // Update The Distribution Mapping.
        properties.totalAmountAllocated -= _amount;
        properties.userAllocatedAmount += _amount;
        _distribution.setDistribution(_pool, properties);

        // Update The User Allocation.
        _beneficiaryInfo[_pool][_user].allocated += _amount;

        emit BeneficiaryModified(_user, _pool, _amount);
    }

      function revokeBeneficiary(
        address _user,
        ICurdDistribution.PoolType _pool
    ) external onlyOwner isInitialized {
        if (_user != address(0x0)) revert ZeroAddress();
        if (_beneficiaryInfo[_pool][_user].allocated == 0)
            revert UserNotExist();
        if (_beneficiaryInfo[_pool][_user].isRevoked) revert RevokedUser();

        ICurdDistribution.PoolInfo memory properties = _distribution
            .getDistribution(_pool);
        uint256 afterCliffTime = _beneficiaryInfo[_pool][_user]
            .startTime
            .addMonths(properties.cliffPeriod);
        if (afterCliffTime < getCurrentTime()) revert UnModifiable();

        // Update Distribution Parameters
        properties.userAllocatedAmount -= _beneficiaryInfo[_pool][_user]
            .allocated;
        properties.totalAmountAllocated += _beneficiaryInfo[_pool][_user]
            .allocated;
        _distribution.setDistribution(_pool, properties);

        emit BeneficiaryRevoked(_user, _pool);
    }

    function redeemToken(
        ICurdDistribution.PoolType _pool
    ) external isInitialized nonReentrant {
        if (_beneficiaryInfo[_pool][_msgSender()].allocated == 0)
            revert UserNotExist();
        if (_beneficiaryInfo[_pool][_msgSender()].isRevoked)
            revert RevokedUser();

        uint256 redeemableAmount = _calculateRedeemableToken(
            _pool,
            _msgSender()
        );
        if (redeemableAmount == 0) revert ZeroAmount();

        // Update The User Mapping
        _beneficiaryInfo[_pool][_msgSender()].withdrawn += redeemableAmount;

        // Transfer CURD Coin to the User address.@author
        _token.safeTransferFrom(
            address(_distribution),
            _msgSender(),
            redeemableAmount
        );

        emit TokensRedeemed(_msgSender(), _pool, redeemableAmount);
    }

    function redeemTokenFromAllPoll() external isInitialized nonReentrant {
        uint256 redeemableAmount = 0;
        for (
            uint8 i = 0;
            i < uint8(type(ICurdDistribution.PoolType).max);
            i++
        ) {
            uint256 poolBalance = _calculateRedeemableToken(
                ICurdDistribution.PoolType(i),
                _msgSender()
            );

            // Update User Mapping.@author
            _beneficiaryInfo[ICurdDistribution.PoolType(i)][_msgSender()]
                .withdrawn += poolBalance;
            redeemableAmount += poolBalance;
        }

        if (redeemableAmount == 0) revert ZeroAmount();
        _token.safeTransferFrom(
            address(_distribution),
            _msgSender(),
            redeemableAmount
        );

        emit TokensRedeemedFromAllPools(_msgSender(), redeemableAmount);
    }

    function _calculateRedeemableToken(
        ICurdDistribution.PoolType _pool,
        address _user
    ) internal returns (uint256) {
        if (
            _beneficiaryInfo[_pool][_user].allocated == 0 ||
            _beneficiaryInfo[_pool][_user].isRevoked
        ) return 0;

        ICurdDistribution.PoolInfo memory properties = _distribution
            .getDistribution(_pool);
        uint256 afterCliffTime = _beneficiaryInfo[_pool][_user]
            .startTime
            .addMonths(properties.cliffPeriod);
        if (afterCliffTime > getCurrentTime()) return 0;

        uint256 totalTokens = 0;
        for (uint8 i = 0; i < properties.vestingSlice; i++) {
            if (
                getCurrentTime() >
                afterCliffTime + properties.vestingSchedule * i
            ) {
                totalTokens +=
                    (_beneficiaryInfo[_pool][_user].allocated) /
                    (properties.vestingSlice);
            } else {
                break;
            }
        }

        return (totalTokens - _beneficiaryInfo[_pool][_user].withdrawn);
    }

    function getVestingInfo(
        ICurdDistribution.PoolType _pool
    ) external view returns (VestingInfo memory) {
        return _beneficiaryInfo[_pool][_msgSender()];
    }

    function getTotalAllocation() external view returns (uint256) {
        uint256 totalAllocation = 0;

        for (
            uint8 i = 0;
            i < uint8(type(ICurdDistribution.PoolType).max);
            i++
        ) {
            totalAllocation += _beneficiaryInfo[ICurdDistribution.PoolType(i)][
                _msgSender()
            ].allocated;
        }

        return totalAllocation;
    }

    function getRedeemable(
        ICurdDistribution.PoolType _pool
    ) external returns (uint256) {
        return _calculateRedeemableToken(_pool, _msgSender());
    }

    function getTotalRedeemable() external returns (uint256) {
        uint256 totalRedeemable = 0;

        for (
            uint8 i = 0;
            i < uint8(type(ICurdDistribution.PoolType).max);
            i++
        ) {
            totalRedeemable += _calculateRedeemableToken(
                ICurdDistribution.PoolType(i),
                _msgSender()
            );
        }

        return totalRedeemable;
    }

    function getCurdDistribution() external view returns (ICurdDistribution) {
        return _distribution;
    }

    function isInitialised() external view returns (bool) {
        return _initialized;
    }

    function getToken() external view returns (IERC20) {
        return _token;
    }

    function getInitialTimestamp() external view returns (uint256) {
        return _initTimestamp;
    }

    /**
     * Not let the owner to transfer ownership to zero address.
     */
    function renounceOwnership() public view override(Ownable) onlyOwner {
        revert UnRenounceable();
    }

    /**
     * @dev Returns the current time.
     * @return the current timestamp in seconds.
     */
    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev This function is called for plain Ether transfers, i.e. for every call with empty calldata.
     */
    receive() external payable {}

    /**
     * @dev Fallback function is executed if none of the other functions match the function
     * identifier or no data was provided with the function call.
     */
    fallback() external payable {}
}
