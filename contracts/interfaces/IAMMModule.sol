// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Trade} from "./../types/Trade.sol";
import {IRouterEventsAndTypes} from "./IRouterEventsAndTypes.sol";

interface IAMMModule is IRouterEventsAndTypes {
    function swapWithAmm(SwapWithAmmReq memory req) external returns (Trade matched, uint256 otcFee);

    function addLiquidityDualToAmm(
        AddLiquidityDualToAmmReq memory req
    ) external returns (uint256 netLpOut, int256 netCashIn, uint256 netOtcFee);

    function addLiquiditySingleCashToAmm(
        AddLiquiditySingleCashToAmmReq memory req
    ) external returns (uint256 netLpOut, int256 netCashUsed, uint256 totalTakerOtcFee, Trade swapTradeInterm);

    function removeLiquidityDualFromAmm(
        RemoveLiquidityDualFromAmmReq memory req
    ) external returns (int256 netCashOut, int256 netSizeOut, uint256 netOtcFee);

    function removeLiquiditySingleCashFromAmm(
        RemoveLiquiditySingleCashFromAmmReq memory req
    ) external returns (int256 netCashOut, uint256 netTakerOtcFee, Trade swapTradeInterm);
}
