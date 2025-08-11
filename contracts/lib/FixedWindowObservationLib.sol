// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PMath} from "./math/PMath.sol";
import {Err} from "./Errors.sol";

library FixedWindowObservationLib {
    using PMath for *;

    uint32 internal constant _MIN_OBV_WINDOW = 10 seconds;
    uint32 internal constant _MAX_OBV_WINDOW = 1 hours;

    function validateWindow(uint32 window) internal pure {
        require(_MIN_OBV_WINDOW <= window && window <= _MAX_OBV_WINDOW, Err.InvalidObservationWindow());
    }

    /// @notice calculation based on Notional's interest rate oracles: https://docs.notional.finance/governance/fcash-valuation/interest-rate-oracles
    function calcCurrentOracleRate(
        int128 prevOracleRate,
        uint32 window,
        uint32 lastTradedTime,
        int128 lastTradedRate,
        uint32 blockTimestamp
    ) internal pure returns (int128) {
        int256 iWindow = int256(uint256(window));
        int256 timeElapsed = int32(blockTimestamp - lastTradedTime);
        if (timeElapsed == 0) return prevOracleRate;
        if (timeElapsed >= iWindow) {
            return lastTradedRate;
        }
        int256 oracleRate = int256(lastTradedRate) * timeElapsed + int256(prevOracleRate) * (iWindow - timeElapsed);
        oracleRate /= iWindow;
        return oracleRate.Int128();
    }
}
