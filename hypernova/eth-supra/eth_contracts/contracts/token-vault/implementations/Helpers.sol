// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

import "contracts/token-vault/implementations/Errors.sol";
import "contracts/token-vault/implementations/State.sol";
import "contracts/interfaces/IVault.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";


/// @title Token Vault Helper utilities
/// @notice Internal helpers, getters and modifiers used by the vault implementation.
/// @dev Exposes some view functions which are part of the `IVault` public API.
contract Helpers is State, Errors {

    /// @notice Restricts caller to admin only
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert UnauthorizedSender();
        }
        _;
    }
    /// @notice Reverts when vault is paused
    modifier isNotPaused() {
        if (isPaused) {
            revert VaultPaused();
        }
        _;
    }

    /// @notice Restricts caller to the configured token bridge contract
    modifier onlyBridge() {
        if (msg.sender != tokenBridgeContract) {
            revert UnauthorizedSender();
        }
        _;
    }

    /// @notice Reverts when release operations are disabled
    modifier isReleaseEnabled() {
        if (!releaseEnabled) {
            revert ReleaseDisabled();
        }
        _;
    }
    /// @dev Sets the admin address, reverts on zero address
    function _setAdmin(address _admin) internal {
        if (_admin != address(0)) {
            admin = _admin;
        } else revert InvalidInput();
    }
    /// @dev Sets the token bridge service address, reverts on zero address
    function _setTokenBridgeService(address _tokenBridgeContract) internal {
        if (_tokenBridgeContract != address(0)) {
            tokenBridgeContract = _tokenBridgeContract;
        } else revert InvalidInput();
    }

    /// @dev Sets the admin withdrawal delay, reverts on zero
    function _setAdminWithdrawDelay(uint256 _delay) internal {
        if (_delay != 0) {
            adminWithdrawDelay = _delay;
        } else revert InvalidInput();
    }

    /// @notice Enables or disables release operations
    function changeReleaseState(bool _releaseEnabled) external onlyAdmin {
        releaseEnabled = _releaseEnabled;
    }
    /// @dev Registers a new delayed transfer and increments the nonce
    function _addTransfer(address token, uint256 amount, address to ) internal returns (bytes32, uint256) {
        uint256 _withdrawNonce = getNextWithdrawNonce(); 
        bytes32 id = getId(token, amount, to, _withdrawNonce);
        adminTransfers[id] = IVault.DelayedTransfer({
            amount: amount,
            to: to,
            token: token,
            nonce: _withdrawNonce,
            timestamp: block.timestamp,
            isAdded: true
        });

        withdrawNonce = _withdrawNonce + 1;
        return (id, _withdrawNonce);
    }
    /// @notice Computes a unique identifier for a delayed admin withdrawal
    function getId(address token, uint256 amount, address to, uint256 _withdrawNonce) public view returns (bytes32 id) {
        id = keccak256(
            abi.encodePacked(token, amount, to, _withdrawNonce, block.timestamp)
        );
    }

    /// @notice Returns the next withdrawal nonce
    function getNextWithdrawNonce() public view returns (uint256){
        return withdrawNonce;
    }

    /// @notice Reads configured lock limits for a token
    function getLockLimits(
        address token
    ) public view returns (uint256, uint256, uint256) {
        IVault.LockLimit memory lockLimit= lockLimits[token];
        return (lockLimit.min, lockLimit.max, lockLimit.globalMax);
    }

    /// @notice Reads configured release limits for a token
    function getReleaseLimits(
        address token
    ) public view returns (uint256, uint256) {
        IVault.ReleaseLimit memory releaseLimit= releaseLimits[token];
        return (releaseLimit.min, releaseLimit.max);
    }

    /// @dev Validates a per-operation amount is within [min, max]
    function isValidLimit(uint256 amount, uint256 min, uint256 max) internal pure returns (bool) {
        return (amount >= min && amount <= max);
    }
    /// @dev Validates cumulative amount does not exceed globalMax unless globalMax == 0
    function isValidGlobalLimit(uint256 amount, uint256 globalMax) internal pure returns (bool) {
        return (amount < globalMax || globalMax == 0);
    }

    /// @notice Returns the token bridge contract address authorized to lock/release
    function getTokenBridgeContract() public view returns (address) {
        return tokenBridgeContract;
    }

    /// @notice Returns how many tokens of a type are currently locked
    function getLockedTokenBalance(address token) public view returns (uint256) {
        return lockedTokens[token];
    }

    /// @notice Returns details of a scheduled admin withdrawal
    function getAdminTransfers(bytes32 id) public view returns (IVault.DelayedTransfer memory) {
        return adminTransfers[id];
    }

    /// @notice Returns the configured delay for admin withdrawals
    function getAdminWithdrawDelay() public view returns (uint256) {
        return adminWithdrawDelay;
    }

    /// @notice Returns whether the vault is paused
    function checkIsVaultPaused() external view returns(bool){
        return isPaused;
    }
    /// @notice Returns the current implementation address used by the proxy
    function getImplementationAddress() public view returns (address) {
        return ERC1967Utils.getImplementation();
    }
}
