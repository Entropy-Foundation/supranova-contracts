// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

contract Errors {
    /// @notice The caller is not authorized to perform this action
    error UnauthorizedSender();
    /// @notice One or more inputs are invalid
    error InvalidInput();
    /// @notice Invalid chain id
    error InvalidChainId();
    /// @notice Amount is insufficient after fees
    error InsufficientAmount(uint256 amount, uint256 feeCutToService, uint256 relayerRewardInBridgedAsset);
    /// @notice Percentage value is invalid
    error InvalidPercentage();
    /// @notice Margin value is invalid
    error InvalidMargin();
    /// @notice Token is not registered
    error TokenNotRegistered();
    /// @notice Fee configuration is disabled
    error FeeConfigIsNotEnabled();
    /// @notice Hypernova configuration is disabled
    error HNConfigIsNotEnabled();
    /// @notice Fee operator is paused
    error FeeOperatorPaused();
    /// @notice Relayer reward computation overflow/invalid
    error InvalidRRComputation(uint256 rr);

    /// @notice Service fee computation resulted in invalid value
    error InvalidSValue(uint256 s);
    /// @notice Relayer reward in bridged asset is invalid
    error InvalidRRinBridgedAssetValue(uint256 rr);
    /// @notice Final amount is invalid
    error InvalidAmountValue(uint256 amount);
}
