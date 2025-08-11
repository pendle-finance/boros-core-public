// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AMMSeedParams} from "./IAMMFactory.sol";
import {AMMCreateParams} from "./IAMMFactory.sol";

interface IAdminModule {
    function newAMM(
        bool isPositive,
        AMMCreateParams memory createParams,
        AMMSeedParams memory seedParams
    ) external returns (address newAMM);

    function AMM_FACTORY() external view returns (address);
}
