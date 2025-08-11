// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Library for generating pseudorandom numbers.
/// @notice This library was stripped to include only used functions.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibPRNG.sol)

/// @dev A pseudorandom number state in memory.
struct PRNG {
    uint256 state;
}

using PRNGLib for PRNG global;

library PRNGLib {
    /// @dev Seeds the `prng` with `state`.
    function seed(PRNG memory prng, uint256 state) internal pure {
        assembly ("memory-safe") {
            mstore(prng, state)
        }
    }

    /// @dev Returns the next pseudorandom uint256.
    /// All bits of the returned uint256 pass the NIST Statistical Test Suite.
    function next(PRNG memory prng) internal pure returns (uint256 result) {
        // We simply use `keccak256` for a great balance between
        // runtime gas costs, bytecode size, and statistical properties.
        //
        // A high-quality LCG with a 32-byte state
        // is only about 30% more gas efficient during runtime,
        // but requires a 32-byte multiplier, which can cause bytecode bloat
        // when this function is inlined.
        //
        // Using this method is about 2x more efficient than
        // `nextRandomness = uint256(keccak256(abi.encode(randomness)))`.
        assembly ("memory-safe") {
            result := keccak256(prng, 0x20)
            mstore(prng, result)
        }
    }
}
