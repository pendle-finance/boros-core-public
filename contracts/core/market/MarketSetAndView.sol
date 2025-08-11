// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Interfaces
import {IFIndexOracle} from "../../interfaces/IFIndexOracle.sol";
import {IMarketSetting} from "../../interfaces/IMarket.sol";

// Libraries
import {Err} from "../../lib/Errors.sol";
import {PMath} from "../../lib/math/PMath.sol";
import {FixedWindowObservationLib} from "../../lib/FixedWindowObservationLib.sol";

// Types
import {MarketAcc} from "../../types/Account.sol";
import {FIndex} from "../../types/MarketTypes.sol";
import {MarketImpliedRateLib} from "../../types/MarketImpliedRate.sol";

// Core
import {PendleRolesPlugin} from "../roles/PendleRoles.sol";

// Components
import {MarketInfoAndState} from "./core/MarketInfoAndState.sol";
import {MarketOffView} from "./MarketOffView.sol";

contract MarketSetAndView is IMarketSetting, MarketOffView, PendleRolesPlugin {
    constructor(
        address marketHub_,
        address permissionController_
    ) MarketInfoAndState(marketHub_) PendleRolesPlugin(permissionController_) {
        _disableInitializers();
    }

    // ---------- Initializer ----------
    function initialize(
        MarketImmutableDataStruct memory initialImmData,
        MarketConfigStruct memory initialConfig,
        MarketImpliedRateLib.InitStruct memory impliedRateInit
    ) external initializer onlyRole(_INITIALIZER_ROLE) {
        _setImmData(initialImmData);

        _setGlobalMaxOpenOrders(initialConfig.maxOpenOrders);
        _setGlobalOracleAddresses(initialConfig.markRateOracle, initialConfig.fIndexOracle);
        _setGlobalHardOICap(initialConfig.hardOICap);
        _setGlobalFeeRates(initialConfig.takerFee, initialConfig.otcFee);
        _setGlobalLiquidationSettings(initialConfig.liqSettings);
        _setGlobalMarginConfig(initialConfig.kIM, initialConfig.kMM, initialConfig.tThresh);
        _setGlobalRateBoundConfig(initialConfig.maxRateDeviationFactorBase1e4, initialConfig.closingOrderBoundBase1e4);
        _setGlobalLimitOrderConfig(
            initialConfig.loUpperConstBase1e4,
            initialConfig.loUpperSlopeBase1e4,
            initialConfig.loLowerConstBase1e4,
            initialConfig.loLowerSlopeBase1e4
        );
        _setGlobalStatus(initialConfig.status);

        _updateFIndex(IFIndexOracle(initialConfig.fIndexOracle).getLatestFIndex());
        _initImpliedRateOracle(impliedRateInit);
    }

    // ---------- Admin SET  ----------

    modifier onlyFIndexOracle() {
        require(msg.sender == _ctx().fIndexOracle, Err.Unauthorized());
        _;
    }

    // ---------- Personal SET  ----------
    function setPersonalMarginConfig(MarketAcc user, uint64 newKIM, uint64 newKMM) external onlyAuthorized {
        (_accState(user).kIM, _accState(user).kMM) = (newKIM, newKMM);
        emit PersonalMarginConfigUpdated(user, newKIM, newKMM);
    }

    function setPersonalDiscRates(MarketAcc user, uint64 newTakerDisc, uint64 newOtcDisc) external onlyAuthorized {
        _ensureValidDiscRates(newTakerDisc, newOtcDisc);
        (_accState(user).takerDisc, _accState(user).otcDisc) = (newTakerDisc, newOtcDisc);
        emit PersonalDiscRatesUpdated(user, newTakerDisc, newOtcDisc);
    }

    function setPersonalExemptCLOCheck(MarketAcc user, bool exemptCLOCheck) external onlyAuthorized {
        _accState(user).exemptCLOCheck = exemptCLOCheck;
        emit PersonalExemptCLOCheckUpdated(user, exemptCLOCheck);
    }

    // ---------- Global SET  ----------
    function setGlobalImpliedWindow(uint32 newWindow) external onlyAuthorized {
        FixedWindowObservationLib.validateWindow(newWindow);
        _ctx().impliedRate = _ctx().impliedRate.replaceWindow(newWindow);
        emit ImpliedRateObservationWindowUpdated(newWindow);
    }

    function setGlobalMaxOpenOrders(uint16 newMaxOpenOrders) external onlyAuthorized {
        _setGlobalMaxOpenOrders(newMaxOpenOrders);
    }

    function setGlobalOracleAddresses(address newMarkRateOracle, address newFIndexOracle) external onlyAuthorized {
        _setGlobalOracleAddresses(newMarkRateOracle, newFIndexOracle);
    }

    function setGlobalHardOICap(uint128 newHardOICap) external onlyAuthorized {
        _setGlobalHardOICap(newHardOICap);
    }

    function setGlobalFeeRates(uint64 newTakerFee, uint64 newOtcFee) external onlyAuthorized {
        _setGlobalFeeRates(newTakerFee, newOtcFee);
    }

    function setGlobalLiquidationSettings(LiqSettings memory newLiqSettings) external onlyAuthorized {
        _setGlobalLiquidationSettings(newLiqSettings);
    }

    function setGlobalMarginConfig(uint64 newKIM, uint64 newKMM, uint32 newTThresh) external onlyAuthorized {
        _setGlobalMarginConfig(newKIM, newKMM, newTThresh);
    }

    function setGlobalRateBoundConfig(
        uint16 newMaxRateDeviationFactorBase1e4,
        uint16 newClosingOrderBoundBase1e4
    ) external onlyAuthorized {
        _setGlobalRateBoundConfig(newMaxRateDeviationFactorBase1e4, newClosingOrderBoundBase1e4);
    }

    function setGlobalLimitOrderConfig(
        int16 loUpperConstBase1e4,
        int16 loUpperSlopeBase1e4,
        int16 loLowerConstBase1e4,
        int16 loLowerSlopeBase1e4
    ) external onlyAuthorized {
        _setGlobalLimitOrderConfig(loUpperConstBase1e4, loUpperSlopeBase1e4, loLowerConstBase1e4, loLowerSlopeBase1e4);
    }

    function setGlobalStatus(MarketStatus newStatus) external onlyAuthorized {
        _setGlobalStatus(newStatus);
    }

    function updateFIndex(FIndex newIndex) external onlyFIndexOracle {
        _updateFIndex(newIndex);
    }

    function _setImmData(MarketImmutableDataStruct memory data) internal {
        require(data.k_maturity > uint32(block.timestamp), Err.InvalidMaturity());
        require(0 < data.k_tickStep && data.k_tickStep < 16);
        require(data.k_iTickThresh <= uint16(type(int16).max));
        _ctx().name = data.name;
        _ctx().symbol = data.symbol;
        _ctx().k_isIsolatedOnly = data.k_isIsolatedOnly;
        _ctx().k_maturity = data.k_maturity;
        _ctx().k_tokenId = data.k_tokenId;
        _ctx().k_marketId = data.k_marketId;
        _ctx().k_tickStep = data.k_tickStep;
        _ctx().k_iTickThresh = data.k_iTickThresh;
    }

    function _initImpliedRateOracle(MarketImpliedRateLib.InitStruct memory impliedRateInit) internal {
        FixedWindowObservationLib.validateWindow(impliedRateInit.window);
        _ctx().impliedRate = MarketImpliedRateLib.initialize(impliedRateInit);
        emit ImpliedRateObservationWindowUpdated(impliedRateInit.window);
    }

    function _setGlobalMaxOpenOrders(uint16 newMaxOpenOrders) internal {
        _ctx().maxOpenOrders = newMaxOpenOrders;
        emit MaxOpenOrdersUpdated(newMaxOpenOrders);
    }

    function _setGlobalOracleAddresses(address newMarkRateOracle, address newFIndexOracle) internal {
        _ensureValidFIndexOracle(newFIndexOracle, _ctx().k_maturity);

        if (newMarkRateOracle == address(0)) {
            (_ctx().useImpliedAsMarkRate, _ctx().markRateOracle) = (true, address(0));
        } else {
            (_ctx().useImpliedAsMarkRate, _ctx().markRateOracle) = (false, newMarkRateOracle);
        }

        _ctx().fIndexOracle = newFIndexOracle;
        emit OracleAddressesUpdated(newMarkRateOracle, newFIndexOracle);
    }

    function _setGlobalHardOICap(uint128 newHardOICap) internal {
        _ctx().hardOICap = newHardOICap;
        emit OICapUpdated(newHardOICap);
    }

    function _setGlobalFeeRates(uint64 newTakerFee, uint64 newOtcFee) internal {
        _ensureValidFeeRates(newTakerFee, newOtcFee);

        _ctx().takerFee = newTakerFee;
        _ctx().otcFee = newOtcFee;
        emit FeeRatesUpdated(newTakerFee, newOtcFee);
    }

    function _setGlobalLiquidationSettings(LiqSettings memory newLiqSettings) internal {
        require(newLiqSettings.feeRate <= PMath.ONE, Err.InvalidFeeRates());
        _ctx().liqSettings = newLiqSettings;
        emit LiquidationSettingsUpdated(newLiqSettings);
    }

    function _setGlobalMarginConfig(uint64 newKIM, uint64 newKMM, uint32 newTThresh) internal {
        _ctx().kIM = newKIM;
        _ctx().kMM = newKMM;
        _ctx().tThresh = newTThresh;
        emit MarginConfigUpdated(newKIM, newKMM, newTThresh);
    }

    function _setGlobalRateBoundConfig(
        uint16 newMaxRateDeviationFactorBase1e4,
        uint16 newClosingOrderBoundBase1e4
    ) internal {
        _ctx().maxRateDeviationFactorBase1e4 = newMaxRateDeviationFactorBase1e4;
        _ctx().closingOrderBoundBase1e4 = newClosingOrderBoundBase1e4;
        emit RateBoundConfigUpdated(newMaxRateDeviationFactorBase1e4, newClosingOrderBoundBase1e4);
    }

    function _setGlobalLimitOrderConfig(
        int16 loUpperConstBase1e4,
        int16 loUpperSlopeBase1e4,
        int16 loLowerConstBase1e4,
        int16 loLowerSlopeBase1e4
    ) internal {
        _ctx().loUpperConstBase1e4 = loUpperConstBase1e4;
        _ctx().loUpperSlopeBase1e4 = loUpperSlopeBase1e4;
        _ctx().loLowerConstBase1e4 = loLowerConstBase1e4;
        _ctx().loLowerSlopeBase1e4 = loLowerSlopeBase1e4;
        emit LimitOrderConfigUpdated(
            loUpperConstBase1e4,
            loUpperSlopeBase1e4,
            loLowerConstBase1e4,
            loLowerSlopeBase1e4
        );
    }

    function _setGlobalStatus(MarketStatus newStatus) internal {
        _ctx().status = newStatus;
        emit StatusUpdated(newStatus);
    }

    function _ensureValidFIndexOracle(address fIndexOracle_, uint32 maturity) internal view {
        uint32 fIndexOracleMaturity = IFIndexOracle(fIndexOracle_).maturity();
        address fIndexOracleMarket = IFIndexOracle(fIndexOracle_).market();
        require(fIndexOracleMaturity == maturity, Err.MarketInvalidFIndexOracle());
        require(fIndexOracleMarket == address(this), Err.MarketInvalidFIndexOracle());
    }

    function _ensureValidDiscRates(uint64 newTakerDisc, uint64 newOtcDisc) internal pure {
        require(newTakerDisc <= PMath.ONE && newOtcDisc <= PMath.ONE, Err.InvalidFeeRates());
    }

    function _ensureValidFeeRates(uint64 newTakerFee, uint64 newOtcFee) internal pure {
        require(newTakerFee <= PMath.ONE && newOtcFee <= PMath.ONE, Err.InvalidFeeRates());
    }
}
