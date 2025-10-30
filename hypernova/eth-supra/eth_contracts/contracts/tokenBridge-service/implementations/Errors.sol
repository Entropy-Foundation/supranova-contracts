// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

contract Errors {
    /// @notice One or more inputs are invalid
    error InvalidInput();
    /// @notice Provided amount does not match msg.value for native transfers
    error IncorrectAmount();
    /// @notice Token is not registered for the destination chain
    error TokenNotRegistered();
    /// @notice Provided fee is insufficient
    error InsufficientFee();
    /// @notice Provided fee is below minimum limit
    error MinimumFeeLimit();
    /// @notice Allowance is not sufficient for the transfer
    error InsufficientAllowance();
    /// @notice Token is already registered
    error TokenAlreadyRegistered();
    /// @notice The caller is not authorized to perform this action
    error UnauthorizedSender();
    /// @notice Bridge is paused and the action cannot be performed
    error BridgePaused();
    /// @notice Deposit amount exceeds configured limit
    error DepositLimitBreached();
    /// @notice Token transfer failed
    error TransferFailed();
    /// @notice Deposit of native currency failed
    error DepositFailed();
    /// @notice The chain id is already registered
    error ChainIdAlreadyRegistered();
    /// @notice The chain id is not registered
    error ChainIdNotRegistered();
    /// @notice Maximum allowed amount is reached
    error MaxAmountReached();
    /// @notice Outgoing bridged amount limit for token is reached
    error OutGoingBridgeAmountLimitForTokenIsReached(uint64 _toChainId, address _tokenAddr, uint64 _finalAmount);
}
