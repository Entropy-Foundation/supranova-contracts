// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

contract Errors {
    /// @notice The caller is not authorized to perform this action
    error UnauthorizedSender();
    /// @notice Vault is paused and the action cannot be performed
    error VaultPaused();
    /// @notice One or more inputs are invalid
    error InvalidInput();
    /// @notice Provided amount does not respect configured per-operation limits
    error LimitBreached();
    /// @notice Cumulative locked amount would exceed configured global maximum
    error GlobaTokenLockLimitBreached();
    /// @notice Release operations are currently disabled
    error ReleaseDisabled();
    /// @notice A withdrawal with the same id has already been added
    error WithdrawalAlreadyAdded(bytes32);
    /// @notice No scheduled withdrawal exists for the given id
    error WithdrawDoesNotExist(bytes32);
    /// @notice The delay has not elapsed yet, try again later
    error TryLater();
    /// @notice Vault does not have enough balance to complete the operation
    error InsufficientBalance();
}