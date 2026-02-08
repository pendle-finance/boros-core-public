// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PendleMulticallOwner is Ownable {
    event TryAggregateCallSucceeded(uint256 index);
    event TryAggregateCallFailed(uint256 index, bytes4 errorSelector);

    struct Call {
        address target;
        uint256 value;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    function tryAggregate(
        bool requireSuccess,
        Call[] calldata calls
    ) external payable onlyOwner returns (Result[] memory returnData) {
        uint256 length = calls.length;
        returnData = new Result[](length);
        for (uint256 i = 0; i < length; i++) {
            Call calldata call = calls[i];
            Result memory result = returnData[i];
            (result.success, result.returnData) = call.target.call{value: call.value}(call.callData);
            if (result.success) {
                emit TryAggregateCallSucceeded(i);
            } else {
                emit TryAggregateCallFailed(i, bytes4(result.returnData));
            }
            if (requireSuccess) require(result.success, "Multicall: call failed");
        }
    }
}
