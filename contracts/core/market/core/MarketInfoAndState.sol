// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// External
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Generated
import {GeneratedStorageSlots} from "../../../generated/slots.sol";

// Interfaces
import {IMarketAllEventsAndTypes} from "../../../interfaces/IMarket.sol";

// Libraries
import {Err} from "../../../lib/Errors.sol";
import {PMath} from "../../../lib/math/PMath.sol";

// Types
import {MarketAcc} from "../../../types/Account.sol";
import {FIndex, FTag, OTCTrade} from "../../../types/MarketTypes.sol";

abstract contract MarketInfoAndState is IMarketAllEventsAndTypes, Initializable {
    using PMath for uint256;

    bool internal constant YES = true;
    bool internal constant NO = false;

    address internal immutable _MARKET_HUB;

    modifier onlyMarketHub() {
        require(msg.sender == _MARKET_HUB, Err.Unauthorized());
        _;
    }

    constructor(address marketHub_) {
        _MARKET_HUB = marketHub_;
    }

    function _ctx() internal pure returns (MarketCtx storage $) {
        bytes32 slot = GeneratedStorageSlots.MARKET_CTX_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    function _accStateMap() internal pure returns (mapping(MarketAcc => AccountState) storage $) {
        bytes32 slot = GeneratedStorageSlots.MARKET_ACC_STATE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    function _accState(MarketAcc acc) internal view returns (AccountState storage) {
        return _accStateMap()[acc];
    }

    function _incDelevLiqNonce(MarketAcc user) internal {
        _accState(user).delevLiqNonce++;
    }

    function _kIM(MarketAcc user) internal view returns (uint64) {
        uint64 kIMAcc = _accState(user).kIM;
        return kIMAcc != 0 ? kIMAcc : _ctx().kIM;
    }

    function _kMM(MarketAcc user) internal view returns (uint64) {
        uint64 kMMAcc = _accState(user).kMM;
        return kMMAcc != 0 ? kMMAcc : _ctx().kMM;
    }

    function _isMatured(MarketMem memory market) internal pure returns (bool) {
        return market.latestFTime >= market.k_maturity;
    }

    function _toFIndex(FTag fTag) internal view returns (FIndex) {
        return _ctx().fTagToIndex[fTag];
    }

    function _getTakerFeeRate(MarketAcc addr) internal view returns (uint256) {
        return uint256(_ctx().takerFee).tweakDown(uint256(_accState(addr).takerDisc));
    }

    function _getOtcFeeRate(MarketAcc addr1, MarketAcc addr2) internal view returns (uint256) {
        uint256 mainUserDisc = _accState(addr1).otcDisc;
        uint256 counterDisc = _accState(addr2).otcDisc;
        return uint256(_ctx().otcFee).tweakDown(mainUserDisc.max(counterDisc));
    }

    function _getOtcFeeRates(MarketAcc user, OTCTrade[] memory OTCs) internal view returns (uint256[] memory fees) {
        uint256 origFee = _ctx().otcFee;
        uint256 userDisc = _accState(user).otcDisc;

        fees = new uint256[](OTCs.length);

        for (uint256 i = 0; i < OTCs.length; i++) {
            uint256 counterDisc = _accState(OTCs[i].counter).otcDisc;
            fees[i] = origFee.tweakDown(userDisc.max(counterDisc));
        }
    }

    function _updateFIndex(FIndex newIndex) internal {
        FIndex fIndex = _toFIndex(_ctx().latestFTag);
        assert(newIndex.fTime() > fIndex.fTime());

        FTag newFTag = _ctx().latestFTag.nextFIndexUpdateTag();
        _ctx().latestFTag = newFTag;
        _ctx().latestFTime = newIndex.fTime();
        _ctx().fTagToIndex[newFTag] = newIndex;

        emit FIndexUpdated(newIndex, newFTag);
    }

    function _updateFTagOnPurge(FTag latestPurgeTag, FIndex latestIndex) internal {
        FTag latestFIndexUpdateTag = latestPurgeTag.nextFIndexUpdateTag();

        // We have to set latestFTag to be fIndexUpdate since it will be used to set on newly filled orders.
        // Hence, we need to set data for the latestPurgeTag, then latestFIndexUpdateTag.
        _ctx().fTagToIndex[latestPurgeTag] = latestIndex;
        _ctx().fTagToIndex[latestFIndexUpdateTag] = latestIndex;
        _ctx().latestFTag = latestFIndexUpdateTag;
        // latestFTime remains the same, we don't need to update it

        emit FTagUpdatedOnPurge(latestIndex, latestFIndexUpdateTag);
    }
}
