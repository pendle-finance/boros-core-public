// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AMMState, PositiveAMMMath} from "./../core/amm/PositiveAMMMath.sol";
import {NegativeAMMMath} from "./../core/amm/NegativeAMMMath.sol";
import {IAMMFactory, AMMCreateParams, AMMSeedParams} from "./../interfaces/IAMMFactory.sol";
import {IMarket} from "./../interfaces/IMarket.sol";
import {PendleRolesPlugin} from "./../core/roles/PendleRoles.sol";

/// @notice This will be deployed as TransparentUpgradeableProxy
contract AMMFactory is IAMMFactory, PendleRolesPlugin {
    address public immutable positiveAMMCreationCodeContract;
    address public immutable negativeAMMCreationCodeContract;

    constructor(
        address permissionController_,
        address positiveAMMCreationCodeContract_,
        address negativeAMMCreationCodeContract_
    ) PendleRolesPlugin(permissionController_) {
        positiveAMMCreationCodeContract = positiveAMMCreationCodeContract_;
        negativeAMMCreationCodeContract = negativeAMMCreationCodeContract_;
    }

    function create(
        bool isPositive,
        AMMCreateParams memory createParams,
        AMMSeedParams memory seedParams
    ) external returns (address newAMM) {
        AMMState memory initialState;

        address market = createParams.market;

        (, , , uint32 maturity, , , uint32 latestFTime) = IMarket(market).descriptor();

        if (isPositive) {
            initialState = PositiveAMMMath.calcSeedOutput(seedParams, maturity, latestFTime);
            newAMM = _deployPositiveAMM(createParams, initialState);
        } else {
            initialState = NegativeAMMMath.calcSeedOutput(seedParams, maturity, latestFTime);
            newAMM = _deployNegativeAMM(createParams, initialState);
        }

        emit AMMCreated(newAMM, isPositive, createParams, seedParams);
    }

    function _deployPositiveAMM(
        AMMCreateParams memory createParams,
        AMMState memory initialState
    ) internal returns (address) {
        bytes memory code = abi.encodePacked(
            positiveAMMCreationCodeContract.code,
            abi.encode(createParams, initialState)
        );
        return _create(code);
    }

    function _deployNegativeAMM(
        AMMCreateParams memory createParams,
        AMMState memory initialState
    ) internal returns (address) {
        bytes memory code = abi.encodePacked(
            negativeAMMCreationCodeContract.code,
            abi.encode(createParams, initialState)
        );
        return _create(code);
    }

    function _create(bytes memory code) internal returns (address addr) {
        assembly ("memory-safe") {
            addr := create(0, add(code, 0x20), mload(code))
        }
        require(addr != address(0), "Failed on deploy");
    }
}
