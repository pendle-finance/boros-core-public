// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {FIndex} from "../types/MarketTypes.sol";

interface IFIndexOracle {
    event ConfigUpdated(uint64 newSettleFeeRate, uint32 newUpdatePeriod, uint32 newMaxUpdateDelay);

    event KeeperUpdated(address newKeeper);

    function updateFloatingIndex(int112 floatingIndexDelta, uint32 desiredTimestamp) external;

    // View functions

    function isDueForUpdateNow() external view returns (bool);

    function getLatestFIndex() external view returns (FIndex);

    function latestAnnualizedRate() external view returns (int256 rate);

    function maturity() external view returns (uint32);

    function market() external view returns (address);

    function nextFIndexUpdateTime() external view returns (uint32);

    // Config

    function setConfig(uint64 settleFeeRate, uint32 updatePeriod, uint32 maxFUpdateDelay) external;

    function getConfig() external view returns (uint64 settleFeeRate, uint32 updatePeriod, uint32 maxUpdateDelay);

    function setKeeper(address keeper) external;

    function keeper() external view returns (address);
}
