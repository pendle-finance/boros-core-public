// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Err} from "../../../lib/Errors.sol";
import {FIndex, FIndexLib} from "../../../types/MarketTypes.sol";
import {IFIndexOracle} from "../../../interfaces/IFIndexOracle.sol";
import {IMarket} from "../../../interfaces/IMarket.sol";
import {PendleRolesPlugin} from "./../../../core/roles/PendleRoles.sol";
import {PaymentLib} from "../../../lib/PaymentLib.sol";
import {PMath} from "../../../lib/math/PMath.sol";

contract FIndexOracle is IFIndexOracle, PendleRolesPlugin {
    using PMath for int256;

    struct FIndexOracleParams {
        // fixed param
        uint32 maturity;
        address market;
        // config
        uint64 settleFeeRate;
        uint32 updatePeriod;
        uint32 maxUpdateDelay;
    }

    FIndexOracleParams internal _params;
    FIndex internal _latestFIndex;
    int256 internal _latestAnnualizedRate;
    address public keeper;

    modifier onlyKeeper() {
        require(msg.sender == keeper, Err.Unauthorized());
        _;
    }

    constructor(
        FIndexOracleParams memory params,
        address permissionController_,
        address keeper_
    ) PendleRolesPlugin(permissionController_) {
        _params = params;

        (uint32 currentEpochStart, ) = _calcEpochRange(params, uint32(block.timestamp));
        _latestFIndex = FIndexLib.from(currentEpochStart, 0, 0);
        _latestAnnualizedRate = 0;
        keeper = keeper_;
    }

    function updateFloatingIndex(int112 floatingIndexDelta, uint32 desiredTimestamp) external onlyKeeper {
        FIndexOracleParams memory params = _params;

        FIndex oldIndex = _latestFIndex;
        uint32 blockTimestamp = uint32(block.timestamp);

        (uint32 lastUpdateTime, uint32 nextUpdateTimestamp) = _calcUpdateTime(params, oldIndex, blockTimestamp);
        require(lastUpdateTime < params.maturity, Err.FIndexUpdatedAtMaturity());
        require(nextUpdateTimestamp <= blockTimestamp, Err.FIndexNotDueForUpdate());
        require(desiredTimestamp == nextUpdateTimestamp, Err.FIndexInvalidTime());

        FIndex newIndex = _calcNewFIndex(params, floatingIndexDelta, oldIndex, nextUpdateTimestamp);
        _latestFIndex = newIndex;
        _latestAnnualizedRate = _calcAnnualizedRateBetween(oldIndex, newIndex);

        IMarket(params.market).updateFIndex(newIndex);
    }

    // View functions

    function isDueForUpdateNow() external view returns (bool) {
        FIndexOracleParams memory params = _params;
        uint32 blockTimestamp = uint32(block.timestamp);
        (uint32 lastUpdateTime, uint32 nextUpdateTimestamp) = _calcUpdateTime(params, _latestFIndex, blockTimestamp);
        return lastUpdateTime < params.maturity && nextUpdateTimestamp <= blockTimestamp;
    }

    function getLatestFIndex() external view returns (FIndex) {
        return _latestFIndex;
    }

    function latestAnnualizedRate() external view returns (int256 rate) {
        return _latestAnnualizedRate;
    }

    function maturity() external view returns (uint32) {
        return _params.maturity;
    }

    function market() external view returns (address) {
        return _params.market;
    }

    function nextFIndexUpdateTime() external view returns (uint32 timestamp) {
        (, timestamp) = _calcUpdateTime(_params, _latestFIndex, uint32(block.timestamp));
    }

    // Config

    function getConfig() external view returns (uint64 settleFeeRate, uint32 updatePeriod, uint32 maxUpdateDelay) {
        return (_params.settleFeeRate, _params.updatePeriod, _params.maxUpdateDelay);
    }

    function setConfig(
        uint64 newSettleFeeRate,
        uint32 newUpdatePeriod,
        uint32 newMaxUpdateDelay
    ) external onlyAuthorized {
        _params.settleFeeRate = newSettleFeeRate;
        _params.updatePeriod = newUpdatePeriod;
        _params.maxUpdateDelay = newMaxUpdateDelay;

        emit ConfigUpdated(newSettleFeeRate, newUpdatePeriod, newMaxUpdateDelay);
    }

    function setKeeper(address newKeeper) external onlyAuthorized {
        keeper = newKeeper;
        emit KeeperUpdated(newKeeper);
    }

    // Calculate functions

    /// epoch endpoints have the form of (maturity - k * period)
    function _calcEpochRange(
        FIndexOracleParams memory params,
        uint32 timestamp
    ) internal pure returns (uint32 start, uint32 stop) {
        uint32 maturity_ = params.maturity;
        uint32 period = params.updatePeriod;
        if (timestamp >= maturity_) return (maturity_, maturity_);

        // find smallest k such that
        //      (maturity - k * period) <= timestamp
        //      maturity - timestamp <= k * period
        //
        //      k = ceil((maturity - timestamp) / period)

        uint32 k = (maturity_ - timestamp + period - 1) / period;
        // slither-disable-next-line divide-before-multiply
        start = params.maturity - k * period;
        stop = start + period;
    }

    function _calcUpdateTime(
        FIndexOracleParams memory params,
        FIndex latestIndex,
        uint32 blockTimestamp
    ) internal pure returns (uint32 lastUpdateTime, uint32 nextUpdateTimestamp) {
        lastUpdateTime = latestIndex.fTime();

        // nextUpdateTimestamp:
        // - must be an epoch endpoint.
        // - must not be before lastUpdateTime
        // - must not be before block.timestamp - maxDelay
        //   (in other words, block.timestamp <= nextUpdateTimestamp + maxDelay)
        (, nextUpdateTimestamp) = _calcEpochRange(
            params,
            _max(lastUpdateTime, _subMax0(blockTimestamp, params.maxUpdateDelay))
        );
    }

    function _calcNewFIndex(
        FIndexOracleParams memory params,
        int112 floatingIndexDelta,
        FIndex oldIndex,
        uint32 timestamp
    ) internal pure returns (FIndex newIndex) {
        // assert(!oldIndex.isZero());
        int112 floatingIndex = floatingIndexDelta + oldIndex.floatingIndex();
        uint64 feeIndex = PaymentLib.calcNewFeeIndex(
            oldIndex.feeIndex(),
            params.settleFeeRate,
            timestamp - oldIndex.fTime()
        );

        newIndex = FIndexLib.from(timestamp, floatingIndex, feeIndex);
    }

    function _calcAnnualizedRateBetween(FIndex oldIndex, FIndex newIndex) internal pure returns (int256 rate) {
        uint256 deltaTime = newIndex.fTime() - oldIndex.fTime();
        int256 deltaIndex = newIndex.floatingIndex() - oldIndex.floatingIndex();
        return (deltaIndex * (365 days)) / int256(deltaTime);
    }

    // Use this instead of PMath so that solidity does not resolve to functions of uint256
    function _max(uint32 lhs, uint32 rhs) internal pure returns (uint32) {
        return (lhs > rhs ? lhs : rhs);
    }

    function _subMax0(uint32 a, uint32 b) internal pure returns (uint32) {
        unchecked {
            return (a >= b ? a - b : 0);
        }
    }
}
