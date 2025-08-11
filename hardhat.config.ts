import "@nomicfoundation/hardhat-viem";
import "hardhat-contract-sizer";
import {HardhatUserConfig} from "hardhat/types";

function genSetting(params: {viaIR: boolean}) {
    return {
        version: "0.8.28",
        settings: {
            optimizer: {
                enabled: true,
                runs: 0,
            },
            viaIR: params.viaIR,
            evmVersion: "cancun",
        },
    };
}

const config: HardhatUserConfig = {
    solidity: {
        compilers: [genSetting({viaIR: false})],
        overrides: {
            // "contracts/core/market/Market1.sol": genSetting({viaIR: true}),
            // "contracts/core/router/trade/TradeModule.sol": genSetting({ viaIR: true }),
        },
    },
    contractSizer: {
        disambiguatePaths: false,
        runOnCompile: false,
        strict: true,
        only: [],
    },
};

export default config;
