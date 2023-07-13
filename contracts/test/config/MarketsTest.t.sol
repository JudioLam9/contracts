// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import { BaseTest } from "./BaseTest.t.sol";
import { FuseFeeDistributor } from "../../FuseFeeDistributor.sol";
import { CErc20Delegate } from "../../compound/CErc20Delegate.sol";
import { CErc20PluginRewardsDelegate } from "../../compound/CErc20PluginRewardsDelegate.sol";
import { DiamondExtension } from "../../midas/DiamondExtension.sol";
import { CTokenFirstExtension } from "../../compound/CTokenFirstExtension.sol";
import { Comptroller } from "../../compound/Comptroller.sol";
import { Unitroller } from "../../compound/Unitroller.sol";
import { ComptrollerFirstExtension } from "../../compound/ComptrollerFirstExtension.sol";
import { AuthoritiesRegistry } from "../../midas/AuthoritiesRegistry.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MarketsTest is BaseTest {
  FuseFeeDistributor internal ffd;

  CErc20Delegate internal cErc20Delegate;
  CErc20PluginRewardsDelegate internal cErc20PluginRewardsDelegate;
  CTokenFirstExtension internal newCTokenExtension;

  address payable internal latestComptrollerImplementation;
  ComptrollerFirstExtension internal comptrollerExtension;

  function afterForkSetUp() internal virtual override {
    ffd = FuseFeeDistributor(payable(ap.getAddress("FuseFeeDistributor")));
    upgradeFfd();
    cErc20Delegate = new CErc20Delegate();
    cErc20PluginRewardsDelegate = new CErc20PluginRewardsDelegate();
    newCTokenExtension = new CTokenFirstExtension();

    comptrollerExtension = new ComptrollerFirstExtension();
    Comptroller newComptrollerImplementation = new Comptroller(payable(address(ffd)));
    latestComptrollerImplementation = payable(address(newComptrollerImplementation));
  }

  function upgradeFfd() internal {
    {
      FuseFeeDistributor newImpl = new FuseFeeDistributor();
      TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(address(ffd)));
      bytes32 bytesAtSlot = vm.load(address(proxy), 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103);
      address admin = address(uint160(uint256(bytesAtSlot)));
      vm.prank(admin);
      proxy.upgradeTo(address(newImpl));
    }

    if (address(ffd.authoritiesRegistry()) == address(0)) {
      AuthoritiesRegistry impl = new AuthoritiesRegistry();
      TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), address(1), "");
      AuthoritiesRegistry newAr = AuthoritiesRegistry(address(proxy));
      newAr.initialize(address(321));
      vm.prank(ffd.owner());
      ffd.reinitialize(newAr);
    }
  }

  function _prepareCTokenUpgrade(CErc20Delegate market) internal returns (address) {
    address implBefore = market.implementation();
    //emit log("implementation before");
    //emit log_address(implBefore);

    CErc20Delegate newImpl;
    if (compareStrings("CErc20Delegate", market.contractType())) {
      newImpl = cErc20Delegate;
    } else {
      newImpl = cErc20PluginRewardsDelegate;
    }

    // whitelist the upgrade
    vm.prank(ffd.owner());
    ffd._editCErc20DelegateWhitelist(asArray(implBefore), asArray(address(newImpl)), asArray(false), asArray(true));

    // set the new ctoken delegate as the latest
    vm.prank(ffd.owner());
    ffd._setLatestCErc20Delegate(implBefore, address(newImpl), false, abi.encode(address(0)));

    // add the extension to the auto upgrade config
    DiamondExtension[] memory cErc20DelegateExtensions = new DiamondExtension[](1);
    cErc20DelegateExtensions[0] = newCTokenExtension;
    vm.prank(ffd.owner());
    ffd._setCErc20DelegateExtensions(address(newImpl), cErc20DelegateExtensions);

    return address(newImpl);
  }

  function _upgradeMarket(CErc20Delegate asDelegate) internal {
    address newDelegate = _prepareCTokenUpgrade(asDelegate);

    bytes memory becomeImplData = (address(newDelegate) == address(cErc20Delegate))
      ? bytes("")
      : abi.encode(address(0));
    vm.prank(asDelegate.fuseAdmin());
    asDelegate._setImplementationSafe(newDelegate, false, becomeImplData);
  }

  function _prepareComptrollerUpgrade(address oldCompImpl) internal {
    // whitelist the upgrade
    vm.startPrank(ffd.owner());
    ffd._editComptrollerImplementationWhitelist(
      asArray(oldCompImpl),
      asArray(latestComptrollerImplementation),
      asArray(true)
    );
    // whitelist the new pool creation
    ffd._editComptrollerImplementationWhitelist(
      asArray(address(0)),
      asArray(latestComptrollerImplementation),
      asArray(true)
    );
    DiamondExtension[] memory extensions = new DiamondExtension[](1);
    extensions[0] = comptrollerExtension;
    ffd._setComptrollerExtensions(latestComptrollerImplementation, extensions);
    vm.stopPrank();
  }

  function _upgradeExistingPool(address poolAddress) internal {
    Unitroller asUnitroller = Unitroller(payable(poolAddress));
    // change the implementation to the new that can add extensions
    address oldComptrollerImplementation = asUnitroller.comptrollerImplementation();

    _prepareComptrollerUpgrade(oldComptrollerImplementation);

    // upgrade to the new comptroller
    vm.startPrank(asUnitroller.admin());
    asUnitroller._setPendingImplementation(latestComptrollerImplementation);
    Comptroller(latestComptrollerImplementation)._become(poolAddress);
    vm.stopPrank();
  }
}
