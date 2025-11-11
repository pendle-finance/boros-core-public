// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AMMState} from "../core/amm/PositiveAMMMath.sol";
import {MarketAcc} from "../types/Account.sol";
import {AMMId} from "../types/MarketTypes.sol";

interface IBOROS20 {
    event BOROS20Transfer(MarketAcc from, MarketAcc to, uint256 value);

    error BOROS20NotEnoughBalance(MarketAcc account, uint256 balance, uint256 value);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(MarketAcc account) external view returns (uint256);
}

interface IAMM is IBOROS20 {
    function mintByBorosRouter(
        MarketAcc receiver,
        int256 totalCash,
        int256 totalSize,
        int256 maxCashIn,
        int256 exactSizeIn
    ) external returns (int256 netCashIn, uint256 netLpOut);

    function burnByBorosRouter(
        MarketAcc payer,
        int256 totalCash,
        int256 totalSize,
        uint256 lpToBurn
    ) external returns (int256 netCashOut, int256 netSizeOut, bool isMatured);

    function swapByBorosRouter(int256 sizeOut) external returns (int256 costOut);

    // ---

    function readState() external view returns (AMMState memory);

    function swapView(int256 sizeOut) external view returns (int256 costOut);

    /// @notice Returns largest swappable size to push implied rate towards `targetRate`.
    /// After swap, implied rate may not be equal to `targetRate` (e.g. hit min/max rate).
    /// Returns 0 when AMM is not swappable (e.g. after cutoff, AMM is withdraw-only).
    function calcSwapSize(int256 targetRate) external view returns (int256);

    function impliedRate() external view returns (int256);

    function oracleImpliedRate() external view returns (int128 oracleImpliedRate, uint32 observationWindow);

    function feeRate() external view returns (uint64);

    function totalSupplyCap() external view returns (uint256);

    function ROUTER() external view returns (address);

    function MARKET() external view returns (address);

    function SEED_TIME() external view returns (uint32);

    function AMM_ID() external view returns (AMMId);

    function MATURITY() external view returns (uint32);

    function SELF_ACC() external view returns (MarketAcc);

    function ACCOUNT_ONE() external view returns (MarketAcc);

    function _storage()
        external
        view
        returns (
            uint128 minAbsRate,
            uint128 maxAbsRate,
            uint32 cutOffTimestamp,
            uint32 oracleImpliedRateWindow,
            uint64 feeRate,
            uint256 totalSupplyCap,
            uint128 totalFloatAmount,
            uint128 normFixedAmount,
            uint32 lastTradedTime,
            int128 prevOracleImpliedRate
        );

    // --- Admin functions ---

    function setAMMImpliedRateObservationWindow(uint32 newWindow) external;

    function setAMMFeeRate(uint64 newFeeRate) external;

    function setAMMTotalSupplyCap(uint256 newTotalSupplyCap) external;

    function setAMMConfig(uint128 minAbsRate, uint128 maxAbsRate, uint32 cutOffTimestamp) external;

    // ---

    event Mint(MarketAcc indexed receiver, uint256 netLpMinted, int256 netCashIn, int256 netSizeIn);
    event Burn(MarketAcc indexed payer, uint256 netLpBurned, int256 netCashOut, int256 netSizeOut);
    event Swap(int256 sizeOut, int256 costOut, uint256 fee);

    event ImpliedRateObservationWindowUpdated(uint32 newWindow);
    event FeeRateUpdated(uint256 newFeeRate);
    event TotalSupplyCapUpdated(uint256 newTotalSupplyCap);
    event AMMConfigUpdated(uint128 minAbsRate, uint128 maxAbsRate, uint32 cutOffTimestamp);
}
