// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IAMMModule} from "./IAMMModule.sol";
import {IAuthModule} from "./IAuthModule.sol";
import {IConditionalModule} from "./IConditionalModule.sol";
import {IDepositModule} from "./IDepositModule.sol";
import {IMiscModule} from "./IMiscModule.sol";
import {ITradeModule} from "./ITradeModule.sol";

// solhint-disable-next-line no-empty-blocks
interface IRouter is IAMMModule, IAuthModule, IConditionalModule, IDepositModule, IMiscModule, ITradeModule {}
