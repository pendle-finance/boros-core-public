import assert from "assert";
import {
    toFunctionSelector,
    toFunctionSignature,
    zeroAddress,
    Abi,
    AbiFunction,
} from "viem";
import hre from "hardhat";
import {
    indentLine,
    indentBlock,
    fileHeader,
    genCodeThenWriteToFile,
} from "./helper";

type FuncData = {
    name: string;
    frag: AbiFunction;
};

function* genStaticDiamond(
    fnName: string,
    func: FuncData[],
    {stopBranch}: {stopBranch: number},
) {
    const allFunctions = func.map(
        (d) => [toFunctionSelector(d.frag), d] as const,
    );
    allFunctions.sort((lhs, rhs) => lhs[0].localeCompare(rhs[0]));
    for (let i = 1; i < allFunctions.length; ++i) {
        const [sel1, d1] = allFunctions[i - 1];
        const [sel2, d2] = allFunctions[i];
        if (sel1 === sel2) {
            throw new Error(
                `Selector ${sel1} collided. ${d1.name}.${toFunctionSignature(d1.frag)} and ${d2.name}.${toFunctionSignature(d2.frag)}`,
            );
        }
        assert(sel1 < sel2);
    }
    let numDivideBranch = 0;
    const allFuncLv: number[] = [];
    function* dnc(
        l: number,
        r: number,
        lv: number = 1,
    ): Generator<string, void, void> {
        const num = r - l;
        if (num == 0) return;
        if (num <= stopBranch) {
            for (let i = l; i < r; ++i, ++lv) {
                const [sel, d] = allFunctions[i];
                allFuncLv.push(lv);
                yield `if (sig == ${sel}) return ${d.name};  // (numCmp: ${lv}) ${toFunctionSignature(d.frag)}`;
            }
        } else {
            ++numDivideBranch;
            const mid = (l + r) >> 1;
            yield `if (sig < ${allFunctions[mid][0]}) {`;
            yield* indentBlock(dnc(l, mid, lv + 1));
            yield `} else {`;
            yield* indentBlock(dnc(mid, r, lv + 1));
            yield `}`;
        }
    }

    const allName = [...new Set(func.map((d) => d.name))].sort();
    const fnParams =
        "bytes4 sig, " + allName.map((n) => `address ${n}`).join(", ");
    yield `function ${fnName}(${fnParams}) internal pure returns (address resolvedFacet) {`;
    yield* indentBlock(dnc(0, allFunctions.length));
    yield indentLine(`assert(false);`);
    yield `}`;

    const sumLv = allFuncLv.reduce((a, b) => a + b, 0);
    const avg = sumLv / allFunctions.length;
    const std = Math.sqrt(
        allFuncLv.reduce((s, x) => s + (x - avg) ** 2, 0) / allFunctions.length,
    );
    const round = (x: number) => Math.round(x * 1000) / 1000;
    yield `// ${JSON.stringify({
        numSig: allFunctions.length,
        numDivideBranch,
        maxLv: allFuncLv.reduce((u, v) => Math.max(u, v)),
        avg: round(avg),
        std: round(std),
        stopBranch,
    })}`;
}

async function main() {
    const auth = await hre.viem.getContractAt("IAuthModule", zeroAddress);
    const amm = await hre.viem.getContractAt("IAMMModule", zeroAddress);
    const misc = await hre.viem.getContractAt("IMiscModule", zeroAddress);
    const trade = await hre.viem.getContractAt("ITradeModule", zeroAddress);

    const gatherAllFunctions = (name: string, abi: Abi) =>
        abi
            .filter((frag) => frag.type === "function")
            .map((frag) => ({name, frag}));

    const FILE_NAME = "contracts/generated/RouterFacetLib.sol";
    genCodeThenWriteToFile(FILE_NAME, function* () {
        yield* fileHeader({
            solVer: "^0.8.28",
            runScript: "yarn gen-router-static-diamond",
        });
        yield "// slither-disable-start cyclomatic-complexity";
        yield "// prettier-ignore";
        yield "library RouterFacetLib {";
        yield* indentBlock(
            genStaticDiamond(
                "resolveRouterFacet",
                [
                    ...gatherAllFunctions("ammModule", amm.abi),
                    ...gatherAllFunctions("authModule", auth.abi),
                    ...gatherAllFunctions("tradeModule", trade.abi),
                    ...gatherAllFunctions("miscModule", misc.abi),
                ],
                {stopBranch: 3},
            ),
        );
        yield "}";
        yield "";
        yield "// slither-disable-end cyclomatic-complexity";
    });
}

main().then(
    () => process.exit(0),
    (e) => {
        console.error(e);
        process.exit(1);
    },
);
