// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MarketAcc} from "../types/Account.sol";
import {AMMSeedParams} from "../core/amm/PositiveAMMMath.sol";
import {AMMId} from "../types/MarketTypes.sol";

struct AMMCreateParams {
    AMMId ammId;
    string name;
    string symbol;
    address router;
    address market;
    uint32 oracleImpliedRateWindow;
    uint64 feeRate;
    uint256 totalSupplyCap;
    MarketAcc seeder;
    address permissionController;
}

interface IAMMFactory {
    event AMMCreated(address amm, bool isPositive, AMMCreateParams createParams, AMMSeedParams seedParams);

    function create(
        bool isPositive,
        AMMCreateParams memory createParams,
        AMMSeedParams memory seedParams
    ) external returns (address newAMM);
}
