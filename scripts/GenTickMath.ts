import {indentBlock, fileHeader, genCodeThenWriteToFile} from "./helper";
import {Decimal} from "decimal.js";
Decimal.set({precision: 1000});

function main() {
    const FILE_NAME = "contracts/lib/math/TickMath.sol";
    genCodeThenWriteToFile(FILE_NAME, function* () {
        yield* fileHeader({
            solVer: "^0.8.28",
            runScript: "yarn ts-node scripts/GenTickMath.ts",
        });

        yield "// slither-disable-start too-many-digits";
        yield "// slither-disable-start cyclomatic-complexity";
        yield "";
        yield "/* solhint-disable*/";
        yield "// prettier-ignore";
        yield "library TickMath {";
        yield* indentBlock(function* () {
            yield `\
/// @return rate = g(tick * step)
/// @param step must be less than 16
/// @notice g(tick) = 1.00005^tick - 1 for tick >= 0
/// @notice g(tick) = -g(-tick) for tick < 0
function getRateAtTick(int16 tick, uint8 step) internal pure returns (int128 rate) {
    unchecked {
        return _getRateAtTick(int24(tick) * int24(uint24(step)));
    }
}`;
            yield "";

            yield `\
/// @return rate = g(tick)
/// @notice g(tick) = 1.00005^tick - 1 for tick >= 0
/// @notice g(tick) = -g(-tick) for tick < 0
/// @dev This function only works for tick from -32768 * 15 to 32767 * 15
/// The algorithm is divided into 2 parts:
/// - The first part is similar to https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/TickMath.sol#L23
///   That is, we calculate the inverse (1/1.00005^tick) for better precision.
/// - When tick has become too big, the inverse calculation will lose precision.
///   So for the second part, we convert it back to (1.00005^tick) then continue the calculation.
function _getRateAtTick(int24 tick) private pure returns (int128 rate) {
    unchecked {`;
            yield* indentBlock(genGetRateAtTick(), "    ".repeat(2));
            yield `\
    }
}`;
        });
        yield "}";

        yield "// slither-disable-end cyclomatic-complexity";
        yield "// slither-disable-end too-many-digits";
    });

    function* genGetRateAtTick(): Generator<string> {
        yield "if (tick == 0) return 0;";
        yield "uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));";
        yield "";

        const MAX_TWO_EXP = 15 + 4; // we allow up to (1.00005)^(2^(15) * 16)
        const MAX_PART_1_TWO_EXP = 16;

        const TWO = new Decimal(2);
        const PART1_PRECISION = 128;
        const PART2_PRECISION = 105;

        const BASE = new Decimal("1.00005");
        const INV_BASE = new Decimal(1).div(BASE);

        yield "uint256 _rate;";

        yield "_rate = absTick & 0x1 != 0";
        yield `    ? ${INV_BASE.mul(TWO.pow(PART1_PRECISION)).round().toHexadecimal()}`;
        yield `    : ${TWO.pow(PART1_PRECISION).toHexadecimal()};`;

        function genBinMulStatement(
            bit: number,
            base: Decimal,
            precision: number,
        ): string {
            const raw = base
                .pow(1 << bit)
                .mul(TWO.pow(precision))
                .round()
                .toHexadecimal();
            return `if (absTick & 0x${(1 << bit).toString(16)} != 0) _rate = (_rate * ${raw}) >> ${precision};`;
        }

        for (let i = 1; i < MAX_PART_1_TWO_EXP; ++i) {
            yield genBinMulStatement(i, INV_BASE, PART1_PRECISION);
        }

        yield "";
        yield "_rate = type(uint256).max / _rate; // _rate = 1 / _rate";
        yield `_rate >>= ${PART1_PRECISION - PART2_PRECISION}; // convert from exp 2^${PART1_PRECISION} to 2^${PART2_PRECISION}`;
        yield "";

        for (let i = MAX_TWO_EXP; i-- > MAX_PART_1_TWO_EXP; ) {
            yield genBinMulStatement(i, BASE, PART2_PRECISION);
        }

        const OUT_DEC_PRECISION = 18;
        yield "";
        yield `_rate = (_rate * 1e${OUT_DEC_PRECISION} + (1 << ${PART2_PRECISION - 1})) >> ${PART2_PRECISION}; // convert from exp 2^${PART2_PRECISION} to 10^${OUT_DEC_PRECISION}`;
        yield `_rate -= 1e${OUT_DEC_PRECISION};`;
        yield "rate = int128(int256(_rate));";
        yield "if (tick < 0) rate = -rate;";
    }
}

main();
