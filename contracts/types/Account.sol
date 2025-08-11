// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {TokenId, MarketId, MarketIdLib} from "./MarketTypes.sol";

/**
 * @title Account
 * @notice Custom type for handling account identifiers with packed data
 * @dev Packs exactly 21 bytes (168 bits) from high to low: address(160) | accountId(8)
 */
type Account is bytes21;

/**
 * @title MarketAcc
 * @notice Custom type for handling market account identifiers with packed data
 * @dev Packs exactly 26 bytes (208 bits) from high to low: address(160) | accountId(8) | tokenId(16) | marketId(24)
 */
type MarketAcc is bytes26;

// Global operators
function _eq(MarketAcc u, MarketAcc v) pure returns (bool) {
    return MarketAcc.unwrap(u) == MarketAcc.unwrap(v);
}

function _neq(MarketAcc u, MarketAcc v) pure returns (bool) {
    return MarketAcc.unwrap(u) != MarketAcc.unwrap(v);
}

using {_eq as ==, _neq as !=} for MarketAcc global;
using AccountLib for Account global;
using AccountLib for MarketAcc global;

library AccountLib {
    using AccountLib for address;

    Account internal constant ZERO_ACC = Account.wrap(0);
    MarketAcc internal constant ZERO_MARKET_ACC = MarketAcc.wrap(0);
    uint8 internal constant MAIN_ACCOUNT_ID = 0;
    uint8 internal constant AMM_ACCOUNT_ID = type(uint8).max;

    // --
    function from(address _root, uint8 _accountId) internal pure returns (Account) {
        uint168 rawValue = (uint168(uint160(_root)) << 8) | uint168(_accountId);
        return Account.wrap(bytes21(rawValue));
    }

    function root(Account acc) internal pure returns (address _root) {
        uint168 rawValue = uint168(Account.unwrap(acc));
        return address(uint160(rawValue >> 8));
    }

    function accountId(Account acc) internal pure returns (uint8 _accountId) {
        uint168 rawValue = uint168(Account.unwrap(acc));
        return uint8(rawValue);
    }

    function isZero(Account acc) internal pure returns (bool) {
        return Account.unwrap(acc) == 0;
    }

    // ---

    function isMain(Account acc) internal pure returns (bool) {
        return acc.accountId() == MAIN_ACCOUNT_ID;
    }

    function isAMM(Account acc) internal pure returns (bool) {
        return acc.accountId() == AMM_ACCOUNT_ID;
    }

    function toMain(address _root) internal pure returns (Account) {
        return from(_root, MAIN_ACCOUNT_ID);
    }

    function toAMM(address _root) internal pure returns (Account) {
        return from(_root, AMM_ACCOUNT_ID);
    }

    function toMainCross(address _root, TokenId _tokenId) internal pure returns (MarketAcc) {
        return from(_root, MAIN_ACCOUNT_ID, _tokenId, MarketIdLib.CROSS);
    }

    function toAmmAcc(address _root, TokenId _tokenId, MarketId _marketId) internal pure returns (MarketAcc) {
        return from(_root, AMM_ACCOUNT_ID, _tokenId, _marketId);
    }

    function toMarketAcc(
        Account acc,
        bool cross,
        TokenId _tokenId,
        MarketId _marketId
    ) internal pure returns (MarketAcc) {
        if (cross) {
            return toCross(acc, _tokenId);
        } else {
            return toIsolated(acc, _tokenId, _marketId);
        }
    }

    function toCross(Account acc, TokenId _tokenId) internal pure returns (MarketAcc) {
        uint208 packed = uint168(Account.unwrap(acc));
        packed = (packed << 16) | TokenId.unwrap(_tokenId);
        packed = (packed << 24) | MarketId.unwrap(MarketIdLib.CROSS);
        return MarketAcc.wrap(bytes26(packed));
    }

    function toIsolated(Account acc, TokenId _tokenId, MarketId _marketId) internal pure returns (MarketAcc) {
        uint208 packed = uint168(Account.unwrap(acc));
        packed = (packed << 16) | TokenId.unwrap(_tokenId);
        packed = (packed << 24) | MarketId.unwrap(_marketId);
        return MarketAcc.wrap(bytes26(packed));
    }

    // --- MarketAccLib ---

    function from(
        address _root,
        uint8 _accountId,
        TokenId _tokenId,
        MarketId _marketId
    ) internal pure returns (MarketAcc) {
        uint208 packed = 0;
        packed = uint208(uint160(_root));
        packed = (packed << 8) | _accountId;
        packed = (packed << 16) | TokenId.unwrap(_tokenId);
        packed = (packed << 24) | MarketId.unwrap(_marketId);
        return MarketAcc.wrap(bytes26(packed));
    }

    // ---

    function root(MarketAcc self) internal pure returns (address _root) {
        uint208 rawValue = uint208(MarketAcc.unwrap(self));
        _root = address(uint160(rawValue >> 48));
    }

    function account(MarketAcc self) internal pure returns (Account) {
        uint208 rawValue = uint208(MarketAcc.unwrap(self));
        return Account.wrap(bytes21(uint168(rawValue >> 40)));
    }

    function accountId(MarketAcc self) internal pure returns (uint8 _accountId) {
        uint208 rawValue = uint208(MarketAcc.unwrap(self));
        return uint8(rawValue >> 40);
    }

    function tokenId(MarketAcc self) internal pure returns (TokenId _tokenId) {
        uint208 rawValue = uint208(MarketAcc.unwrap(self));
        return TokenId.wrap(uint16(rawValue >> 24));
    }

    function marketId(MarketAcc self) internal pure returns (MarketId _marketId) {
        uint208 rawValue = uint208(MarketAcc.unwrap(self));
        return MarketId.wrap(uint24(rawValue));
    }

    function isZero(MarketAcc self) internal pure returns (bool) {
        return MarketAcc.unwrap(self) == 0;
    }

    // ---

    function isCross(MarketAcc self) internal pure returns (bool) {
        return self.marketId() == MarketIdLib.CROSS;
    }

    function toCross(MarketAcc self) internal pure returns (MarketAcc) {
        uint208 packed = ((uint208(MarketAcc.unwrap(self)) >> 24) << 24) | MarketId.unwrap(MarketIdLib.CROSS);
        return MarketAcc.wrap(bytes26(packed));
    }
}
