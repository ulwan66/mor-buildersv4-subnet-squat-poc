// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Minimal cheatcode interface (avoids forge-std dependency), following h-mor-03 layout.
interface Vm {
    function createSelectFork(string calldata url, uint256 blockNumber) external returns (uint256);
    function rollFork(uint256 blockNumber) external;
    function warp(uint256 newTimestamp) external;
    function prank(address msgSender) external;
    function deal(address account, uint256 newBalance) external;
    function load(address target, bytes32 slot) external view returns (bytes32 data);
    function store(address target, bytes32 slot, bytes32 value) external;
    function envOr(string calldata name, string calldata defaultValue) external returns (string memory);
    function snapshotState() external returns (uint256 snapshotId);
    function revertToState(uint256 snapshotId) external returns (bool success);
    function expectRevert() external;
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface IFeeConfig {
    function getFeeAndTreasuryForOperation(address sender, bytes32 operation) external view returns (uint256 feePart, address treasury);
}

interface IRewardPoolBuilders {
    function getPeriodRewards(uint256 rewardPoolIndex, uint128 start, uint128 end) external view returns (uint256);
}

interface IBuilders {
    struct Subnet {
        string name;
        address admin;
        uint128 unusedStorage1_V4Update;
        uint128 withdrawLockPeriodAfterDeposit;
        uint128 unusedStorage2_V4Update;
        uint256 minimalDeposit;
        address claimAdmin;
    }
    struct SubnetMetadata {
        string slug;
        string description;
        string website;
        string image;
    }
    function createSubnet(Subnet calldata subnet_, SubnetMetadata calldata metadata_) external;
    function deposit(bytes32 subnetId_, uint256 amount_) external;
    function withdraw(bytes32 subnetId_, uint256 amount_) external;
    function claim(bytes32 subnetId_, address receiver_) external;
    function getSubnetId(string memory subnetName_) external view returns (bytes32);
    function getSubnetIdOld(string memory subnetName_) external pure returns (bytes32);
    function getCurrentSubnetRewards(bytes32 subnetId_) external view returns (uint256);
    function getCurrentSubnetsRewards() external view returns (uint256);
    function subnetCreationFeeAmount() external view returns (uint256);
    function minimalWithdrawLockPeriod() external view returns (uint256);
    function networkShare() external view returns (uint256);
    function feeConfig() external view returns (address);
    function buildersTreasury() external view returns (address);
    function depositToken() external view returns (address);
    function rewardPool() external view returns (address);
    // Public mapping getters: struct fields as separate return values.
    function subnets(bytes32 subnetId) external view returns (
        string memory name, address admin, uint128 unused1, uint128 withdrawLockPeriodAfterDeposit,
        uint128 unused2, uint256 minimalDeposit, address claimAdmin
    );
    function subnetsData(bytes32 subnetId) external view returns (
        uint128 unused1, uint256 deposited, uint256 unused2, uint256 rate, uint256 pendingRewards
    );
    function usersData(address user, bytes32 subnetId) external view returns (
        uint128 lastDeposit, uint128 unused1, uint256 deposited, uint256 unused2
    );
    function allSubnetsData() external view returns (
        uint256 unused1, uint256 rate, uint256 totalDeposited, uint256 unused2
    );
    function allSubnetsDataV4() external view returns (
        uint256 distributedRewards, uint256 undistributedRewards, uint256 claimedRewards, uint128 lastUpdate
    );
}

interface ITreasury {
    function rewardToken() external view returns (address);
    function builders() external view returns (address);
    function distributedRewards() external view returns (uint256);
}
