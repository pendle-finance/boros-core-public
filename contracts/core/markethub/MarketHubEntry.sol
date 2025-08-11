// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// External
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Interfaces
import {IMarket} from "../../interfaces/IMarket.sol";
import {IMarketHubEntryOnly} from "../../interfaces/IMarketHub.sol";

// Libraries
import {Err} from "../../lib/Errors.sol";
import {PMath} from "../../lib/math/PMath.sol";

// Types
import {AccountLib, MarketAcc} from "../../types/Account.sol";
import {
    BulkOrder,
    BulkOrderResult,
    CancelData,
    GetRequest,
    LiqResult,
    LongShort,
    OTCTrade,
    PayFee,
    VMResult,
    MarketId,
    MarketIdLib,
    TokenId,
    UserResult,
    OTCResult
} from "../../types/MarketTypes.sol";
import {Trade} from "../../types/Trade.sol";

// Components
import {MarketHubSetAndView} from "./MarketHubSetAndView.sol";
import {MarginManager} from "./MarginManager.sol";
import {Storage} from "./Storage.sol";

contract MarketHubEntry is IMarketHubEntryOnly, MarketHubSetAndView, MarginManager, Proxy {
    using AccountLib for address;
    using SafeERC20 for IERC20;
    using PMath for uint256;

    address internal immutable _MARKET_HUB_RISK_MANAGEMENT;

    constructor(
        address _permissionController,
        address _marketFactory,
        address _router,
        address _treasury,
        uint256 _maxEnteredMarkets,
        address _marketHubRiskManagement
    ) Storage(_permissionController, _marketFactory, _router, _treasury, _maxEnteredMarkets) {
        _disableInitializers();
        _MARKET_HUB_RISK_MANAGEMENT = _marketHubRiskManagement;
    }

    function _implementation() internal view override returns (address) {
        return _MARKET_HUB_RISK_MANAGEMENT;
    }

    function initialize(uint32 globalCooldown_) external initializer onlyRole(_INITIALIZER_ROLE) {
        __Storage_init(globalCooldown_);
    }

    // ----------------------- MARKET ENTRY/EXIT -----------------------

    function enterMarket(MarketAcc user, MarketId marketId) external onlyRouter {
        _validateMarketEntry(user, marketId);
        uint256 feePaid = _addMarketToUser(user, marketId);
        emit EnterMarket(user, marketId, feePaid);
    }

    function exitMarket(MarketAcc user, MarketId marketId) external onlyRouter {
        _removeFromEnteredMarkets(user, marketId);

        // The removal above acts as valid market check
        address market = _marketIdToAddrRaw(marketId);

        (, PayFee payFee, int256 signedSize, uint256 nOrders) = IMarket(market).settleAndGet(user, GetRequest.ZERO);
        _processPayFee(user, payFee);

        bool positionIsEmpty = signedSize == 0 && nOrders == 0;
        require(positionIsEmpty || _isMarketMatured(market), Err.MMMarketExitDenied());

        emit ExitMarket(user, marketId);
    }

    // ----------------------- DEPOSIT FUNCTIONS -----------------------

    function vaultDeposit(MarketAcc acc, uint256 unscaled) external onlyRouter {
        TokenData memory data = _tokenDataChecked(acc.tokenId());

        IERC20(data.token).safeTransferFrom(msg.sender, address(this), unscaled);
        _topUpWithdrawCash(acc, _toScaled(unscaled, data.scalingFactor), true);

        emit VaultDeposit(acc, unscaled);
    }

    function vaultPayTreasury(address root, TokenId tokenId, uint256 unscaled) external onlyRouter {
        TokenData memory data = _tokenDataChecked(tokenId);
        MarketAcc main = root.toMainCross(tokenId);

        IERC20(data.token).safeTransferFrom(msg.sender, address(this), unscaled);

        uint256 scaled = _toScaled(unscaled, data.scalingFactor);
        _topUpTreasury(tokenId, scaled);
        emit PayTreasury(main, scaled);
    }

    function requestVaultWithdrawal(address root, TokenId tokenId, uint256 unscaled) external onlyRouter {
        TokenData memory data = _tokenDataChecked(tokenId);
        MarketAcc main = root.toMainCross(tokenId);
        Withdrawal memory user = _withdrawal[root][tokenId];

        user.unscaled += unscaled.Uint224();
        user.start = uint32(block.timestamp);

        _topUpWithdrawCash(main, _toScaled(unscaled, data.scalingFactor), false);
        emit VaultWithdrawalRequested(root, tokenId, user.start, user.unscaled);

        _withdrawal[root][tokenId] = user;
    }

    function cancelVaultWithdrawal(address root, TokenId tokenId) external onlyRouter {
        TokenData memory data = _tokenDataChecked(tokenId);
        MarketAcc main = root.toMainCross(tokenId);
        Withdrawal memory user = _withdrawal[root][tokenId];

        _topUpWithdrawCash(main, _toScaled(user.unscaled, data.scalingFactor), true);
        emit VaultWithdrawalCanceled(root, tokenId, user.unscaled);

        user.unscaled = 0;
        _withdrawal[root][tokenId] = user;
    }

    /// @dev allow this to be called by anyone
    function finalizeVaultWithdrawal(address root, TokenId tokenId) external {
        TokenData memory data = _tokenDataChecked(tokenId);
        Withdrawal memory user = _withdrawal[root][tokenId];

        require(uint256(user.start) + uint256(_getPersonalCooldown(root)) <= block.timestamp, Err.MHWithdrawNotReady());

        uint256 outAmount = user.unscaled;
        user.unscaled = 0;
        _withdrawal[root][tokenId] = user;

        IERC20(data.token).safeTransfer(root, outAmount);
        emit VaultWithdrawalFinalized(root, tokenId, outAmount);
    }

    function cashTransfer(MarketAcc from, MarketAcc to, int256 amount) public onlyRouter {
        require(from != to && from.tokenId() == to.tokenId(), Err.MMTransferDenied());

        _transferCashAndCheck(from, to, amount);
        emit CashTransfer(from, to, amount);
    }

    function cashTransferAll(MarketAcc from, MarketAcc to) external onlyRouter returns (int256 amountOut) {
        amountOut = acc[from].cash;
        cashTransfer(from, to, amountOut);
    }

    function payTreasury(MarketAcc user, uint256 amount) external onlyRouter {
        TokenId tokenId = user.tokenId();
        require(_isValidTokenId(tokenId), Err.MHTokenNotExists());

        _transferToTreasury(user, amount);

        emit PayTreasury(user, amount);
    }

    // ----------------------- SIMULATION -----------------------

    function simulateTransfer(MarketAcc user, int256 amount) external {
        require(tx.origin == address(0), Err.MMSimulationOnly());
        acc[user].cash += amount;
    }

    // ----------------------- MARKET OPERATIONS -----------------------

    function orderAndOtc(
        MarketId marketId,
        MarketAcc mainUser,
        LongShort memory orders,
        CancelData memory cancelData,
        OTCTrade[] memory OTCs
    ) external onlyRouter returns (Trade /*bookMatched*/, uint256 /*totalTakerOtcFee*/) {
        bool checkCritHealthUser = _checkEnteredMarketsAndStrictHealth(mainUser, marketId);
        bool[] memory checkCritHealthOTCs = new bool[](OTCs.length);
        for (uint256 i = 0; i < OTCs.length; i++) {
            checkCritHealthOTCs[i] = _checkEnteredMarketsAndStrictHealth(OTCs[i].counter, marketId);
        }

        address market = _marketIdToAddrRaw(marketId);
        (UserResult memory userRes, OTCResult[] memory otcRes) = IMarket(market).orderAndOtc(
            mainUser,
            orders,
            cancelData,
            OTCs,
            critHR
        );

        _processPayFee(mainUser, userRes.settle + userRes.payment);
        if (!userRes.partialMaker.isZero()) {
            _processPayFee(userRes.partialMaker, userRes.partialPayFee);
        }
        for (uint256 i = 0; i < OTCs.length; i++) {
            _processPayFee(OTCs[i].counter, otcRes[i].settle + otcRes[i].payment);
        }

        _processMarginCheck(mainUser, marketId, userRes.isStrictIM, checkCritHealthUser, userRes.finalVM);
        for (uint256 i = 0; i < OTCs.length; i++) {
            _processMarginCheck(
                OTCs[i].counter,
                marketId,
                otcRes[i].isStrictIM,
                checkCritHealthOTCs[i],
                otcRes[i].finalVM
            );
        }

        return (userRes.bookMatched, userRes.payment.fee());
    }

    function bulkOrders(
        MarketAcc user,
        BulkOrder[] memory bulks
    ) external onlyRouter returns (BulkOrderResult[] memory results) {
        bool isStrictIM = false;
        bool isCritHealth = _checkEnteredMarketsAndStrictHealth(user, bulks);

        results = new BulkOrderResult[](bulks.length);

        int256 localCritHR = critHR; // avoid repeating storage read
        OTCTrade[] memory emptyOTCs;
        for (uint256 i = 0; i < bulks.length; ++i) {
            address market = _marketIdToAddrRaw(bulks[i].marketId);
            (UserResult memory res, ) = IMarket(market).orderAndOtc(
                user,
                bulks[i].orders,
                bulks[i].cancelData,
                emptyOTCs,
                localCritHR
            );

            _processPayFee(user, res.settle + res.payment);
            if (!res.partialMaker.isZero()) {
                _processPayFee(res.partialMaker, res.partialPayFee);
            }

            if (res.isStrictIM) {
                isStrictIM = true;
            }

            results[i].matched = res.bookMatched;
            results[i].takerFee = res.payment.fee();
        }

        _processMarginCheck(user, isStrictIM, isCritHealth);
    }

    function cancel(MarketId marketId, MarketAcc user, CancelData memory cancelData) external onlyRouter {
        _checkEnteredMarkets(user, marketId);
        address market = _marketIdToAddrRaw(marketId);
        (PayFee payFee, ) = IMarket(market).cancel(user, cancelData, false);
        _processPayFee(user, payFee);
    }

    function liquidate(
        MarketId marketId,
        MarketAcc liq,
        MarketAcc vio,
        int256 sizeToLiq
    ) external onlyAuthorized returns (Trade /*liqTrade*/, uint256 /*liqFee*/) {
        require(liq.root() == msg.sender, Err.MHInvalidLiquidator());

        bool checkCritHealthLiq = _checkEnteredMarketsAndStrictHealth(liq, marketId);
        _checkEnteredMarkets(vio, marketId);

        int256 vioHealthRatio = _settleProcessGetHR(vio);

        address market = _marketIdToAddrRaw(marketId);
        LiqResult memory res = IMarket(market).liquidate(liq, vio, sizeToLiq, vioHealthRatio, critHR);

        _processPayFee(liq, res.liqSettle + res.liqPayment);
        _processPayFee(vio, res.vioSettle + res.vioPayment);

        _processMarginCheck(liq, marketId, res.isStrictIMLiq, checkCritHealthLiq, res.finalVMLiq);

        return (res.liqTrade, res.liqPayment.fee());
    }

    /// @dev allow this to be called by anyone
    function settleAllAndGet(
        MarketAcc user,
        GetRequest req,
        MarketId idToGetSize
    ) external returns (int256 /*cash*/, VMResult /*totalVM*/, int256 /*signedSize*/) {
        return _settleProcess(user, req, MarketIdLib.ZERO, idToGetSize);
    }

    // slither-disable-next-line locked-ether
    receive() external payable {
        revert();
    }
}
