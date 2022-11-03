// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "ds-test/test.sol";
import "forge-std/Vm.sol";

import { Comptroller } from "../compound/Comptroller.sol";
import { CErc20Delegate } from "../compound/CErc20Delegate.sol";
import { MasterPriceOracle } from "../oracles/MasterPriceOracle.sol";

import { WETH } from "solmate/tokens/WETH.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

import "../FuseSafeLiquidator.sol";
import "../FusePoolDirectory.sol";
import "./config/BaseTest.t.sol";
import "../liquidators/CurveLpTokenLiquidatorNoRegistry.sol";
import "../liquidators/CurveSwapLiquidator.sol";
import "../liquidators/CurveSwapLiquidatorFunder.sol";

contract AnyLiquidationTest is BaseTest {
  FuseSafeLiquidator fsl;
  address uniswapRouter;
  mapping(address => address) assetSpecificRouters;
  CurveLpTokenPriceOracleNoRegistry curveOracle;

  IFundsConversionStrategy[] fundingStrategies;
  bytes[] fundingDatas;

  IRedemptionStrategy[] redemptionStrategies;
  bytes[] redemptionDatas;

  IUniswapV2Pair mostLiquidPair1;
  IUniswapV2Pair mostLiquidPair2;

  function upgradeAp() internal {
    bytes32 _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    AddressesProvider newImpl = new AddressesProvider();
    newImpl.initialize(address(this));
    TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(address(ap)));
    bytes32 bytesAtSlot = vm.load(address(proxy), _ADMIN_SLOT);
    address admin = address(uint160(uint256(bytesAtSlot)));
    vm.prank(admin);
    proxy.upgradeTo(address(newImpl));
  }

  function afterForkSetUp() internal override {
    upgradeAp();

    uniswapRouter = ap.getAddress("IUniswapV2Router02");

    if (block.chainid == BSC_MAINNET) {
      mostLiquidPair1 = IUniswapV2Pair(0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16); // WBNB-BUSD
      mostLiquidPair2 = IUniswapV2Pair(0x61EB789d75A95CAa3fF50ed7E47b96c132fEc082); // WBNB-BTCB
      curveOracle = CurveLpTokenPriceOracleNoRegistry(0x4544d21EB5B368b3f8F98DcBd03f28aC0Cf6A0CA);
      fsl = FuseSafeLiquidator(payable(ap.getAddress("FuseSafeLiquidator")));
      //      fsl = new FuseSafeLiquidator();
      //      fsl.initialize(
      //        ap.getAddress("wtoken"),
      //        uniswapRouter,
      //        ap.getAddress("stableToken"),
      //        ap.getAddress("wBTCToken"),
      //        "0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5",
      //        25
      //      );

      {
        // manual config
        // TODO configure in the AP?
        address bnbx = 0x1bdd3Cf7F79cfB8EdbB955f20ad99211551BA275;
        address apeSwapRouter = 0xcF0feBd3f17CEf5b47b0cD257aCf6025c5BFf3b7;
        assetSpecificRouters[bnbx] = apeSwapRouter;

        // BRZ funding strategy
        address brz = 0x71be881e9C5d4465B3FfF61e89c6f3651E69B5bb;
        address jbrl = 0x316622977073BBC3dF32E7d2A9B3c77596a0a603;
        address brzw = 0x5b1a9850f55d9282a7C4Bf23A2a21B050e3Beb2f;

        AddressesProvider.FundingStrategy memory fs = ap.getFundingStrategy(brz);
        if (fs.addr != address(0)) revert("remove the manual config for brz");

        CurveSwapLiquidatorFunder cslf = new CurveSwapLiquidatorFunder();
        vm.prank(ap.owner());
        ap.setFundingStrategy(brz, address(cslf), "CurveSwapLiquidatorFunder", jbrl);

        address[] memory coins = new address[](3);
        coins[0] = jbrl;
        coins[1] = brz;
        coins[2] = brzw;
        vm.prank(ap.owner());
        ap.setCurveSwapPool(0x43719DfFf12B04C71F7A589cdc7F54a01da07D7a, coins);
      }
    } else if (block.chainid == POLYGON_MAINNET) {
      mostLiquidPair1 = IUniswapV2Pair(0x6e7a5FAFcec6BB1e78bAE2A1F0B612012BF14827); // USDC/WMATIC
      mostLiquidPair2 = IUniswapV2Pair(0x369582d2010B6eD950B571F4101e3bB9b554876F); // SAND/WMATIC
      curveOracle = CurveLpTokenPriceOracleNoRegistry(0xaCF3E1C6f2D6Ff12B8aEE44413D6834774B3f7A3);
      fsl = FuseSafeLiquidator(payable(ap.getAddress("FuseSafeLiquidator")));
      //      fsl = new FuseSafeLiquidator();
      //      fsl.initialize(
      //        ap.getAddress("wtoken"),
      //        uniswapRouter,
      //        ap.getAddress("stableToken"),
      //        ap.getAddress("wBTCToken"),
      //        "0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f",
      //        30
      //      );
    }
  }

  function testBscAnyLiquidation(uint256 random) public fork(BSC_MAINNET) {
    vm.assume(random > 100 && random < type(uint64).max);
    doTestAnyLiquidation(random);
  }

  function testPolygonAnyLiquidation(uint256 random) public fork(POLYGON_MAINNET) {
    vm.assume(random > 100 && random < type(uint64).max);
    doTestAnyLiquidation(random);
  }

  struct LiquidationData {
    FusePoolDirectory.FusePool[] pools;
    address[] cTokens;
    IRedemptionStrategy[] strategies;
    bytes[] redemptionDatas;
    CTokenInterface[] markets;
    address[] borrowers;
    FuseSafeLiquidator liquidator;
    IFundsConversionStrategy[] fundingStrategies;
    bytes[] fundingDatas;
    CErc20Delegate debtMarket;
    CErc20Delegate collateralMarket;
    Comptroller comptroller;
    address borrower;
    uint256 borrowAmount;
    address flashSwapFundingToken;
    IUniswapV2Pair flashSwapPair;
  }

  function getPoolAndBorrower(uint256 random, LiquidationData memory vars)
    internal
    view
    returns (Comptroller, address)
  {
    if (vars.pools.length == 0) revert("no pools to pick from");

    uint256 i = random % vars.pools.length; // random pool
    Comptroller comptroller = Comptroller(vars.pools[i].comptroller);
    address[] memory borrowers = comptroller.getAllBorrowers();

    if (borrowers.length == 0) {
      return (Comptroller(address(0)), address(0));
    } else {
      uint256 k = random % borrowers.length; // random borrower
      address borrower = borrowers[k];

      return (comptroller, borrower);
    }
  }

  function setUpDebtAndCollateralMarkets(uint256 random, LiquidationData memory vars)
    internal
    returns (
      CErc20Delegate debt,
      CErc20Delegate collateral,
      uint256 borrowAmount
    )
  {
    // debt
    for (uint256 m = 0; m < vars.markets.length; m++) {
      uint256 marketIndexWithOffset = (random + m) % vars.markets.length;
      borrowAmount = vars.markets[marketIndexWithOffset].borrowBalanceStored(vars.borrower);
      if (borrowAmount > 0) {
        debt = CErc20Delegate(address(vars.markets[marketIndexWithOffset]));
        break;
      }
    }

    if (address(debt) != address(0)) {
      emit log("debt market is");
      emit log_address(address(debt));

      uint256 shortfall = 0;
      // reduce the collateral for each market of the borrower
      // until there is shortfall for which to be liquidated
      for (uint256 m = 0; m < vars.markets.length; m++) {
        uint256 marketIndexWithOffset = (random - m) % vars.markets.length;
        if (vars.markets[marketIndexWithOffset].balanceOf(vars.borrower) > 0) {
          if (address(vars.markets[marketIndexWithOffset]) == address(debt)) continue;

          collateral = CErc20Delegate(address(vars.markets[marketIndexWithOffset]));

          // the collateral prices change
          MasterPriceOracle mpo = MasterPriceOracle(address(vars.comptroller.oracle()));
          uint256 priceCollateral = mpo.getUnderlyingPrice(ICToken(address(collateral)));
          vm.mockCall(
            address(mpo),
            abi.encodeWithSelector(mpo.getUnderlyingPrice.selector, ICToken(address(collateral))),
            abi.encode(priceCollateral / 5)
          );

          (, , shortfall) = vars.comptroller.getHypotheticalAccountLiquidity(vars.borrower, address(0), 0, 0);
          if (shortfall == 0) {
            emit log("collateral still enough");
            continue;
          } else {
            emit log("has shortfall");
            break;
          }
        }
      }
      if (shortfall == 0) {
        return (CErc20Delegate(address(0)), CErc20Delegate(address(0)), 0);
      }
    }
  }

  function doTestAnyLiquidation(uint256 random) internal {
    LiquidationData memory vars;
    vars.liquidator = fsl;

    vars.pools = FusePoolDirectory(ap.getAddress("FusePoolDirectory")).getAllPools();

    while (true) {
      // get a random pool and a random borrower from it
      (vars.comptroller, vars.borrower) = getPoolAndBorrower(random, vars);

      if (address(vars.comptroller) != address(0) && vars.borrower != address(0)) {
        // find a market in which the borrower has debt and reduce his collateral price
        vars.markets = vars.comptroller.getAllMarkets();
        (vars.debtMarket, vars.collateralMarket, vars.borrowAmount) = setUpDebtAndCollateralMarkets(random, vars);

        if (address(vars.debtMarket) != address(0) && address(vars.collateralMarket) != address(0)) {
          emit log("found testable markets at random number");
          emit log_uint(random);
          break;
        }
      }
      random++;
    }

    emit log("debt and collateral markets");
    emit log_address(address(vars.debtMarket));
    emit log_address(address(vars.collateralMarket));

    // prepare the liquidation

    // add funding strategies
    {
      address debtTokenToFund = vars.debtMarket.underlying();

      uint256 i = 0;
      while (true) {
        emit log("debt token");
        emit log_address(debtTokenToFund);
        if (i++ > 10) revert("endless loop bad");

        AddressesProvider.FundingStrategy memory strategy = ap.getFundingStrategy(debtTokenToFund);
        if (strategy.addr == address(0)) break;

        debtTokenToFund = addFundingStrategy(
          vars,
          IFundsConversionStrategy(strategy.addr),
          debtTokenToFund,
          strategy.contractInterface,
          strategy.inputToken
        );
      }

      vars.flashSwapFundingToken = debtTokenToFund;
      if (vars.flashSwapFundingToken != ap.getAddress("wtoken")) {
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapRouter);
        address pairAddress = IUniswapV2Factory(router.factory()).getPair(
          vars.flashSwapFundingToken,
          ap.getAddress("wtoken")
        );
        if (pairAddress != address(0)) {
          vars.flashSwapPair = IUniswapV2Pair(pairAddress);
        } else {
          revert("no pair for flash swap funding");
        }
      } else {
        vars.flashSwapPair = IUniswapV2Pair(mostLiquidPair1);
      }

      vars.fundingStrategies = fundingStrategies;
      vars.fundingDatas = fundingDatas;
    }

    emit log("flash swap funding token is");
    emit log_address(vars.flashSwapFundingToken);

    address exchangeCollateralTo = vars.flashSwapFundingToken;

    // add the redemption strategies
    if (exchangeCollateralTo != address(0)) {
      address collateralTokenToRedeem = vars.collateralMarket.underlying();
      while (collateralTokenToRedeem != exchangeCollateralTo) {
        AddressesProvider.RedemptionStrategy memory strategy = ap.getRedemptionStrategy(collateralTokenToRedeem);
        if (strategy.addr == address(0)) break;
        collateralTokenToRedeem = addRedemptionStrategy(
          vars,
          IRedemptionStrategy(strategy.addr),
          strategy.contractInterface,
          collateralTokenToRedeem,
          strategy.outputToken
        );
      }
      vars.redemptionDatas = redemptionDatas;
      vars.strategies = redemptionStrategies;
    }

    // liquidate
    vm.prank(ap.owner());
    try
      vars.liquidator.safeLiquidateToTokensWithFlashLoan(
        FuseSafeLiquidator.LiquidateToTokensWithFlashSwapVars(
          vars.borrower,
          vars.borrowAmount / 100, //repayAmount,
          ICErc20(address(vars.debtMarket)),
          ICErc20(address(vars.collateralMarket)),
          vars.flashSwapPair,
          0,
          exchangeCollateralTo,
          IUniswapV2Router02(uniswapRouter), // TODO ASSET_SPECIFIC_ROUTER
          IUniswapV2Router02(uniswapRouter), // TODO ASSET_SPECIFIC_ROUTER
          vars.strategies,
          vars.redemptionDatas,
          0,
          vars.fundingStrategies,
          vars.fundingDatas
        )
      )
    {
      // noop
    } catch Error(string memory reason) {
      if (compareStrings(reason, "Number of tokens less than minimum limit")) {
        emit log("jarvis pool failing, that's ok");
      } else {
        revert(reason);
      }
    }
  }

  function getUniswapV2Router(address inputToken) internal returns (address) {
    address router = assetSpecificRouters[inputToken];
    return router != address(0) ? router : uniswapRouter;
  }

  function toggleFlashSwapPair(LiquidationData memory vars) internal {
    if (address(vars.flashSwapPair) == address(mostLiquidPair1)) {
      vars.flashSwapPair = mostLiquidPair2;
    } else {
      vars.flashSwapPair = mostLiquidPair1;
    }
  }

  function addRedemptionStrategy(
    LiquidationData memory vars,
    IRedemptionStrategy strategy,
    string memory strategyContract,
    address inputToken,
    address strategyOutputToken
  ) internal returns (address) {
    address outputToken;
    bytes memory strategyData;

    if (compareStrings(strategyContract, "UniswapLpTokenLiquidator")) {
      IUniswapV2Pair pair = IUniswapV2Pair(inputToken);
      address[] memory swapToken0Path;
      address[] memory swapToken1Path;

      if (pair.token0() == strategyOutputToken) {
        swapToken0Path = new address[](0);
        swapToken1Path = new address[](2);

        swapToken1Path[0] = pair.token1();
        swapToken1Path[1] = pair.token0();
        outputToken = swapToken1Path[1];
      } else {
        swapToken0Path = new address[](2);
        swapToken1Path = new address[](0);

        swapToken0Path[0] = pair.token0();
        swapToken0Path[1] = pair.token1();
        outputToken = swapToken0Path[1];
      }

      strategyData = abi.encode(uniswapRouter, swapToken0Path, swapToken1Path);

      if (address(vars.flashSwapPair) == address(pair)) {
        emit log("toggling the flashswap pair");
        emit log_address(address(pair));
        toggleFlashSwapPair(vars);
      }
    } else if (compareStrings(strategyContract, "UniswapV2LiquidatorFunder")) {
      outputToken = strategyOutputToken;

      address[] memory swapPath = new address[](2);
      swapPath[0] = inputToken;
      swapPath[1] = outputToken;

      strategyData = abi.encode(getUniswapV2Router(inputToken), swapPath);
    } else if (compareStrings(strategyContract, "JarvisLiquidatorFunder")) {
      AddressesProvider.JarvisPool[] memory pools = ap.getJarvisPools();
      for (uint256 i = 0; i < pools.length; i++) {
        AddressesProvider.JarvisPool memory pool = pools[i];
        if (pool.syntheticToken == inputToken) {
          strategyData = abi.encode(pool.syntheticToken, pool.liquidityPool, pool.expirationTime);
          outputToken = pool.collateralToken;
          break;
        }
      }
    } else if (compareStrings(strategyContract, "CurveSwapLiquidator")) {
      outputToken = strategyOutputToken;

      AddressesProvider.CurveSwapPool[] memory curveSwapPools = ap.getCurveSwapPools();
      for (uint256 i = 0; i < curveSwapPools.length; i++) {
        if (curveSwapPools[i].poolAddress == inputToken) {
          emit log_address(inputToken);
          emit log_address(strategyOutputToken);
          revert("use the CurveLpTokenLiquidatorNoRegistry for the redemption of LP tokens");
        }
      }

      int128 outputIndex;
      int128 inputIndex;
      address poolAddress;
      for (uint256 i = 0; i < curveSwapPools.length; i++) {
        outputIndex = -1;
        inputIndex = -1;
        poolAddress = curveSwapPools[i].poolAddress;
        ICurvePool curvePool = ICurvePool(poolAddress);
        int128 j = 0;
        while (true) {
          try curvePool.coins(uint256(int256(j))) returns (address coin) {
            if (coin == outputToken) outputIndex = j;
            else if (coin == inputToken) inputIndex = j;
          } catch {
            break;
          }
          j++;
        }
        if (outputIndex >= 0 && inputIndex >= 0) break;
      }

      if (outputIndex == -1 || inputIndex == -1) {
        emit log("input token");
        emit log_address(inputToken);
        emit log("output token");
        emit log_address(outputToken);
        revert("failed to find curve pool");
      }

      strategyData = abi.encode(poolAddress, inputIndex, outputIndex, outputToken, ap.getAddress("wtoken"));
    } else if (compareStrings(strategyContract, "CurveLpTokenLiquidatorNoRegistry")) {
      address[] memory underlyingTokens = getCurvePoolUnderlyingTokens(curveOracle.poolOf(inputToken));
      (address preferredOutputToken, uint8 outputTokenIndex) = pickPreferredToken(
        underlyingTokens,
        strategyOutputToken
      );
      emit log("preferred token");
      emit log_address(preferredOutputToken);
      emit log_uint(outputTokenIndex);
      outputToken = preferredOutputToken;
      if (outputToken == address(0) || outputToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
        outputToken = ap.getAddress("wtoken");
      }

      strategyData = abi.encode(outputTokenIndex, preferredOutputToken, ap.getAddress("wtoken"), address(curveOracle));
    } else {
      emit log(strategyContract);
      emit log_address(address(strategy));
      revert("unknown collateral");
    }

    vm.prank(vars.liquidator.owner());
    vars.liquidator._whitelistRedemptionStrategy(strategy, true);
    redemptionStrategies.push(strategy);
    redemptionDatas.push(strategyData);

    assertEq(outputToken, strategyOutputToken, "!expected output token");
    return outputToken;
  }

  function getCurvePoolUnderlyingTokens(address lpTokenAddress) internal returns (address[] memory) {
    ICurvePool curvePool = ICurvePool(lpTokenAddress);
    uint8 i = 0;
    while (true) {
      try curvePool.coins(i) returns (address underlying) {
        i++;
      } catch {
        break;
      }
    }
    address[] memory tokens = new address[](i);
    for (uint8 j = 0; j < i; j++) {
      tokens[j] = curvePool.coins(j);
    }
    return tokens;
  }

  function pickPreferredToken(address[] memory tokens, address strategyOutputToken) internal returns (address, uint8) {
    address wtoken = ap.getAddress("wtoken");
    address stable = ap.getAddress("stableToken");
    address wbtc = ap.getAddress("wBTCToken");

    for (uint8 i = 0; i < tokens.length; i++) {
      if (tokens[i] == strategyOutputToken) return (strategyOutputToken, i);
    }
    for (uint8 i = 0; i < tokens.length; i++) {
      if (tokens[i] == wtoken) return (wtoken, i);
    }
    for (uint8 i = 0; i < tokens.length; i++) {
      if (tokens[i] == stable) return (stable, i);
    }
    for (uint8 i = 0; i < tokens.length; i++) {
      if (tokens[i] == wbtc) return (wbtc, i);
    }
    return (tokens[0], 0);
  }

  function addFundingStrategy(
    LiquidationData memory vars,
    IFundsConversionStrategy strategy,
    address debtToken,
    string memory strategyContract,
    address strategyInputToken
  ) internal returns (address) {
    address inputToken;
    bytes memory strategyData;

    if (compareStrings(strategyContract, "JarvisLiquidatorFunder")) {
      AddressesProvider.JarvisPool[] memory pools = ap.getJarvisPools();

      for (uint256 i = 0; i < pools.length; i++) {
        AddressesProvider.JarvisPool memory pool = pools[i];
        if (pool.syntheticToken == debtToken) {
          strategyData = abi.encode(pool.collateralToken, pool.liquidityPool, pool.expirationTime);
          inputToken = pool.collateralToken;
          break;
        }
      }

      // } else if (compareStrings(strategyContract, "SomeOtherFunder")) {
      // bytes memory strategyData = abi.encode(strategySpecificParams);
      // (IERC20Upgradeable inputToken, uint256 inputAmount) = IFundsConversionStrategy(addr).estimateInputAmount(10**(debtToken.decimals()), strategyData);
      // fundingStrategies.push(new SomeOtherFunder());
      // return inputToken;
    } else if (compareStrings(strategyContract, "CurveSwapLiquidatorFunder")) {
      int128 inputIndex;
      int128 outputIndex;
      inputToken = strategyInputToken;

      AddressesProvider.CurveSwapPool[] memory curveSwapPools = ap.getCurveSwapPools();

      address poolAddress;
      for (uint256 i = 0; i < curveSwapPools.length; i++) {
        poolAddress = curveSwapPools[i].poolAddress;
        if (poolAddress == debtToken || poolAddress == inputToken) {
          emit log_address(debtToken);
          emit log_address(inputToken);
          emit log_address(poolAddress);
          revert("no strategy available for funding with curve LP tokens");
        }

        inputIndex = -1;
        outputIndex = -1;
        ICurvePool curvePool = ICurvePool(poolAddress);
        int128 j = 0;
        while (true) {
          try curvePool.coins(uint256(int256(j))) returns (address coin) {
            if (coin == debtToken) outputIndex = j;
            else if (coin == inputToken) inputIndex = j;
          } catch {
            break;
          }
          j++;
        }
        if (outputIndex >= 0 && inputIndex >= 0) break;
      }

      if (outputIndex == -1 || inputIndex == -1) {
        emit log("input token");
        emit log_address(inputToken);
        emit log("debt token");
        emit log_address(debtToken);
        revert("failed to find curve pool");
      }

      strategyData = abi.encode(poolAddress, inputIndex, outputIndex, debtToken, ap.getAddress("wtoken"));
    } else {
      emit log(strategyContract);
      emit log_address(debtToken);
      revert("unknown debt token");
    }

    fundingDatas.push(strategyData);

    vm.prank(vars.liquidator.owner());
    vars.liquidator._whitelistRedemptionStrategy(strategy, true);
    fundingStrategies.push(strategy);

    assertEq(strategyInputToken, inputToken, "!expected input token");
    return inputToken;
  }
}
