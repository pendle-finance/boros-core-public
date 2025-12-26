// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

struct SwapData {
    address tokenIn;
    uint256 amountIn;
    address tokenOut;
    address extRouter;
    bytes extCalldata;
}

interface IPSwapExecutor {
    function swap(address receiver, SwapData memory swapData) external payable;
}
