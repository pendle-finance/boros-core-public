// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IRouterEventsAndTypes} from "./IRouterEventsAndTypes.sol";

interface IConditionalModule is IRouterEventsAndTypes {
    event ConditionalValidatorUpdated(address validator, bool isValidator);

    function executeConditionalOrder(ExecuteConditionalOrderReq memory req) external;

    function setConditionalValidator(address validator, bool isValidator) external;

    function isConditionalValidator(address validator) external view returns (bool);

    function isActionExecuted(bytes32 actionHash) external view returns (bool);
}
