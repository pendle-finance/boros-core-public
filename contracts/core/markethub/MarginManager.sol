// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Interfaces
import {IMarket} from "../../interfaces/IMarket.sol";

// Libraries
import {Err} from "../../lib/Errors.sol";
import {PMath} from "../../lib/math/PMath.sol";

// Types
import {MarketAcc} from "../../types/Account.sol";
import {GetRequest, PayFee, TokenId, MarketId, MarketIdLib, VMResult} from "../../types/MarketTypes.sol";

// Components
import {Storage} from "./Storage.sol";

abstract contract MarginManager is Storage {
    using PMath for int256;
    using PMath for uint256;

    // ----------------------- INTERNAL FUNCTIONS -----------------------
    function _validateMarketEntry(MarketAcc user, MarketId marketId) internal view {
        address market = _marketIdToAddrChecked(marketId);

        (bool marketIsIsolatedOnly, TokenId tokenId, , uint32 maturity, , , uint32 latestFTime) = IMarket(market)
            .descriptor();

        require(latestFTime < maturity, Err.MarketMatured());
        require(user.tokenId() == tokenId, Err.MMTokenMismatch());

        if (user.marketId().isCross()) {
            require(!marketIsIsolatedOnly, Err.MMIsolatedMarketDenied());
        } else {
            require(user.marketId() == marketId, Err.MMMarketMismatch());
        }

        if (acc[user].enteredMarkets.length == 0) {
            // validate minCash only if the user hasn't entered any market before
            uint128 minCash = user.isCross() ? cashFeeData[tokenId].minCashCross : cashFeeData[tokenId].minCashIsolated;
            require(acc[user].cash >= int256(uint256(minCash)), Err.MMInsufficientMinCash());
        }
    }

    function _addMarketToUser(MarketAcc user, MarketId marketId) internal returns (uint128 entranceFee) {
        if (!acc[user].hasEnteredMarketBefore[marketId]) {
            acc[user].hasEnteredMarketBefore[marketId] = true;
            entranceFee = cashFeeData[user.tokenId()].marketEntranceFee;

            _transferToTreasury(user, entranceFee);
        }

        _addToEnteredMarkets(user, marketId);
        require(acc[user].enteredMarkets.length <= MAX_ENTERED_MARKETS, Err.MMMarketLimitExceeded());
    }

    function _topUpWithdrawCash(MarketAcc payer, uint256 scaled, bool isDeposit) internal {
        if (isDeposit) {
            acc[payer].cash += scaled.Int();
        } else {
            acc[payer].cash -= scaled.Int();
            _checkIMStrict(payer);
        }
    }

    function _topUpTreasury(TokenId tokenId, uint256 scaled) internal {
        cashFeeData[tokenId].treasuryCash += scaled.Uint128();
    }

    function _transferToTreasury(MarketAcc payer, uint256 scaled) internal {
        acc[payer].cash -= scaled.Int();
        _checkIMStrict(payer);

        cashFeeData[payer.tokenId()].treasuryCash += scaled.Uint128();
    }

    function _transferCashAndCheck(MarketAcc payer, MarketAcc receiver, int256 scaled) internal {
        acc[payer].cash -= scaled;
        acc[receiver].cash += scaled;
        _checkIMStrict(scaled > 0 ? payer : receiver);
    }

    function _processPayFee(MarketAcc user, PayFee payFee) internal {
        (int128 payment, uint128 fees) = payFee.unpack();
        if (payment != 0 || fees != 0) {
            acc[user].cash += payment - uint256(fees).Int();
        }
        if (fees != 0) {
            cashFeeData[user.tokenId()].treasuryCash += fees;
        }
    }

    function _isMarketMatured(address market) internal view returns (bool) {
        (, , , uint32 maturity, , , uint32 latestFTime) = IMarket(market).descriptor();
        return latestFTime >= maturity;
    }

    // ----------------------- SETTLEMENT & MARGIN CHECK -----------------------

    function _processMarginCheck(MarketAcc user, bool isStrictIM, bool isCritHealth) internal {
        if (isStrictIM) {
            _checkIMStrict(user);
        } else if (isCritHealth) {
            _checkCritHealth(user);
        }
    }

    function _processMarginCheck(
        MarketAcc user,
        MarketId marketId,
        bool isStrictIM,
        bool isCritHealth,
        VMResult finalVM
    ) internal {
        if (isStrictIM) {
            _checkIMStrict(user, marketId, finalVM);
        } else if (isCritHealth) {
            _checkCritHealth(user, marketId, finalVM);
        }
    }

    function _checkIMStrict(MarketAcc user) internal {
        (int256 cash, VMResult totalIM) = _settleExcept(user, GetRequest.IM, MarketIdLib.ZERO);
        require(_isEnoughIMStrict(totalIM, cash), Err.MMInsufficientIM());
    }

    function _checkIMStrict(MarketAcc user, MarketId idToSkip, VMResult IMOfSkip) internal {
        (int256 cash, VMResult totalIM) = _settleExcept(user, GetRequest.IM, idToSkip);
        require(_isEnoughIMStrict(totalIM + IMOfSkip, cash), Err.MMInsufficientIM());
    }

    function _checkCritHealth(MarketAcc user) internal {
        (int256 cash, VMResult totalMM) = _settleExcept(user, GetRequest.MM, MarketIdLib.ZERO);
        require(_isHRAboveThres(totalMM, cash, critHR), Err.MMHealthCritical());
    }

    function _checkCritHealth(MarketAcc user, MarketId idToSkip, VMResult MMOfSkip) internal {
        (int256 cash, VMResult totalMM) = _settleExcept(user, GetRequest.MM, idToSkip);
        require(_isHRAboveThres(totalMM + MMOfSkip, cash, critHR), Err.MMHealthCritical());
    }

    function _isEnoughIMStrict(VMResult totalIM, int256 cash) internal pure returns (bool) {
        (int256 totalValue, uint256 totalMargin) = totalIM.unpack();
        return totalValue + cash >= totalMargin.Int();
    }

    function _isHRAboveThres(VMResult totalMM, int256 cash, int256 thres) internal pure returns (bool) {
        // We avoid using _calcHR when totalMargin is 0 (i.e. user has no position) to prevent division by zero
        // Instead, we check if totalValue + cash >= totalMargin * thres
        // When totalMargin is 0, this simplifies to checking if the user has non-negative net value
        (int256 totalValue, uint256 totalMargin) = totalMM.unpack();
        return totalValue + cash >= totalMargin.Int().mulCeil(thres);
    }

    function _calcHR(VMResult totalMM, int256 cash) internal pure returns (int256) {
        (int256 totalValue, uint256 totalMargin) = totalMM.unpack();
        return (totalValue + cash).divDown(totalMargin.Int());
    }

    // ----------------------- SETTLEMENT -----------------------

    function _settleProcessGetTotalValue(MarketAcc user) internal returns (int256) {
        (int256 cash, VMResult totalMM) = _settleExcept(user, GetRequest.MM, MarketIdLib.ZERO);
        (int256 value, ) = totalMM.unpack();
        return value + cash;
    }

    function _settleProcessGetHR(MarketAcc user) internal returns (int256) {
        (int256 cash, VMResult totalMM) = _settleExcept(user, GetRequest.MM, MarketIdLib.ZERO);
        return _calcHR(totalMM, cash);
    }

    function _settleProcessCheckHRAboveThres(MarketAcc user, int256 thres) internal returns (bool) {
        (int256 cash, VMResult totalMM) = _settleExcept(user, GetRequest.MM, MarketIdLib.ZERO);
        return _isHRAboveThres(totalMM, cash, thres);
    }

    function _settleExcept(
        MarketAcc user,
        GetRequest req,
        MarketId idToSkip
    ) internal returns (int256 cash, VMResult totalVM) {
        (cash, totalVM, ) = _settleProcess(user, req, idToSkip, MarketIdLib.ZERO);
    }

    function _settleProcess(
        MarketAcc user,
        GetRequest req,
        MarketId idToSkip,
        MarketId idToGetSize
    ) internal returns (int256 cash, VMResult totalVM, int256 signedSizeOfMarket) {
        PayFee totalPayFee;
        MarketId[] memory marketIds = acc[user].enteredMarkets;

        for (uint256 i = 0; i < marketIds.length; i++) {
            if (marketIds[i] == idToSkip) continue;

            address market = _marketIdToAddrRaw(marketIds[i]);

            (VMResult thisVM, PayFee thisPayFee, int256 thisSignedSize,  /*uint256 nOrders*/) = IMarket(market)
                .settleAndGet(user, req);

            if (req != GetRequest.ZERO) {
                totalVM = totalVM + thisVM;
            }
            if (marketIds[i] == idToGetSize) {
                signedSizeOfMarket = thisSignedSize;
            }

            totalPayFee = totalPayFee + thisPayFee;
        }

        _processPayFee(user, totalPayFee);
        cash = acc[user].cash;
    }
}
