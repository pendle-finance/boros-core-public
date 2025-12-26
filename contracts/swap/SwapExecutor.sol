// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IPSwapExecutor, SwapData} from "../interfaces/IPSwapExecutor.sol";
import {TokenHelper} from "../lib/TokenHelper.sol";

contract SwapExecutor is IPSwapExecutor, TokenHelper {
    using Address for address;

    function swap(address receiver, SwapData memory $) external payable {
        _transferIn($.tokenIn, msg.sender, $.amountIn);
        _safeApproveInf($.tokenIn, $.extRouter);
        $.extRouter.functionCallWithValue($.extCalldata, $.tokenIn == NATIVE ? $.amountIn : 0);
        _transferOut($.tokenOut, receiver, _selfBalance($.tokenOut));
    }

    receive() external payable {}
}
