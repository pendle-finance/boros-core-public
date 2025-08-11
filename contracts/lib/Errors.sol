// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library Err {
    // Market Errors
    error MarketMatured();
    error MarketOICapExceeded();
    error MarketSelfSwap();
    error MarketLiqNotReduceSize();
    error MarketInvalidLiquidation();
    error MarketInvalidDeleverage();
    error MarketOrderNotFound();
    error MarketOrderFOKNotFilled();
    error MarketOrderALOFilled();
    error MarketInvalidFIndexOracle();
    error MarketMaxOrdersExceeded();
    error MarketZeroSize();
    error MarketDuplicateOTC();
    error MarketOrderFilled();
    error MarketOrderCancelled();
    error MarketOrderRateOutOfBound();
    error MarketLastTradedRateTooFar();
    error MarketPaused();
    error MarketCLO();

    // FIndex Errors
    error FIndexUpdatedAtMaturity();
    error FIndexNotDueForUpdate();
    error FIndexInvalidTime();

    // Margin Manager Errors
    error MMMarketNotEntered();
    error MMMarketAlreadyEntered();
    error MMMarketLimitExceeded();
    error MMInsufficientIM();
    error MMMarketExitDenied();
    error MMIsolatedMarketDenied();
    error MMMarketMismatch();
    error MMTokenMismatch();
    error MMTransferDenied();
    error MMSimulationOnly();
    error MMHealthCritical();
    error MMInsufficientMinCash();
    error MMInvalidCritHR();
    error MMHealthNonRisky();

    // Market Hub Errors
    error MHTokenNotExists();
    error MHTokenExists();
    error MHMarketExists();
    error MHTokenLimitExceeded();
    error MHMarketNotExists();
    error MHMarketNotByFactory();
    error MHWithdrawNotReady();
    error MHInvalidLiquidator();

    // AMM Errors
    error AMMWithdrawOnly();
    error AMMCutOffReached();
    error AMMInsufficientLiquidity();
    error AMMInvalidRateRange();
    error AMMSignMismatch();
    error AMMInsufficientCashIn();
    error AMMInvalidParams();
    error AMMInsufficientCashOut();
    error AMMInsufficientLpOut();
    error AMMInsufficientSizeOut();
    error AMMNegativeCash();
    error AMMTotalSupplyCapExceeded();
    error AMMNotFound();

    // Trade Module Errors
    error TradeALOAMMNotAllowed();
    error TradeOnlyMainAccount();
    error TradeOnlyAMMAccount();
    error TradeOnlyForIsolated();
    error TradeUndesiredRate();
    error TradeUndesiredSide();
    error TradeMarketIdMismatch();
    error TradeAMMAlreadySet();

    // General Errors
    error Unauthorized();
    error InvalidLength();
    error InvalidFeeRates();
    error InvalidObservationWindow();
    error InvalidNumTicks();
    error InvalidTokenId();
    error InvalidMaturity();
    error InvalidAMMId();
    error InvalidAMMAcc();
    error SimulationOnly();

    // Math Errors
    error MathOutOfBounds();
    error MathInvalidExponent();

    // AuthModule Errors
    error AuthInvalidMessage();
    error AuthInvalidConnectionId();
    error AuthAgentExpired();
    error AuthInvalidNonce();
    error AuthExpiryInPast();
    error AuthSelectorNotAllowed();

    // Funding Rate Aggregator Errors
    error NotEnoughReports();
    error DuplicateOracleType();
    error FundingTimestampMismatch();
    error FundingRateMismatch();

    // Executors Errors
    error InsufficientProfit();
    error ProfitMismatch();
    error LiquidationAMMNotAllowed();

    // Risk Bots Errors
    error CLOInvalidThreshold();
    error CLOThresholdNotMet();
    error CLOMarketInvalidStatus();
    error DeleveragerDuplicateMarketId();
    error DeleveragerHealthNonRisky();
    error DeleveragerUnsatCondition();
    error DeleveragerWinnerInBadDebt();
    error DeleveragerNonZeroRemainingSize();
    error OrderCancellerDuplicateMarketId();
    error OrderCancellerDuplicateOrderId();
    error OrderCancellerInvalidOrder();
    error OrderCancellerNotRisky();
    error PauserNotRisky();
    error PauserTokenMismatch();
    error WithdrawalPoliceInvalidThreshold();
    error WithdrawalPoliceUnsatCondition();
    error ZoneMarketInvalidStatus();
    error ZoneInvalidGlobalCooldown();
    error ZoneInvalidLiqSettings();
    error ZoneInvalidRateDeviationConfig();
}
