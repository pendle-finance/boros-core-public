// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EIP712} from "./../auth-base/EIP712.sol";
import {RouterAccountBase} from "./../auth-base/RouterAccountBase.sol";
import {Err} from "./../../../lib/Errors.sol";
import {IAMM} from "./../../../interfaces/IAMM.sol";
import {IMiscModule} from "./../../../interfaces/IMiscModule.sol";
import {PendleRolesPlugin} from "./../../../core/roles/PendleRoles.sol";
import {AuthStorage} from "./../auth-base/AuthStorage.sol";
import {TradeStorage} from "./../trade-base/TradeStorage.sol";
import {MarketAcc} from "./../../../types/Account.sol";
import {AMMId, TokenId} from "./../../../types/MarketTypes.sol";

contract MiscModule is RouterAccountBase, AuthStorage, TradeStorage, PendleRolesPlugin, EIP712, IMiscModule {
    using Address for address;
    using SafeERC20 for IERC20;

    constructor(
        address permissionController_,
        address marketHub_
    ) PendleRolesPlugin(permissionController_) TradeStorage(marketHub_) {
        _disableInitializers();
    }

    function initialize(
        string memory eip712Name,
        string memory eip712Version,
        uint16 numTicksToTryAtOnce_
    ) external initializer onlyRole(_INITIALIZER_ROLE) {
        __EIP712_init(eip712Name, eip712Version);
        _setNumTicksToTryAtOnce_checked_emit(numTicksToTryAtOnce_);
    }

    function tryAggregate(
        bool requireSuccess,
        bytes[] memory calls
    ) external returns (Result[] memory returnData, uint256[] memory gasUsed) {
        uint256 length = calls.length;
        returnData = new Result[](length);
        gasUsed = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            Result memory result = returnData[i];
            uint256 gasBefore = gasleft();
            (result.success, result.returnData) = address(this).delegatecall(calls[i]);
            gasUsed[i] = gasBefore - gasleft();
            if (result.success) {
                emit TryAggregateCallSucceeded(i);
            } else {
                emit TryAggregateCallFailed(i, bytes4(result.returnData));
            }
            if (requireSuccess) require(result.success, "Multicall3: call failed");
        }
    }

    // -------------------------- SIMULATE --------------------------

    error Router_RevertedBatchResult(bytes[] results, uint256[] gasUsed);

    function batchSimulate(
        SimulateData[] memory calls
    ) external returns (bytes[] memory /*results*/, uint256[] memory /*gasUsed*/) {
        (bool success, bytes memory result) = address(this).delegatecall(abi.encodeCall(this.batchRevert, calls));
        assert(!success);

        if (result.length < 4 || bytes4(result) != Router_RevertedBatchResult.selector) {
            _revertBytes(result);
        }

        assembly ("memory-safe") {
            let len := mload(result)
            result := add(result, 4)
            mstore(result, sub(len, 4)) // can not underflow as we require result.length >= 4 above
        }
        return abi.decode(result, (bytes[], uint256[]));
    }

    function _revertBytes(bytes memory errMsg) internal pure {
        assembly ("memory-safe") {
            let len := mload(errMsg)
            if len {
                revert(add(32, errMsg), len)
            }
            revert(0, 0)
        }
    }

    function batchRevert(SimulateData[] memory calls) external {
        bytes[] memory results = new bytes[](calls.length);
        uint256[] memory gasUsed = new uint256[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            uint256 gasBefore = gasleft();
            _setUnchecked(calls[i].account);
            results[i] = calls[i].target.functionCall(calls[i].data);
            gasUsed[i] = gasBefore - gasleft();
        }
        revert Router_RevertedBatchResult(results, gasUsed);
    }

    // -------------------------- ADMIN --------------------------

    function isAllowedRelayer(address relayer) external view returns (bool) {
        return _isAllowedRelayer(relayer);
    }

    function ammIdToAcc(AMMId ammId) external view returns (MarketAcc) {
        return _getAMMIdToAcc(ammId);
    }

    function numTicksToTryAtOnce() external view returns (uint16) {
        return _getNumTicksToTryAtOnce();
    }

    function maxIterationAndEps() external view returns (uint256 /*maxIteration*/, uint256 /*eps*/) {
        return (_getMaxIterationAddLiquidity(), _getEpsAddLiquidity());
    }

    function approveMarketHubInf(TokenId tokenId) external onlyAuthorized {
        address token = _MARKET_HUB.tokenIdToAddress(tokenId);
        IERC20(token).forceApprove(address(_MARKET_HUB), type(uint256).max);
        emit ApprovedMarketHubInf(tokenId);
    }

    function setAllowedRelayer(address relayer, bool allowed) external onlyAuthorized {
        _AMS().allowedRelayer[relayer] = allowed;
        emit AllowedRelayerUpdated(relayer, allowed);
    }

    function setAMMIdToAcc(address amm, bool forceOverride) external onlyAuthorized {
        AMMId ammId = IAMM(amm).AMM_ID();
        MarketAcc ammAcc = IAMM(amm).SELF_ACC();
        require(!ammId.isZero(), Err.InvalidAMMId());
        require(!ammAcc.isZero(), Err.InvalidAMMAcc());
        _setAMMIdToAcc(ammId, ammAcc, forceOverride);
        emit AMMIdToAccUpdated(ammId, ammAcc);
    }

    function setNumTicksToTryAtOnce(uint16 newNumTicksToTryAtOnce) external onlyAuthorized {
        _setNumTicksToTryAtOnce_checked_emit(newNumTicksToTryAtOnce);
    }

    function setMaxIterationAndEps(uint256 newMaxIteration, uint256 newEps) external onlyAuthorized {
        _setMaxIterationAddLiquidity(newMaxIteration);
        _setEpsAddLiquidity(newEps);
        emit MaxIterationAndEpsUpdated(newMaxIteration, newEps);
    }

    function _setNumTicksToTryAtOnce_checked_emit(uint16 newNumTicksToTryAtOnce) internal {
        require(newNumTicksToTryAtOnce > 0, Err.InvalidNumTicks());
        _setNumTicksToTryAtOnce(newNumTicksToTryAtOnce);
        emit NumTicksToTryAtOnceUpdated(newNumTicksToTryAtOnce);
    }
}
