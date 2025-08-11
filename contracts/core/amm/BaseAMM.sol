// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IAMM} from "./../../interfaces/IAMM.sol";
import {AMMCreateParams} from "./../../interfaces/IAMMFactory.sol";
import {IMarket} from "./../../interfaces/IMarket.sol";
import {Err} from "./../../lib/Errors.sol";
import {PMath} from "./../../lib/math/PMath.sol";
import {MarketAcc, AccountLib} from "./../../types/Account.sol";
import {AMMId, MarketId, TokenId} from "./../../types/MarketTypes.sol";
import {FixedWindowObservationLib} from "./../../lib/FixedWindowObservationLib.sol";
import {PendleRolesPlugin} from "./../../core/roles/PendleRoles.sol";
import {BOROS20} from "./BOROS20.sol";
import {AMMState, PositiveAMMMath} from "./PositiveAMMMath.sol";

abstract contract BaseAMM is IAMM, BOROS20, PendleRolesPlugin {
    using PMath for int256;
    using PMath for uint256;
    using AccountLib for address;

    address public immutable ROUTER;
    address public immutable MARKET;

    uint32 public immutable SEED_TIME;
    uint32 public immutable MATURITY;

    MarketAcc public immutable SELF_ACC;
    MarketAcc public immutable ACCOUNT_ONE;
    AMMId public immutable AMM_ID;

    struct AMMStorage {
        // amm config
        uint128 minAbsRate;
        uint128 maxAbsRate;
        uint32 cutOffTimestamp;
        // misc config
        uint32 oracleImpliedRateWindow;
        uint64 feeRate;
        uint256 totalSupplyCap;
        // amm state
        uint128 totalFloatAmount;
        uint128 normFixedAmount;
        // oracle state
        uint32 lastTradedTime;
        int128 prevOracleImpliedRate;
    }

    AMMStorage public _storage;

    uint256 private constant _MINIMUM_LIQUIDITY = 10 ** 6;

    modifier onlyRouterWithOracleUpdate() {
        require(msg.sender == ROUTER, Err.Unauthorized());
        _updateOracle();
        _;
    }

    modifier notWithdrawOnly() {
        require(_isSizeInSync(), Err.AMMWithdrawOnly());
        _;
    }

    modifier notCutOff() {
        uint32 cutOffTimestamp = _storage.cutOffTimestamp;
        if (cutOffTimestamp <= block.timestamp) {
            require(IMarket(MARKET).getLatestFTime() < cutOffTimestamp, Err.AMMCutOffReached());
        }
        _;
    }

    constructor(
        AMMCreateParams memory params,
        AMMState memory initialState
    ) BOROS20(params.name, params.symbol) PendleRolesPlugin(params.permissionController) {
        ROUTER = params.router;
        MARKET = params.market;
        SEED_TIME = initialState.seedTime.Uint32();
        MATURITY = initialState.maturity.Uint32();
        AMM_ID = params.ammId;

        (, TokenId tokenId, MarketId marketId, , , , ) = IMarket(MARKET).descriptor();
        SELF_ACC = address(this).toAmmAcc(tokenId, marketId);

        ACCOUNT_ONE = address(1).toAmmAcc(tokenId, marketId); // anything goes, only to contain some position

        _setAMMConfig(
            initialState.minAbsRate.Uint128(),
            initialState.maxAbsRate.Uint128(),
            initialState.cutOffTimestamp.Uint32()
        );
        _setAMMImpliedRateObservationWindow(params.oracleImpliedRateWindow);
        _setAMMTotalSupplyCap(params.totalSupplyCap);
        _setAMMFeeRate(params.feeRate);

        _writeState(initialState);

        _mint(params.seeder, initialState.totalLp - _MINIMUM_LIQUIDITY);
        _mint(ACCOUNT_ONE, _MINIMUM_LIQUIDITY);
        require(totalSupply() <= _storage.totalSupplyCap, Err.AMMTotalSupplyCapExceeded());

        // lastTradedTime is initialized to 0 so that the initial oracle
        // implied rate will be equal to the initial implied rate
        // _lastTradedTime = 0;
    }

    function mintByBorosRouter(
        MarketAcc receiver,
        int256 totalCash,
        int256 totalSize,
        int256 maxCashIn,
        int256 exactSizeIn
    ) external onlyRouterWithOracleUpdate notWithdrawOnly returns (int256 netCashIn, uint256 netLpOut) {
        require(totalCash > 0, Err.AMMNegativeCash()); // disable adding liquidity when net cash is negative

        (netCashIn, netLpOut) = _mint(totalCash, totalSize, maxCashIn, exactSizeIn);
        _mint(receiver, netLpOut);
        require(totalSupply() <= _storage.totalSupplyCap, Err.AMMTotalSupplyCapExceeded());
        emit Mint(receiver, netLpOut, netCashIn, exactSizeIn);
    }

    function burnByBorosRouter(
        MarketAcc payer,
        int256 totalCash,
        int256 totalSize,
        uint256 lpToBurn
    ) external onlyRouterWithOracleUpdate returns (int256 netCashOut, int256 netSizeOut, bool isMatured) {
        (netCashOut, netSizeOut, isMatured) = _burn(totalCash, totalSize, lpToBurn);
        _burn(payer, lpToBurn);
        emit Burn(payer, lpToBurn, netCashOut, netSizeOut);
    }

    function swapByBorosRouter(
        int256 sizeOut
    ) external onlyRouterWithOracleUpdate notWithdrawOnly returns (int256 costOut) {
        uint256 fee;
        (costOut, fee) = _applyFee(sizeOut, _swap(sizeOut));
        emit Swap(sizeOut, costOut, fee);
    }

    function readState() external view returns (AMMState memory) {
        return _readState();
    }

    function swapView(int256 sizeOut) external view returns (int256 costOut) {
        (costOut, ) = _applyFee(sizeOut, _swapView(sizeOut));
    }

    function calcSwapSize(int256 targetRate) external view returns (int256) {
        return _calcSwapSize(targetRate);
    }

    function impliedRate() external view notCutOff returns (int256) {
        return _calcImpliedRate();
    }

    function oracleImpliedRate()
        external
        view
        notCutOff
        returns (int128 /*_oracleImpliedRate*/, uint32 /*_observationWindow*/)
    {
        return _calcOracleImpliedRateInternal(uint32(block.timestamp));
    }

    function feeRate() external view returns (uint64) {
        return _storage.feeRate;
    }

    function totalSupplyCap() external view returns (uint256) {
        return _storage.totalSupplyCap;
    }

    // --- Admin functions ---

    function setAMMImpliedRateObservationWindow(uint32 newWindow) external onlyAuthorized {
        _setAMMImpliedRateObservationWindow(newWindow);
    }

    function setAMMFeeRate(uint64 newFeeRate) external onlyAuthorized {
        _setAMMFeeRate(newFeeRate);
    }

    function setAMMTotalSupplyCap(uint256 newTotalSupplyCap) external onlyAuthorized {
        _setAMMTotalSupplyCap(newTotalSupplyCap);
    }

    function setAMMConfig(uint128 minAbsRate, uint128 maxAbsRate, uint32 cutOffTimestamp) external onlyAuthorized {
        _setAMMConfig(minAbsRate, maxAbsRate, cutOffTimestamp);
    }

    // --- internal functions --

    function _isSizeInSync() internal view returns (bool) {
        return IMarket(MARKET).getDelevLiqNonce(SELF_ACC) == 0;
    }

    function _applyFee(int256 sizeOut, int256 costOut) internal view returns (int256 newCost, uint256 fee) {
        fee = sizeOut.abs().mulUp(_storage.feeRate);
        newCost = costOut + fee.Int();
    }

    function _updateOracle() private {
        uint32 blockTimestamp = block.timestamp.Uint32();
        (_storage.prevOracleImpliedRate, ) = _calcOracleImpliedRateInternal(blockTimestamp);
        _storage.lastTradedTime = blockTimestamp;
    }

    function _calcOracleImpliedRateInternal(
        uint32 blockTimestamp
    ) internal view returns (int128 _oracleImpliedRate, uint32 _observationWindow) {
        int128 _prevOracleImpliedRate = _storage.prevOracleImpliedRate;
        uint32 _lastTradedTime = _storage.lastTradedTime;
        int128 _lastTradedRate = _calcImpliedRate().Int128();

        _observationWindow = _storage.oracleImpliedRateWindow;

        _oracleImpliedRate = FixedWindowObservationLib.calcCurrentOracleRate(
            _prevOracleImpliedRate,
            _observationWindow,
            _lastTradedTime,
            _lastTradedRate,
            blockTimestamp
        );
    }

    function _setAMMImpliedRateObservationWindow(uint32 newWindow) private {
        FixedWindowObservationLib.validateWindow(newWindow);
        _storage.oracleImpliedRateWindow = newWindow;
        emit ImpliedRateObservationWindowUpdated(newWindow);
    }

    function _setAMMFeeRate(uint64 newFeeRate) private {
        require(newFeeRate <= PMath.ONE, Err.InvalidFeeRates());
        _storage.feeRate = newFeeRate;
        emit FeeRateUpdated(newFeeRate);
    }

    function _setAMMTotalSupplyCap(uint256 newTotalSupplyCap) private {
        _storage.totalSupplyCap = newTotalSupplyCap;
        emit TotalSupplyCapUpdated(newTotalSupplyCap);
    }

    function _setAMMConfig(uint128 minAbsRate, uint128 maxAbsRate, uint32 cutOffTimestamp) private {
        (uint256 adjustedMinAbsRate, uint256 adjustedMaxAbsRate) = PositiveAMMMath.tweakRate(minAbsRate, maxAbsRate);
        require(cutOffTimestamp <= MATURITY, Err.AMMCutOffReached());
        require(0 < adjustedMinAbsRate && adjustedMinAbsRate < adjustedMaxAbsRate, Err.AMMInvalidRateRange());

        _storage.minAbsRate = minAbsRate;
        _storage.maxAbsRate = maxAbsRate;
        _storage.cutOffTimestamp = cutOffTimestamp;

        emit AMMConfigUpdated(minAbsRate, maxAbsRate, cutOffTimestamp);
    }

    function _readState() internal view returns (AMMState memory) {
        return
            AMMState({
                totalFloatAmount: _storage.totalFloatAmount,
                normFixedAmount: _storage.normFixedAmount,
                totalLp: totalSupply(),
                latestFTime: IMarket(MARKET).getLatestFTime(),
                maturity: MATURITY,
                seedTime: SEED_TIME,
                minAbsRate: _storage.minAbsRate,
                maxAbsRate: _storage.maxAbsRate,
                cutOffTimestamp: _storage.cutOffTimestamp
            });
    }

    function _writeState(AMMState memory state) internal {
        _storage.totalFloatAmount = state.totalFloatAmount.Uint128();
        _storage.normFixedAmount = state.normFixedAmount.Uint128();
    }

    // --- virtual functions --

    function _mint(
        int256 totalCash,
        int256 totalSize,
        int256 maxCashIn,
        int256 exactSizeIn
    ) internal virtual returns (int256 netCashIn, uint256 netLpOut);

    function _burn(
        int256 totalCash,
        int256 totalSize,
        uint256 lpToBurn
    ) internal virtual returns (int256 netCashOut, int256 netSizeOut, bool isMatured);

    function _swap(int256 sizeOut) internal virtual returns (int256 costOut);

    function _swapView(int256 sizeOut) internal view virtual returns (int256 costOut);

    function _calcSwapSize(int256 targetRate) internal view virtual returns (int256);

    function _calcImpliedRate() internal view virtual returns (int256);
}
