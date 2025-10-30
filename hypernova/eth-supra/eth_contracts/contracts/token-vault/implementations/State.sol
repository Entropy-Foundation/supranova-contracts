// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

import "contracts/interfaces/IVault.sol";
contract State {
    /// @notice Address with administrative permissions over the vault
    address public admin;
    /// @dev Global pause flag to stop lock/release operations
    bool isPaused;
    /// @dev Whether release operations are enabled
    bool releaseEnabled;
    /// @dev Token bridge contract authorized to call lock/release
    address tokenBridgeContract;
    /// @dev Delay in seconds before an admin withdrawal can be executed
    uint256 adminWithdrawDelay;
    /// @dev Next nonce to be used for admin withdrawals
    uint256 withdrawNonce;

    /// @dev Mapping of delayed transfers by identifier
    mapping(bytes32 => IVault.DelayedTransfer) adminTransfers;
    /// @dev Per-token lock limits
    mapping(address => IVault.LockLimit) lockLimits;
    /// @dev Per-token release limits
    mapping(address => IVault.ReleaseLimit) releaseLimits;
    /// @dev Amount of each token currently locked in the vault
    mapping(address => uint256) lockedTokens;
}
