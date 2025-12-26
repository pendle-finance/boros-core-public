// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract TokenHelper {
    using SafeERC20 for IERC20;

    address internal constant NATIVE = address(0);

    function _balanceOf(address addr, address token) internal view returns (uint256) {
        return (token == NATIVE) ? addr.balance : IERC20(token).balanceOf(addr);
    }

    function _selfBalance(address token) internal view returns (uint256) {
        return _balanceOf(address(this), token);
    }

    function _transferIn(address token, address from, uint256 amount) internal {
        if (token == NATIVE) require(msg.value == amount, "eth mismatch");
        else if (amount != 0) IERC20(token).safeTransferFrom(from, address(this), amount);
    }

    function _transferOut(address token, address to, uint256 amount) internal {
        if (amount == 0 || to == address(this)) return;
        if (token == NATIVE) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "eth send failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function _safeApproveInf(address token, address spender) internal {
        if (token == NATIVE) return;
        if (IERC20(token).allowance(address(this), spender) < type(uint256).max) {
            IERC20(token).forceApprove(spender, type(uint256).max);
        }
    }
}
