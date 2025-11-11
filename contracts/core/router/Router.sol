// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// OpenZeppelin imports
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {RouterFacetLib} from "./../../generated/RouterFacetLib.sol";

// * Closely resemble the Diamond proxy pattern, Router is the main contract that delegates calls to the corresponding modules
// * This contract will be TransparentUpgradeableProxy'ed
contract Router is Proxy {
    address internal immutable _AMM_MODULE;
    address internal immutable _AUTH_MODULE;
    address internal immutable _CONDITIONAL_MODULE;
    address internal immutable _MISC_MODULE;
    address internal immutable _TRADE_MODULE;

    constructor(
        address ammModule_,
        address authModule_,
        address conditionalModule_,
        address miscModule_,
        address tradeModule_
    ) {
        _AMM_MODULE = ammModule_;
        _AUTH_MODULE = authModule_;
        _CONDITIONAL_MODULE = conditionalModule_;
        _MISC_MODULE = miscModule_;
        _TRADE_MODULE = tradeModule_;
    }

    function _implementation() internal view override returns (address) {
        return
            RouterFacetLib.resolveRouterFacet({
                sig: msg.sig,
                ammModule: _AMM_MODULE,
                authModule: _AUTH_MODULE,
                conditionalModule: _CONDITIONAL_MODULE,
                miscModule: _MISC_MODULE,
                tradeModule: _TRADE_MODULE
            });
    }
}
