// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {BitMath} from "../../../lib/math/BitMath.sol";
import {PMath} from "../../../lib/math/PMath.sol";
import {Side} from "../../../types/Order.sol";

struct TickBitmap {
    uint256 activeWordMask;
    uint256[256] words;
}

using TickBitmapLib for TickBitmap global;

library TickBitmapLib {
    using StorageSlot for bytes32;
    using SlotDerivation for bytes32;
    using PMath for uint256;

    function set(TickBitmap storage self, int16 iTick) internal {
        (uint8 wordPos, uint8 bitPos) = tickToPos(iTick);
        uint256 word = getWord(self, wordPos);
        uint256 newWord = word | (1 << bitPos);
        if (word == newWord) return;

        setWord(self, wordPos, newWord);
        if (word == 0) self.activeWordMask |= (1 << wordPos);
    }

    function reset(TickBitmap storage self, int16 iTick) internal {
        (uint8 wordPos, uint8 bitPos) = tickToPos(iTick);
        uint256 word = getWord(self, wordPos);
        uint256 newWord = word & ~(1 << bitPos);
        if (word == newWord) return;

        setWord(self, wordPos, newWord);
        if (newWord == 0) self.activeWordMask &= ~(1 << wordPos);
    }

    function findGreaterTick(
        TickBitmap storage self,
        int16 iTick
    ) internal view returns (int16 /* next */, bool found) {
        unchecked {
            if (iTick == type(int16).max) return (0, false);
            ++iTick;

            (uint8 wordPos, uint8 bitPos) = tickToPos(iTick);
            uint256 activeWordMask = self.activeWordMask;

            // Find in the same word
            if ((activeWordMask & (1 << wordPos)) != 0) {
                uint256 maskedWord = BitMath.keepNToMSB(getWord(self, wordPos), bitPos);
                if (maskedWord != 0) {
                    return (posToTick(wordPos, BitMath.leastSignificantBit(maskedWord)), true);
                }
            }

            // Find next active word and return lowest active tick
            if (wordPos < 255) {
                wordPos++;
                uint256 maskedActive = BitMath.keepNToMSB(activeWordMask, wordPos);
                if (maskedActive != 0) {
                    wordPos = BitMath.leastSignificantBit(maskedActive);
                    return (posToTick(wordPos, BitMath.leastSignificantBit(getWord(self, wordPos))), true);
                }
            }

            return (0, false);
        }
    }

    function findLessTick(TickBitmap storage self, int16 iTick) internal view returns (int16 /* prev */, bool found) {
        unchecked {
            if (iTick == type(int16).min) return (0, false);
            --iTick;

            (uint8 wordPos, uint8 bitPos) = tickToPos(iTick);
            uint256 activeWordMask = self.activeWordMask;

            // Find in the same word
            if ((activeWordMask & (1 << wordPos)) != 0) {
                uint256 maskedWord = BitMath.keepNToLSB(getWord(self, wordPos), bitPos);
                if (maskedWord != 0) {
                    return (posToTick(wordPos, BitMath.mostSignificantBit(maskedWord)), true);
                }
            }

            // Find prev active word and return highest active tick
            if (wordPos > 0) {
                wordPos--;
                uint256 maskedActive = BitMath.keepNToLSB(activeWordMask, wordPos);
                if (maskedActive != 0) {
                    wordPos = BitMath.mostSignificantBit(maskedActive);
                    return (posToTick(wordPos, BitMath.mostSignificantBit(getWord(self, wordPos))), true);
                }
            }

            return (0, false);
        }
    }

    function findLowestTick(TickBitmap storage self) internal view returns (int16 iTick, bool found) {
        uint256 active = self.activeWordMask;
        if (active == 0) return (0, false);
        uint8 wordPos = BitMath.leastSignificantBit(active);
        uint8 bitPos = BitMath.leastSignificantBit(getWord(self, wordPos));
        return (posToTick(wordPos, bitPos), true);
    }

    function findHighestTick(TickBitmap storage self) internal view returns (int16 iTick, bool found) {
        uint256 active = self.activeWordMask;
        if (active == 0) return (0, false);
        uint8 wordPos = BitMath.mostSignificantBit(active);
        uint8 bitPos = BitMath.mostSignificantBit(getWord(self, wordPos));
        return (posToTick(wordPos, bitPos), true);
    }

    // Private functions

    function setWord(TickBitmap storage self, uint8 wordPos, uint256 word) private {
        wordSlot(self, wordPos).value = word;
    }

    function getWord(TickBitmap storage self, uint8 wordPos) private view returns (uint256 word) {
        return wordSlot(self, wordPos).value;
    }

    function wordSlot(
        TickBitmap storage self,
        uint8 wordPos
    ) private pure returns (StorageSlot.Uint256Slot storage slot) {
        return _slot(self).offset(uint256(wordPos).inc()).getUint256Slot();
    }

    function _slot(TickBitmap storage self) private pure returns (bytes32 slot) {
        assembly {
            slot := self.slot
        }
    }

    function tickToPos(int16 iTick) private pure returns (uint8 wordPos, uint8 bitPos) {
        uint16 uTick = uint16(iTick) ^ (1 << 15);
        wordPos = uint8(uTick >> 8);
        bitPos = uint8(uTick & 255);
    }

    function posToTick(uint8 wordPos, uint8 bitPos) private pure returns (int16 iTick) {
        uint16 uTick = (uint16(wordPos) << 8) | uint16(bitPos);
        iTick = int16(uTick ^ (1 << 15));
    }
}

using TickIterationLib for TickBitmap global;

library TickIterationLib {
    function begin(TickBitmap storage tickBitmap, Side side) internal view returns (int16 tick, bool found) {
        if (side.sweepTickTopDown()) {
            return tickBitmap.findHighestTick();
        } else {
            return tickBitmap.findLowestTick();
        }
    }

    function next(TickBitmap storage tickBitmap, int16 iTick, Side side) internal view returns (int16 res, bool found) {
        if (side.sweepTickTopDown()) {
            return tickBitmap.findLessTick(iTick);
        } else {
            return tickBitmap.findGreaterTick(iTick);
        }
    }
}
