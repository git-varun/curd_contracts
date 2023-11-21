//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CurdDistribution is Ownable {
    using SafeERC20 for IERC20;

    enum PoolType {
        COMMUNITY,
        TEAM,
        ADVISORS,
        MARKETING,
        ECOSYSTEM,
        PUBLIC,
        PRIVATE,
        SEED,
        PRE_SEED
    }

    event PoolAdded(
        address indexed caller,
        PoolType pool,
        uint256 allocation,
        uint256 cliff,
        uint256 vesting,
        uint256 slice
    );
    event UnallocatedTokensWithdrawn(address _to, uint256 _amount);
    event WithdrawnPoolUnallocatedToken(
        address _to,
        PoolType _pool,
        uint256 _amount
    );
    event RecoveredERC20(address token, uint256 value);
    event MaticTransferred(bool status, bytes data);

    error InsufficientBalance(uint256 required, uint256 current);
    error NonRenounceable();
    error NonVestingContract();
    error Uninitialized();

    error Initialized();
    error ZeroAddress();
    error ZeroAmount();
    error WrongToken();

    struct PoolInfo {
        PoolType pool;
        uint256 totalAmountAllocated; // Total amount allocated to the pool.@dev
        uint256 userAllocatedAmount; // Amount allocated to beneficiary in vesting contract.@dev
        uint256 userWithdrawn; // User redeemed amount.@dev
        uint256 cliffPeriod; // Cliff Period In Months.@dev
        uint256 vestingSchedule; // Vesting Period In Months.@dev
        uint8 vestingSlice; // No. Of time the cycle repeat.@dev
    }

    mapping(PoolType => PoolInfo) private _poolInfo;

    bool private _initialized;
    IERC20 private _token;
    address private _vesting;
    uint256 private _initTimestamp;

    modifier isInitialized() {
        if (_initialized == false) revert Uninitialized();
        _;
    }

    constructor(IERC20 token) {
        if (address(token) == address(0x0)) revert ZeroAddress();

        _token = token;
        _initialized = false;
    }

    function initialize(address vesting) external {
        if (_initialized == true) revert Initialized();
        if (vesting == address(0x0)) revert ZeroAddress();
        if (_token.balanceOf(address(this)) != 10 ** 9 * 10 ** 18)
            revert InsufficientBalance(
                10 ** 9 * 10 ** 18,
                _token.balanceOf(address(this))
            );

        _initTimestamp = getCurrentTime();
        _initialized = true;
        _vesting = vesting;

        // 30%, Available To remove at any moment.
        _addPool(PoolType.COMMUNITY, (300 * ((10 ** 6) * (10 ** 18))), 0, 0, 1);

        // 18%, 0% TGE, 24 month cliff, linear release at rate of 25% after every 12 months
        _addPool(PoolType.TEAM, (180 * ((10 ** 6) * (10 ** 18))), 24, 12, 4);

        // 3%, 0% TGE, 24 month cliff, linear release at rate of 25% after every 12 months
        _addPool(PoolType.ADVISORS, (30 * ((10 ** 6) * (10 ** 18))), 24, 12, 4);

        // 10%, No Info.
        _addPool(PoolType.MARKETING, (100 * ((10 ** 6) * (10 ** 18))), 0, 0, 1);

        // 10%, 0% TGE, 24 month cliff, linear release at rate of 25% after every 12 months
        _addPool(
            PoolType.ECOSYSTEM,
            (100 * ((10 ** 6) * (10 ** 18))),
            24,
            12,
            4
        );

        // 10%, 0% TGE, 12 month cliff, linear release at rate of 20% after every 4 months
        _addPool(PoolType.PUBLIC, (100 * ((10 ** 6) * (10 ** 18))), 12, 4, 5);

        // 4%, 0% TGE, 12 month cliff, linear release at rate of 20% after every 4 months
        _addPool(PoolType.PRIVATE, (40 * ((10 ** 6) * (10 ** 18))), 12, 4, 5);

        // 8%, 0% TGE, 12 month cliff, linear release at rate of 20% after every 4 months
        _addPool(PoolType.SEED, (80 * ((10 ** 6) * (10 ** 18))), 12, 4, 5);

        // 7%, 0% TGE, 12 month cliff, linear release at rate of 20% after every 4 months
        _addPool(PoolType.PRE_SEED, (70 * ((10 ** 6) * (10 ** 18))), 12, 4, 5);
    }

    function _addPool(
        PoolType _pool,
        uint256 _allocation,
        uint256 _cliff,
        uint256 _vestingSchedule,
        uint8 _slice
    ) internal {
        PoolInfo storage poolInfo = _poolInfo[_pool];

        poolInfo.pool = _pool;
        poolInfo.totalAmountAllocated = _allocation;
        poolInfo.userAllocatedAmount = 0;
        poolInfo.userWithdrawn = 0;
        poolInfo.cliffPeriod = _cliff;
        poolInfo.vestingSchedule = _vestingSchedule;
        poolInfo.vestingSlice = _slice;

        emit PoolAdded(
            _msgSender(),
            _pool,
            _allocation,
            _cliff,
            _vestingSchedule,
            _slice
        );
    }

    function withdrawUnallocatedToken(
        address _to
    ) external onlyOwner isInitialized {
        if (_to == address(0x0)) revert ZeroAddress();

        uint256 balanceOfContract = _token.balanceOf(address(this));
        uint256 unTransferredTokens = getTotalAllocatedToken() -
            getTotalTokenWithdrawn();
        uint256 execsToken = unTransferredTokens - balanceOfContract;

        if (execsToken == 0) revert ZeroAmount();
        _token.transfer(_to, execsToken);

        emit UnallocatedTokensWithdrawn(_to, execsToken);
    }

    function withdrawAvailableToken(
        address _to,
        uint256 _value,
        PoolType _pool
    ) external onlyOwner isInitialized {
        if (_to == address(0x0)) revert ZeroAddress();
        if (_value == 0) revert ZeroAmount();

        uint256 poolBalance = _poolInfo[_pool].totalAmountAllocated -
            _poolInfo[_pool].userAllocatedAmount;

        if (_value > poolBalance)
            revert InsufficientBalance(_value, poolBalance);

        _poolInfo[_pool].totalAmountAllocated -= _value;
        _token.safeTransfer(_to, _value);

        emit WithdrawnPoolUnallocatedToken(_to, _pool, _value);
    }

    function setDistribution(PoolType _pool, PoolInfo calldata _data) external {
        if (_msgSender() != _vesting) revert NonVestingContract();
        _poolInfo[_pool] = _data;
    }

    function setVestingAllowance(uint256 _amount) external {
        _token.approve(_vesting, _amount);
    }

    function getAllocatedToken(PoolType _pool) public view returns (uint256) {
        return _poolInfo[_pool].totalAmountAllocated;
    }

    function getTotalAllocatedToken() public view returns (uint256) {
        uint256 totalAllocatedCurdTokens = 0;

        for (uint8 i = 0; i <= uint8(type(PoolType).max); i++) {
            totalAllocatedCurdTokens += getAllocatedToken(
                CurdDistribution.PoolType(i)
            );
        }

        return totalAllocatedCurdTokens;
    }

    function getAvailableToken(PoolType _pool) public view returns (uint256) {
        return (_poolInfo[_pool].totalAmountAllocated -
            _poolInfo[_pool].userAllocatedAmount);
    }

    function getAllAvailableToken() public view returns (uint256) {
        uint256 totalAvailableCurdTokens = 0;

        for (uint8 i = 0; i <= uint8(type(PoolType).max); i++) {
            totalAvailableCurdTokens += getAvailableToken(PoolType(i));
        }

        return totalAvailableCurdTokens;
    }

    function getTotalTokenWithdrawn() public view returns (uint256) {
        uint256 totalUserWithdrawnToken = 0;

        for (uint8 i = 0; i <= uint8(type(PoolType).max); i++) {
            totalUserWithdrawnToken += _poolInfo[PoolType(i)].userWithdrawn;
        }

        return totalUserWithdrawnToken;
    }

    function getDistribution(
        PoolType _pool
    ) external view returns (PoolInfo memory) {
        return _poolInfo[_pool];
    }

    function getCurdVesting() external view returns (address) {
        return _vesting;
    }

    function getInitialTimestamp() external view returns (uint256) {
        return _initTimestamp;
    }

    function isInitialised() external view returns (bool) {
        return _initialized;
    }

    function renounceOwnership() public view override(Ownable) onlyOwner {
        revert NonRenounceable();
    }

    /**
     * @dev Returns the current time.
     * @return the current timestamp in seconds.
     */
    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function recoverToken(address token) external onlyOwner {
        if (token == address(0x0)) revert ZeroAddress();
        if (token == address(_token)) revert WrongToken();

        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        if (contractBalance == 0) revert ZeroAmount();

        IERC20(token).safeTransfer(_msgSender(), contractBalance);

        emit RecoveredERC20(token, contractBalance);
    }

    function recoverMatic() external payable onlyOwner {
        uint256 contractBalance = address(this).balance;
        if (contractBalance == 0) revert ZeroAmount();

        (bool status, bytes memory _data) = address(this).call{
            value: contractBalance
        }("");

        emit MaticTransferred(status, _data);
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
