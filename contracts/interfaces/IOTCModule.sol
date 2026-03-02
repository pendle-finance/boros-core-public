// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IRouterEventsAndTypes} from "./IRouterEventsAndTypes.sol";

interface IOTCModule is IRouterEventsAndTypes {
    event OTCTradeValidatorUpdated(address validator);

    function executeOTCTrade(ExecuteOTCTradeReq memory req) external;

    function setOTCTradeValidator(address validator) external;

    function otcTradeValidator() external view returns (address);

    function isOTCTradeExecuted(bytes32 tradeHash) external view returns (bool);
}
