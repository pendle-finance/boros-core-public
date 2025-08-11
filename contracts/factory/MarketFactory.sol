// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IMarketFactory} from "./../interfaces/IMarketFactory.sol";
import {IMarketHub} from "./../interfaces/IMarketHub.sol";
import {IMarketSetting} from "./../interfaces/IMarket.sol";
import {PendleRolesPlugin} from "./../core/roles/PendleRoles.sol";
import {TokenId, MarketId} from "./../types/MarketTypes.sol";
import {MarketImpliedRateLib} from "./../types/MarketImpliedRate.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PMath} from "./../lib/math/PMath.sol";
import {Err} from "./../lib/Errors.sol";
import {CreateCompute} from "./../types/createCompute.sol";

/// @notice This will be deployed as TransparentUpgradeableProxy
contract MarketFactory is IMarketFactory, PendleRolesPlugin, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using PMath for uint256;

    EnumerableSet.AddressSet internal allMarkets;
    address public immutable IMPLEMENTATION;
    address public immutable MARKET_HUB;
    uint24 public marketNonce;

    constructor(
        address _marketHub,
        address _implementation,
        address permissionController_
    ) PendleRolesPlugin(permissionController_) {
        _disableInitializers();
        MARKET_HUB = _marketHub;
        IMPLEMENTATION = _implementation;
    }

    function initialize() external initializer onlyRole(_INITIALIZER_ROLE) {
        marketNonce = 1;
    }

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
    ) external onlyAuthorized returns (address newMarket) {
        require(IMarketHub(MARKET_HUB).tokenData(tokenId).token != address(0), Err.InvalidTokenId());

        MarketId newMarketId = MarketId.wrap(++marketNonce);
        MarketImmutableDataStruct memory immData = MarketImmutableDataStruct({
            name: name,
            symbol: symbol,
            k_isIsolatedOnly: isIsolatedOnly,
            k_maturity: maturity,
            k_tokenId: tokenId,
            k_marketId: newMarketId,
            k_tickStep: tickStep,
            k_iTickThresh: iTickThresh
        });

        newMarket = address(
            new TransparentUpgradeableProxy(
                IMPLEMENTATION,
                msg.sender,
                abi.encodeCall(IMarketSetting.initialize, (immData, config, impliedRateInit))
            )
        );

        address computedAddress = CreateCompute.compute(address(this), newMarketId);
        assert(computedAddress == newMarket);

        assert(allMarkets.add(newMarket));

        emit MarketCreated(newMarket, immData, config);
    }
}
