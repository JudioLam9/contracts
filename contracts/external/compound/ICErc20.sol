// SPDX-License-Identifier: BSD-3-Clause
pragma solidity >=0.8.0;

import "./ICToken.sol";
import "../../oracles/keydonix/UniswapOracle.sol";

/**
 * @title Compound's CErc20 Contract
 * @notice CTokens which wrap an EIP-20 underlying
 * @author Compound
 */
interface ICErc20 is ICToken {
  function underlying() external view returns (address);

  function liquidateBorrow(
    address borrower,
    uint256 repayAmount,
    ICToken cTokenCollateral
  ) external returns (uint256);

//  function liquidateBorrowWithPriceProof(
//    address borrower,
//    uint256 repayAmount,
//    ICToken cTokenCollateral,
//    UniswapOracle.ProofData calldata repaidProofData,
//    UniswapOracle.ProofData calldata collateralProofData,
//    address _keydonixPriceOracle
//  ) external returns (uint256);
}
