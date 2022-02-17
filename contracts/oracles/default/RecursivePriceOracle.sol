// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;


import "../../external/compound/IPriceOracle.sol";
import "../../external/compound/ICToken.sol";
import "../../external/compound/ICErc20.sol";
import "../../external/compound/IComptroller.sol";

/**
 * @title RecursivePriceOracle
 * @notice Returns prices from other cTokens (from Fuse).
 * @dev Implements `PriceOracle`.
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 */
contract RecursivePriceOracle is IPriceOracle {
    /**
     * @notice Returns the price in ETH of the token underlying `cToken`.
     * @dev Implements the `PriceOracle` interface for Fuse pools (and Compound v2).
     * @return Price in ETH of the token underlying `cToken`, scaled by `10 ** (36 - underlyingDecimals)`.
     */
    function getUnderlyingPrice(ICToken cToken) external override view returns (uint) {
        // Get cToken's underlying cToken
        ICToken underlying = ICToken(ICErc20(address(cToken)).underlying());

        // Get Comptroller
        IComptroller comptroller = IComptroller(underlying.comptroller());

        // If cETH, return cETH/ETH exchange rate
        if (underlying.isCEther()) {
            return underlying.exchangeRateStored();
        }

        // Fuse cTokens: cToken/token price * token/ETH price = cToken/ETH price
        return (underlying.exchangeRateStored() * comptroller.oracle().getUnderlyingPrice(underlying)) / 1e18;
    }

}
