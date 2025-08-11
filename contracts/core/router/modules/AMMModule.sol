// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Err} from "./../../../lib/Errors.sol";
import {PaymentLib} from "./../../../lib/PaymentLib.sol";
import {PMath} from "./../../../lib/math/PMath.sol";
import {IAMMModule} from "./../../../interfaces/IAMMModule.sol";
import {MarketAcc} from "./../../../types/Account.sol";
import {LongShort, OrdersLib, AMMId, CancelData} from "./../../../types/MarketTypes.sol";
import {Side, TimeInForce, OrderIdLib} from "./../../../types/Order.sol";
import {Trade} from "./../../../types/Trade.sol";
import {RouterAccountBase} from "./../auth-base/RouterAccountBase.sol";
import {LiquidityMathParams} from "./../math/LiquidityMath.sol";
import {SwapMathParams} from "./../math/SwapMath.sol";
import {BookAmmSwapBase} from "./../trade-base/BookAmmSwapBase.sol";

contract AMMModule is IAMMModule, RouterAccountBase, BookAmmSwapBase {
    using PaymentLib for Trade;
    using PMath for uint256;

    int16 private constant _MAX_TICK = type(int16).max;
    int16 private constant _MIN_TICK = type(int16).min;

    constructor(address marketHub_) BookAmmSwapBase(marketHub_) {}

    function swapWithAmm(
        SwapWithAmmReq memory req
    ) external setNonAuth returns (Trade /*matched*/, uint256 /*otcFee*/) {
        (MarketAcc user, MarketAcc amm) = _getUserAndAMM(req.cross, req.ammId);
        LongShort memory emptyOrders;
        CancelData memory emptyCancels;

        (Trade matched, uint256 otcFee) = _swapBookAMM(user, amm, req.signedSize, emptyOrders, emptyCancels);
        matched.requireDesiredRate(req.desiredSwapRate);

        emit SwapWithAmm(user, amm.marketId(), req.ammId, matched, otcFee);

        return (matched, otcFee);
    }

    function addLiquidityDualToAmm(
        AddLiquidityDualToAmmReq memory req
    ) external setNonAuth returns (uint256 /*netLpOut*/, int256 /*netCashIn*/, uint256 /*netOtcFee*/) {
        (MarketAcc user, MarketAcc amm) = _getUserAndAMM(req.cross, req.ammId);

        (uint256 netLpOut, int256 netCashIn, uint256 netOtcFee) = _mintAMM(user, amm, req.maxCashIn, req.exactSizeIn);

        require(netCashIn <= req.maxCashIn, Err.AMMInsufficientCashIn());
        require(netLpOut >= req.minLpOut, Err.AMMInsufficientLpOut());

        emit AddLiquidityDualToAmm(user, req.ammId, req.exactSizeIn, netLpOut, netCashIn, netOtcFee);

        return (netLpOut, netCashIn, netOtcFee);
    }

    function addLiquiditySingleCashToAmm(
        AddLiquiditySingleCashToAmmReq memory req
    )
        external
        setNonAuth
        returns (uint256 /*netLpOut*/, int256 /*netCashIn*/, uint256 /*totalTakerOtcFee*/, int256 /*swapSizeOut*/)
    {
        (MarketAcc user, MarketAcc amm) = _getUserAndAMM(req.cross, req.ammId);

        if (req.enterMarket) {
            _MARKET_HUB.enterMarket(user, amm.marketId());
        }

        (int256 swapSizeOut, int256 swapCashIn, uint256 swapTakerOtcFee) = _swapToAddLiquidity(req, user, amm);

        AddLiquiditySingleCashToAmmReq memory _req = req; // hoist to avoid stack too deep
        (uint256 netLpOut, int256 mintCashIn, uint256 mintOtcFee) = _mintAMM(
            user,
            amm,
            _req.netCashIn - swapCashIn,
            swapSizeOut
        );

        int256 netCashIn = swapCashIn + mintCashIn;

        require(netLpOut >= _req.minLpOut, Err.AMMInsufficientLpOut());
        require(netCashIn <= _req.netCashIn, Err.AMMInsufficientCashIn());

        uint256 totalTakerOtcFee = swapTakerOtcFee + mintOtcFee;
        emit AddLiquiditySingleCashToAmm(user, _req.ammId, netLpOut, netCashIn, totalTakerOtcFee, swapSizeOut);

        return (netLpOut, netCashIn, totalTakerOtcFee, swapSizeOut);
    }

    function removeLiquidityDualFromAmm(
        RemoveLiquidityDualFromAmmReq memory req
    ) external setNonAuth returns (int256 /*netCashOut*/, int256 /*netSizeOut*/, uint256 /*netOtcFee*/) {
        (MarketAcc user, MarketAcc amm) = _getUserAndAMM(req.cross, req.ammId);

        (int256 netCashOut, int256 netSizeOut, uint256 netOtcFee) = _burnAMM(user, amm, req.lpToRemove);

        require(req.minSizeOut <= netSizeOut && netSizeOut <= req.maxSizeOut, Err.AMMInsufficientSizeOut());
        require(netCashOut >= req.minCashOut, Err.AMMInsufficientCashOut());

        emit RemoveLiquidityDualFromAmm(user, req.ammId, req.lpToRemove, netCashOut, netSizeOut, netOtcFee);

        return (netCashOut, netSizeOut, netOtcFee);
    }

    function removeLiquiditySingleCashFromAmm(
        RemoveLiquiditySingleCashFromAmmReq memory req
    ) external setNonAuth returns (int256 netCashOut, uint256 netTakerOtcFee, int256 swapSizeInterm) {
        (MarketAcc user, MarketAcc amm) = _getUserAndAMM(req.cross, req.ammId);

        (int256 burnCashOut, int256 burnSizeOut, uint256 burnOtcFee) = _burnAMM(user, amm, req.lpToRemove);

        netCashOut = burnCashOut;
        netTakerOtcFee = burnOtcFee;
        swapSizeInterm = -burnSizeOut;

        if (swapSizeInterm != 0) {
            MarketCache memory cache = _getMarketCache(amm.marketId());

            (Side side, int16 limitTick) = _toSideAndLimitTick(swapSizeInterm);
            SwapMathParams memory swaps = _createSwapMathParams(cache, user, amm, side, _getTimeToMat(cache));

            (Trade matched, uint256 takerOtcFee) = _splitAndSwapBookAMM(
                swaps,
                TimeInForce.FOK,
                swapSizeInterm,
                limitTick,
                OrderIdLib.ZERO
            );

            netCashOut -= matched.toUpfrontFixedCost(_getTimeToMat(cache)) + takerOtcFee.Int();
            netTakerOtcFee += takerOtcFee;
        }

        require(netCashOut >= req.minCashOut, Err.AMMInsufficientCashOut());

        emit RemoveLiquiditySingleCashFromAmm(
            user,
            req.ammId,
            req.lpToRemove,
            netCashOut,
            netTakerOtcFee,
            swapSizeInterm
        );

        return (netCashOut, netTakerOtcFee, swapSizeInterm);
    }

    function _getUserAndAMM(bool cross, AMMId ammId) internal view returns (MarketAcc user, MarketAcc amm) {
        amm = _getAMMIdToAcc(ammId);
        user = _account().toMarketAcc(cross, amm.tokenId(), amm.marketId());
    }

    function _toSideAndLimitTick(int256 signedSize) internal pure returns (Side side, int16 limitTick) {
        if (signedSize > 0) {
            (side, limitTick) = (Side.LONG, _MAX_TICK);
        } else {
            (side, limitTick) = (Side.SHORT, _MIN_TICK);
        }
    }

    function _swapToAddLiquidity(
        AddLiquiditySingleCashToAmmReq memory req,
        MarketAcc user,
        MarketAcc amm
    ) internal returns (int256 /*netSizeOut*/, int256 /*netCashIn*/, uint256 /*takerOtcFee*/) {
        LiquidityMathParams memory params = _createLiquidityMathParams(req, user, amm);

        (int256 withBook, int256 withAMM) = params.approxSwapToAddLiquidity();

        LongShort memory orders;
        if (withBook != 0) {
            (, int16 limitTick) = _toSideAndLimitTick(params.ammSize);
            orders = OrdersLib.createOrders(TimeInForce.FOK, withBook, limitTick);
        }

        CancelData memory emptyCancels;
        (Trade totalMatched, uint256 takerOtcFee) = _swapBookAMM(user, amm, withAMM, orders, emptyCancels);

        int256 netSizeOut = totalMatched.signedSize();

        int256 netCashIn = totalMatched.toUpfrontFixedCost(params.timeToMat()) + takerOtcFee.Int();

        return (netSizeOut, netCashIn, takerOtcFee);
    }

    function _createLiquidityMathParams(
        AddLiquiditySingleCashToAmmReq memory req,
        MarketAcc user,
        MarketAcc amm
    ) internal returns (LiquidityMathParams memory) {
        MarketCache memory cache = _getMarketCache(amm.marketId());

        (int256 ammCash, int256 ammSize) = _settleAndGetCashAMM(amm);
        require(ammCash > 0 && req.netCashIn > 0, Err.AMMInvalidParams());

        Side userSide = ammSize > 0 ? Side.LONG : Side.SHORT;

        return
            LiquidityMathParams({
                _core: _createSwapMathParams(cache, user, amm, userSide, _getTimeToMat(cache)),
                maxIteration: _getMaxIterationAddLiquidity(),
                eps: _getEpsAddLiquidity(),
                ammCash: ammCash,
                ammSize: ammSize,
                totalCashIn: req.netCashIn
            });
    }
}
