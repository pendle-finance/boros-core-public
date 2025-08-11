// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {TokenId} from "./../types/MarketTypes.sol";
import {IMarketAllTypes} from "./../interfaces/IMarket.sol";
import {MarketImpliedRateLib} from "./../types/MarketImpliedRate.sol";

interface IMarketFactory is IMarketAllTypes {
    event MarketCreated(address market, MarketImmutableDataStruct immData, MarketConfigStruct config);

    function create(
        string memory name,
        string memory symbol,
        bool isIsolatedOnly,
        uint32 maturity,
        TokenId tokenId,
        uint8 tickStep,
        uint16 iTickThresh,
        MarketConfigStruct memory config,
        MarketImpliedRateLib.InitStruct memory impliedRateInit
    ) external returns (address newMarket);

    function MARKET_HUB() external view returns (address);

    function IMPLEMENTATION() external view returns (address);

    function marketNonce() external view returns (uint24);
}
