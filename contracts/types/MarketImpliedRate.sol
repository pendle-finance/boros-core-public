// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Err} from "../lib/Errors.sol";
import {TickMath} from "../lib/math/TickMath.sol";
import {FixedWindowObservationLib} from "../lib/FixedWindowObservationLib.sol";

type MarketImpliedRate is uint208;

using MarketImpliedRateLib for MarketImpliedRate global;

library MarketImpliedRateLib {
    struct InitStruct {
        int16 seedTradedTick;
        uint32 window;
    }

    function initialize(InitStruct memory initStruct) internal view returns (MarketImpliedRate) {
        return from(0, initStruct.window, uint32(block.timestamp), initStruct.seedTradedTick);
    }

    function from(
        int128 _prevOracleRate,
        uint32 _window,
        uint32 _lastTradedTime,
        int16 _lastTradedTick
    ) internal pure returns (MarketImpliedRate) {
        require(_window > 0, Err.InvalidObservationWindow());
        uint208 packed = 0;
        packed = uint208(uint128(_prevOracleRate));
        packed = (packed << 32) | _window;
        packed = (packed << 32) | _lastTradedTime;
        packed = (packed << 16) | uint16(_lastTradedTick);
        return MarketImpliedRate.wrap(packed);
    }

    function unpack(
        MarketImpliedRate data
    ) internal pure returns (int128 _prevOracleRate, uint32 _window, uint32 _lastTradedTime, int16 _lastTradedTick) {
        uint256 packed = MarketImpliedRate.unwrap(data);

        _lastTradedTick = int16(uint16(packed));
        packed >>= 16;

        _lastTradedTime = uint32(packed);
        packed >>= 32;

        _window = uint32(packed);
        packed >>= 32;

        _prevOracleRate = int128(uint128(packed));
    }

    function getCurrentRate(
        MarketImpliedRate self,
        uint8 tickStep
    ) internal view returns (int128 lastTradedRate, int128 oracleRate, uint32 _lastTradedTime, uint32 _window) {
        uint32 blockTimestamp = uint32(block.timestamp);
        (_window, _lastTradedTime, lastTradedRate, oracleRate) = self._calcOracleImpliedRate(blockTimestamp, tickStep);
    }

    function update(
        MarketImpliedRate self,
        uint32 blockTimestamp,
        int16 newTradedTick,
        uint8 tickStep
    ) internal pure returns (MarketImpliedRate) {
        (uint32 _window, , , int128 currentOracleRate) = self._calcOracleImpliedRate(blockTimestamp, tickStep);
        return from(currentOracleRate, _window, blockTimestamp, newTradedTick);
    }

    function replaceWindow(MarketImpliedRate self, uint32 newWindow) internal pure returns (MarketImpliedRate) {
        (int128 _prevOracleRate, , uint32 _lastTradedTime, int16 _lastTradedTick) = self.unpack();
        return from(_prevOracleRate, newWindow, _lastTradedTime, _lastTradedTick);
    }

    function _calcOracleImpliedRate(
        MarketImpliedRate self,
        uint32 blockTimestamp,
        uint8 tickStep
    )
        internal
        pure
        returns (
            // unpacked data
            uint32 _window,
            uint32 _lastTradedTime,
            // calculated data
            int128 _lastTradedRate,
            int128 oracleRate
        )
    {
        int128 _prevOracleRate;
        int16 _lastTradedTick;
        (_prevOracleRate, _window, _lastTradedTime, _lastTradedTick) = self.unpack();
        _lastTradedRate = TickMath.getRateAtTick(_lastTradedTick, tickStep);
        oracleRate = FixedWindowObservationLib.calcCurrentOracleRate(
            _prevOracleRate,
            _window,
            _lastTradedTime,
            _lastTradedRate,
            blockTimestamp
        );
    }
}
