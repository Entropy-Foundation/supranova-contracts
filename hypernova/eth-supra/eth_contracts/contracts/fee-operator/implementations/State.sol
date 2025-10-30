// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;
import "../../interfaces/IFeeOperator.sol";

contract State {
    /// @notice Basis points base used for percentages (1e4)
    uint64 constant public PERCENTAGE_BASE = 1e4;
    /// @notice Normalization factor: supraPriceInUsdt.decimals (18) - USDT_DECIMALS(6) + SUPRA_DECIMALS(8)
    uint8 constant public NORMALIZED_DECIMALS = 20; //supraPriceInUsdt.decimals (18) - USDT_DECIMALS(6) + SUPRA_DECIMALS(8)
    /// @notice Address with administrative permissions over the fee operator
    address public admin;
    /// @dev Global pause flag
    bool isPaused;
    /// @dev Hypernova contract address
    address hypernova;
    /// @dev S-Value feed contract address
    address sValueFeed;
    /// @dev SUPRA/USDT pair index used by S-Value feed
    uint256 supraUsdtPairIndex;
    /// @dev Per-chain fee configurations
    mapping (uint64 toChainId => IFeeOperator.FeeConfig) public feeConfigs;
}