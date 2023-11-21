//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface ICurdDistribution {
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

    struct PoolInfo {
        PoolType pool;
        uint256 totalAmountAllocated; // Total amount allocated to the pool.@dev
        uint256 userAllocatedAmount; // Amount allocated to beneficiary in vesting contract.@dev
        uint256 userWithdrawn;
        uint256 cliffPeriod; // Cliff Period In Months.@dev
        uint256 vestingSchedule; // Vesting Period In Months.@dev
        uint8 vestingSlice; // No. Of time the cycle repeat.@dev
    }

    function getDistribution(
        PoolType _pool
    ) external returns (PoolInfo calldata);

    function setDistribution(PoolType _pool, PoolInfo calldata _data) external;
}
