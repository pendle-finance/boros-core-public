// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketId} from "./MarketTypes.sol";

library CreateCompute {
    function compute(address deployer, MarketId marketId) internal pure returns (address computedAddress) {
        bytes memory data;
        bytes1 len = bytes1(0x94);

        uint24 nonce = MarketId.unwrap(marketId);

        // The integer zero is treated as an empty byte string and therefore has only one length prefix,
        // 0x80, which is calculated via 0x80 + 0.
        if (nonce == 0x00) {
            data = abi.encodePacked(bytes1(0xd6), len, deployer, bytes1(0x80));
        }
        // A one-byte integer in the [0x00, 0x7f] range uses its own value as a length prefix, there is no
        // additional "0x80 + length" prefix that precedes it.
        else if (nonce <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), len, deployer, uint8(nonce));
        }
        // In the case of `nonce > 0x7f` and `nonce <= type(uint8).max`, we have the following encoding scheme
        // (the same calculation can be carried over for higher nonce bytes):
        // 0xda = 0xc0 (short RLP prefix) + 0x1a (= the bytes length of: 0x94 + address + 0x84 + nonce, in hex),
        // 0x94 = 0x80 + 0x14 (= the bytes length of an address, 20 bytes, in hex),
        // 0x84 = 0x80 + 0x04 (= the bytes length of the nonce, 4 bytes, in hex).
        else if (nonce <= type(uint8).max) {
            data = abi.encodePacked(bytes1(0xd7), len, deployer, bytes1(0x81), uint8(nonce));
        } else if (nonce <= type(uint16).max) {
            data = abi.encodePacked(bytes1(0xd8), len, deployer, bytes1(0x82), uint16(nonce));
        } else if (nonce <= type(uint24).max) {
            data = abi.encodePacked(bytes1(0xd9), len, deployer, bytes1(0x83), uint24(nonce));
        } else {
            assert(false);
        }

        computedAddress = address(uint160(uint256(keccak256(data))));
    }
}
