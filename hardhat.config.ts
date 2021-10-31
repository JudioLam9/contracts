import "hardhat-deploy";

import { config as dotEnvConfig } from "dotenv";
import { HardhatUserConfig } from "hardhat/types";

dotEnvConfig();

const urlOverride = process.env.ETH_PROVIDER_URL;

const mnemonic =
  process.env.SUGAR_DADDY ||
  process.env.MNEMONIC ||
  "candy maple cake sugar pudding cream honey rich smooth crumble sweet treat";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.6.12",
    // settings: {
    //   optimizer: {
    //     enabled: true,
    //     runs: 200,
    //   },
    // },
  },
  paths: {
    artifacts: "./artifacts",
    sources: "./contracts",
    tests: "./test",
  },
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: { default: 0 },
    alice: { default: 1 },
    bob: { default: 2 },
    rando: { default: 3 },
  },
  networks: {
    hardhat: {},
    rinkeby: {
      accounts: { mnemonic },
      chainId: 4,
      url:
        urlOverride ||
        process.env.RINKEBY_ETH_PROVIDER_URL ||
        "http://localhost:8545",
    },
    bsc: {
      accounts: { mnemonic },
      chainId: 56,
      url:
        urlOverride ||
        process.env.BSC_PROVIDER_URL ||
        "https://bsc-dataseed.binance.org/",
    },
    chapel: {
      accounts: { mnemonic },
      chainId: 97,
      url: "https://data-seed-prebsc-2-s1.binance.org:8545/",
    },
  },
};

export default config;
