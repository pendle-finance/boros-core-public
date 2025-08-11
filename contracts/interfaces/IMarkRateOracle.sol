// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IMarkRateOracle {
    function getMarkRate() external view returns (int256);
}
