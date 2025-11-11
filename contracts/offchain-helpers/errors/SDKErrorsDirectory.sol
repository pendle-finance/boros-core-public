// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketAcc} from "../../types/Account.sol";

library SDKErrorsDirectory {
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
    error MulWadFailed();
    error SMulWadFailed();
    error DivWadFailed();
    error SDivWadFailed();
    error DivFailed();
    error Overflow();

    // AuthModule Errors
    error AuthInvalidMessage();
    error AuthInvalidConnectionId();
    error AuthAgentExpired();
    error AuthInvalidNonce();
    error AuthExpiryInPast();
    error AuthSelectorNotAllowed();

    // ConditionalModule Errors
    error ConditionalInvalidAgent();
    error ConditionalInvalidValidator();
    error ConditionalInvalidParams();
    error ConditionalActionExecuted();
    error ConditionalMessageExpired();
    error ConditionalOrderExpired();
    error ConditionalOrderNotReduceOnly();

    // Executors Errors
    error InsufficientProfit();
    error ProfitMismatch();
    error LiquidationAMMNotAllowed();
    error ZeroArbitrageSize();

    // Risk Bots Errors
    error CLOInvalidThreshold();
    error CLOThresholdNotMet();
    error CLOMarketInvalidStatus();
    error DeleveragerAMMNotAllowed();
    error DeleveragerDuplicateMarketId();
    error DeleveragerHealthNonRisky();
    error DeleveragerLoserHealthier();
    error DeleveragerLoserInBadDebt();
    error DeleveragerWinnerInBadDebt();
    error DeleveragerIncomplete();
    error OrderCancellerDuplicateMarketId();
    error OrderCancellerDuplicateOrderId();
    error OrderCancellerInvalidOrder();
    error OrderCancellerNotRisky();
    error PauserNotRisky();
    error PauserTokenMismatch();
    error WithdrawalPoliceAlreadyRestricted();
    error WithdrawalPoliceInvalidCooldown();
    error WithdrawalPoliceInvalidThreshold();
    error WithdrawalPoliceUnsatCondition();
    error ZoneGlobalCooldownAlreadyIncreased();
    error ZoneMarketInvalidStatus();
    error ZoneInvalidGlobalCooldown();
    error ZoneInvalidLiqSettings();
    error ZoneInvalidRateDeviationConfig();

    // BOROS20 Errors
    error BOROS20NotEnoughBalance(MarketAcc account, uint256 balance, uint256 value);

    // ERC20 Errors
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);

    // OpenZeppelin Errors
    error FailedCall();
}
