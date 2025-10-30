// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

contract Errors {
    /// @notice The caller is not authorized to perform this action
    error UnauthorizedSender();
    /// @notice Destination chain is not supported/enabled
    error UnsupportedToChain();
    /// @notice One or more inputs are invalid
    error InvalidInput();
    /// @notice Hypernova is paused and the action cannot be performed
    error HNBridgePaused();
    /// @notice Percentage value is invalid
    error InvalidPercentage();
    /// @notice Margin value is invalid
    error InvalidMargin();
    /// @notice Traffic parameter X cannot be more than CR
    error XCannotBeMore();
    /// @notice Verification fee computation overflow/invalid
    error InvalidVComputation(uint256 v);
    /// @notice Committee updater reward computation overflow/invalid
    error InvalidCRComputation(uint256 cr);

}
