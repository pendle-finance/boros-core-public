// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IAuthModule} from "./IAuthModule.sol";
import {ITradeModule} from "./ITradeModule.sol";
import {IMiscModule} from "./IMiscModule.sol";
import {IAMMModule} from "./IAMMModule.sol";

// solhint-disable-next-line no-empty-blocks
interface IRouter is IAuthModule, ITradeModule, IMiscModule, IAMMModule {}
