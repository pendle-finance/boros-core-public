// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AMMId} from "../../../types/MarketTypes.sol";

library ExecuteConditionalOrderParamsLib {
    uint256 internal constant VERSION_1 = 1;

    function decodeVersion(bytes memory params) internal pure returns (uint256) {
        return abi.decode(params, (uint256));
    }

    function decodeBodyV1(
        bytes memory params
    ) internal pure returns (bool enterMarket, AMMId ammId, int128 desiredMatchRate) {
        ( /*version*/, enterMarket, ammId, desiredMatchRate) = abi.decode(params, (uint256, bool, AMMId, int128));
    }
}
