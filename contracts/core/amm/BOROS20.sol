// SPDX-License-Identifier: BUSL-1.1
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.28;

import {IBOROS20} from "./../../interfaces/IAMM.sol";
import {MarketAcc} from "./../../types/Account.sol";

abstract contract BOROS20 is IBOROS20 {
    mapping(MarketAcc account => uint256) private _balances;

    MarketAcc private constant _ZERO_ACCOUNT = MarketAcc.wrap(0);

    uint256 private _totalSupply;
    string internal _name;
    string internal _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(MarketAcc account) public view virtual returns (uint256) {
        return _balances[account];
    }

    function _mint(MarketAcc account, uint256 value) internal {
        _update(_ZERO_ACCOUNT, account, value);
    }

    function _burn(MarketAcc account, uint256 value) internal {
        _update(account, _ZERO_ACCOUNT, value);
    }

    function _update(MarketAcc from, MarketAcc to, uint256 value) internal virtual {
        if (from == _ZERO_ACCOUNT) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert BOROS20NotEnoughBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from] = fromBalance - value;
            }
        }

        if (to == _ZERO_ACCOUNT) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _balances[to] += value;
            }
        }

        emit BOROS20Transfer(from, to, value);
    }
}
