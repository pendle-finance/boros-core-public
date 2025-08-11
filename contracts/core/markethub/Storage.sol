// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

// External
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Interfaces
import {IMarketHubStorageOnly} from "../../interfaces/IMarketHub.sol";

// Libraries
import {ArrayLib} from "../../lib/ArrayLib.sol";
import {Err} from "../../lib/Errors.sol";

// Types
import {MarketAcc} from "../../types/Account.sol";
import {BulkOrder, MarketId, TokenId} from "../../types/MarketTypes.sol";
import {CreateCompute} from "../../types/createCompute.sol";

// Core
import {PendleRolesPlugin} from "../roles/PendleRoles.sol";

abstract contract Storage is IMarketHubStorageOnly, PendleRolesPlugin, Initializable {
    using ArrayLib for MarketId[];

    address public immutable MARKET_FACTORY;
    address public immutable ROUTER;
    address public immutable TREASURY;
    uint256 public immutable MAX_ENTERED_MARKETS;

    mapping(MarketAcc => MarketAccData) internal acc;
    mapping(TokenId => CashFeeData) internal cashFeeData;

    // Used only in deposit / withdrawal for scaling / tokenAddress
    TokenData[] internal _tokenData;

    // Used to register markets
    mapping(MarketId => address) internal _marketIdToAddress;

    // --- Health check ---
    MarketId[] internal _strictMarkets;
    mapping(MarketId => bool) internal _isStrictMarket;
    uint128 internal _strictMarketsFilter;
    int128 public critHR;

    // --- Force cancel all ---
    int256 public riskyThresHR;

    // --- Withdrawal ---
    uint32 public globalCooldown;

    mapping(address userAddr => mapping(TokenId => Withdrawal)) internal _withdrawal;
    // @dev store zero to use default cooldown duration.
    // @dev custom cooldown of `t` seconds is stored as `~t`.
    mapping(address userAddr => uint32) internal _personalCooldown;

    constructor(
        address permissionController_,
        address marketFactory_,
        address router_,
        address treasury_,
        uint256 maxEnteredMarkets_
    ) PendleRolesPlugin(permissionController_) {
        MARKET_FACTORY = marketFactory_;
        ROUTER = router_;
        TREASURY = treasury_;
        MAX_ENTERED_MARKETS = maxEnteredMarkets_;
    }

    modifier onlyRouter() {
        _checkOnlyRouter();
        _;
    }

    function _checkOnlyRouter() internal view {
        require(msg.sender == ROUTER || _PERM_CONTROLLER.canDirectCallMarketHub(msg.sender), Err.Unauthorized());
    }

    function __Storage_init(uint32 globalCooldown_) internal onlyInitializing {
        _tokenData.push(TokenData(address(0), 0));
        globalCooldown = globalCooldown_;
    }

    function _tokenDataChecked(TokenId tokenId) internal view returns (TokenData memory) {
        require(_isValidTokenId(tokenId), Err.MHTokenNotExists());
        return _tokenData[TokenId.unwrap(tokenId)];
    }

    function _getPersonalCooldown(address userAddr) internal view returns (uint32) {
        uint32 res = _personalCooldown[userAddr];
        return res != 0 ? ~res : globalCooldown;
    }

    /// @notice if the market was to have this id, it would be deployed at this address, but it's not guaranteed to be registered
    /// As a result, this function should only be used if it can be confirmed that the corresponding market is registered
    function _marketIdToAddrRaw(MarketId marketId) internal view returns (address) {
        return CreateCompute.compute(MARKET_FACTORY, marketId);
    }

    function _marketIdToAddrChecked(MarketId marketId) internal view returns (address) {
        address market = _marketIdToAddress[marketId];
        require(market != address(0), Err.MHMarketNotExists());
        return market;
    }

    function _addToEnteredMarkets(MarketAcc user, MarketId marketId) internal {
        MarketId[] storage markets = acc[user].enteredMarkets;
        require(!markets.include(marketId), Err.MMMarketAlreadyEntered());
        markets.push(marketId);
    }

    function _removeFromEnteredMarkets(MarketAcc user, MarketId marketId) internal {
        MarketId[] memory markets = acc[user].enteredMarkets;
        require(markets.remove(marketId), Err.MMMarketNotEntered());
        acc[user].enteredMarkets = markets;
    }

    function _checkEnteredMarkets(MarketAcc user, MarketId marketId) internal view {
        MarketId[] memory markets = acc[user].enteredMarkets;
        require(markets.include(marketId), Err.MMMarketNotEntered());
    }

    function _checkEnteredMarketsAndStrictHealth(
        MarketAcc user,
        MarketId marketId
    ) internal view returns (bool /*checkCritHealth*/) {
        MarketId[] memory markets = acc[user].enteredMarkets;
        require(markets.include(marketId), Err.MMMarketNotEntered());
        return _hasStrictMarkets(markets);
    }

    function _checkEnteredMarketsAndStrictHealth(
        MarketAcc user,
        BulkOrder[] memory bulks
    ) internal view returns (bool /*checkCritHealth*/) {
        MarketId[] memory markets = acc[user].enteredMarkets;
        for (uint256 i = 0; i < bulks.length; i++) {
            require(markets.include(bulks[i].marketId), Err.MMMarketNotEntered());
        }
        return _hasStrictMarkets(markets);
    }

    function _toScaled(uint256 unscaledAmount, uint96 scalingFactor) internal pure returns (uint256) {
        return unscaledAmount * scalingFactor;
    }

    function _toUnscaled(uint256 scaledAmount, uint96 scalingFactor) internal pure returns (uint256) {
        return scaledAmount / scalingFactor;
    }

    function _hashMarketId(MarketId marketId) internal pure returns (uint8) {
        return uint8(MarketId.unwrap(marketId) % 128);
    }

    function _hasStrictMarkets(MarketId[] memory markets) internal view returns (bool) {
        uint256 filter = _strictMarketsFilter;
        for (uint256 i = 0; i < markets.length; i++) {
            uint8 b = _hashMarketId(markets[i]);
            if ((filter & (1 << b)) != 0 && _isStrictMarket[markets[i]]) {
                return true;
            }
        }
        return false;
    }

    function _isValidTokenId(TokenId tokenId) internal view returns (bool) {
        return TokenId.unwrap(tokenId) != 0 && TokenId.unwrap(tokenId) < _tokenData.length;
    }
}
