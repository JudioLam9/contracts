import { deployments } from "hardhat";
import { createPool } from "./utils";
import { deployAssets, getAssetsConf } from "./utils/pool";

describe("Deposit flow tests", function () {
  beforeEach(async function () {
    await deployments.fixture(); // ensure you start from a fresh deployments
  });

  describe("Deposit flow", async function () {
    it.only("should deposit asset to pool", async function () {
      const [, implementationAddress] = await createPool();
      const assets = await getAssetsConf(implementationAddress);
      await deployAssets(assets);
    });
  });
});
