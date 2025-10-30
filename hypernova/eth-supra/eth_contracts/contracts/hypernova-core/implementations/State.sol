// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;
import "../../interfaces/IHypernova.sol";

contract State {
    /// @notice Basis points base used for percentages (1e4)
    uint64 constant public PERCENTAGE_BASE = 1e4;
    /// @notice Address with administrative permissions over Hypernova
    address public admin;
    /// @notice The next sequential message id
    uint256 public msgId;
    /// @notice Global pause flag for Hypernova
    bool public isPaused;
    /// @dev Per-chain Hypernova configuration
    mapping (uint64 toChainId => IHypernova.HNConfig) hnConfig;
}