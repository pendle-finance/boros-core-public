// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IPDepositBoxFactory} from "./IPDepositBoxFactory.sol";
import {IRouterEventsAndTypes} from "./IRouterEventsAndTypes.sol";

interface IDepositModule is IRouterEventsAndTypes {
    function depositFromBox(DepositFromBoxMessage memory message, bytes memory signature) external;

    function withdrawFromBox(WithdrawFromBoxMessage memory message, bytes memory signature) external;

    function DEPOSIT_BOX_FACTORY() external view returns (IPDepositBoxFactory);
}
