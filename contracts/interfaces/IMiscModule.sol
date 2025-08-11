// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Account, MarketAcc} from "../types/Account.sol";
import {AMMId, TokenId} from "../types/MarketTypes.sol";

interface IMiscModule {
    event ApprovedMarketHubInf(TokenId tokenId);
    event AllowedRelayerUpdated(address relayer, bool allowed);
    event AMMIdToAccUpdated(AMMId ammId, MarketAcc amm);
    event NumTicksToTryAtOnceUpdated(uint16 newNumTicksToTryAtOnce);
    event MaxIterationAndEpsUpdated(uint256 newMaxIteration, uint256 newEps);

    event TryAggregateCallSucceeded(uint256 index);
    event TryAggregateCallFailed(uint256 index, bytes4 errorSelector);

    struct Result {
        bool success;
        bytes returnData;
    }

    struct SimulateData {
        Account account;
        address target;
        bytes data;
    }

    function initialize(string memory eip712Name, string memory eip712Version, uint16 numTicksToTryAtOnce) external;

    function tryAggregate(
        bool requireSuccess,
        bytes[] memory calls
    ) external returns (Result[] memory returnData, uint256[] memory gasUsed);

    function batchSimulate(
        SimulateData[] memory calls
    ) external returns (bytes[] memory results, uint256[] memory gasUsed);

    function batchRevert(SimulateData[] memory calls) external;

    function isAllowedRelayer(address relayer) external view returns (bool);

    function ammIdToAcc(AMMId ammId) external view returns (MarketAcc);

    function numTicksToTryAtOnce() external view returns (uint16);

    function maxIterationAndEps() external view returns (uint256 maxIteration, uint256 eps);

    function approveMarketHubInf(TokenId tokenId) external;

    function setAllowedRelayer(address relayer, bool allowed) external;

    function setAMMIdToAcc(address amm, bool forceOverride) external;

    function setNumTicksToTryAtOnce(uint16 newNumTicksToTryAtOnce) external;

    function setMaxIterationAndEps(uint256 newMaxIteration, uint256 newEps) external;
}
