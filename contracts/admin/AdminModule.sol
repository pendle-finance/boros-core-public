// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PendleRolesPlugin} from "./../core/roles/PendleRoles.sol";
import {IAdminModule} from "./../interfaces/IAdminModule.sol";
import {IAMM} from "./../interfaces/IAMM.sol";
import {IAMMFactory, AMMCreateParams, AMMSeedParams} from "./../interfaces/IAMMFactory.sol";
import {IMarket} from "./../interfaces/IMarket.sol";
import {IMarketHub, IMarketHubAllEventsAndTypes} from "./../interfaces/IMarketHub.sol";
import {PMath} from "./../lib/math/PMath.sol";
import {MarketAcc} from "./../types/Account.sol";
import {LongShort, MarketId, OTCTrade, CancelData} from "./../types/MarketTypes.sol";
import {TradeLib} from "./../types/Trade.sol";

/// @notice This will be deployed as TransparentUpgradeableProxy
contract AdminModule is IAdminModule, PendleRolesPlugin {
    using PMath for uint256;

    address public immutable AMM_FACTORY;
    IMarketHub internal immutable _MARKET_HUB;

    constructor(
        address ammFactory_,
        address marketHub_,
        address permissionController_
    ) PendleRolesPlugin(permissionController_) {
        AMM_FACTORY = ammFactory_;
        _MARKET_HUB = IMarketHub(marketHub_);
    }

    function newAMM(
        bool isPositive,
        AMMCreateParams memory createParams,
        AMMSeedParams memory seedParams
    ) external onlyAuthorized returns (address amm) {
        MarketId marketId = _getAndValidateMarketId(createParams.market);

        amm = IAMMFactory(AMM_FACTORY).create(isPositive, createParams, seedParams);
        MarketAcc ammAccount = IAMM(amm).SELF_ACC();

        IMarketHubAllEventsAndTypes.CashFeeData memory cashFeeData = _MARKET_HUB.getCashFeeData(ammAccount.tokenId());
        uint256 marketEntranceFee = cashFeeData.marketEntranceFee;
        uint256 minCash = ammAccount.isCross() ? cashFeeData.minCashCross : cashFeeData.minCashIsolated;
        _MARKET_HUB.cashTransfer(createParams.seeder, ammAccount, (marketEntranceFee + minCash).Int());
        _MARKET_HUB.enterMarket(ammAccount, marketId);
        _MARKET_HUB.cashTransfer(ammAccount, createParams.seeder, minCash.Int());

        LongShort memory emptyOrders;
        CancelData memory emptyCancels;
        OTCTrade[] memory OTCs = new OTCTrade[](1);
        OTCs[0] = OTCTrade({
            counter: ammAccount,
            trade: TradeLib.from(-seedParams.initialSize, 0),
            cashToCounter: seedParams.initialCash.Int()
        });
        _MARKET_HUB.orderAndOtc(marketId, createParams.seeder, emptyOrders, emptyCancels, OTCs);
    }

    function _getAndValidateMarketId(address market) internal view returns (MarketId) {
        (, , MarketId marketId, , , , ) = IMarket(market).descriptor();
        require(_MARKET_HUB.marketIdToAddress(marketId) == market);
        return marketId;
    }
}
