// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs


pragma solidity 0.8.22;

/// @title Token Vault Interface
/// @notice Defines the external API for the Token Vault that locks/release ERC-20 (and wrapped native) tokens.
/// @dev Implemented by the upgradeable `VaultImplementation` behind an `ERC1967Proxy`.
interface IVault {
    /// @notice Per-token limits applied when locking tokens into the vault
    /// @dev `globalMax == 0` disables the global cumulative cap for that token
    struct LockLimit {
        /// @notice Minimum amount allowed per single lock
        uint256 min;
        /// @notice Maximum amount allowed per single lock
        uint256 max;
        /// @notice Maximum cumulative amount allowed to be locked (0 = no cap)
        uint256 globalMax;
    }

    /// @notice Per-token limits applied when releasing tokens from the vault
    struct ReleaseLimit {
        /// @notice Minimum amount allowed per single release
        uint256 min;
        /// @notice Maximum amount allowed per single release
        uint256 max;
    }

    /// @notice Data about an administrator-initiated delayed transfer
    struct DelayedTransfer {
        /// @notice Amount to transfer
        uint256 amount;
        /// @notice Recipient address
        address to;
        /// @notice Token address to transfer
        address token;
        /// @notice Monotonic identifier for admin withdrawals
        uint256 nonce;
        /// @notice Timestamp at which the withdrawal was scheduled
        uint256 timestamp;
        /// @notice Flag indicating whether it is currently registered
        bool isAdded;
    }

    /// @notice Emitted when the admin address is updated
    /// @param owner The caller that performed the update (previous admin)
    /// @param admin The newly set admin address
    event UpdatedAdmin(address indexed owner,address admin);

    /// @notice Emitted when tokens are locked
    /// @param tokenAddr The ERC-20 or wrapped native token address
    /// @param amount The amount locked
    event Locked(address indexed tokenAddr, uint256 indexed amount);

    /// @notice Emitted when tokens are released to a recipient
    /// @param to The recipient address
    /// @param tokenAddr The token address being released
    /// @param amount The amount released
    event Released(address indexed to, address indexed tokenAddr, uint256 indexed amount);

    /// @notice Emitted when an admin withdrawal is added (scheduled)
    /// @param id Unique identifier of the scheduled withdrawal
    /// @param token Token address to withdraw
    /// @param to Recipient address for the withdrawal
    /// @param amount Amount to withdraw
    /// @param withdrawNonce Withdrawal nonce at the time of scheduling
    /// @param timestamp Timestamp when the withdrawal was scheduled
    event AdminWithdrawAdded(bytes32 indexed id, address indexed token, address indexed to, uint256 amount, uint256 withdrawNonce, uint256 timestamp);

    /// @notice Emitted when a scheduled admin withdrawal is removed (canceled)
    /// @param id Unique identifier of the scheduled withdrawal
    /// @param token Token address of the scheduled withdrawal
    /// @param to Recipient address of the scheduled withdrawal
    /// @param amount Amount of the scheduled withdrawal
    /// @param withdrawNonce Withdrawal nonce of the scheduled withdrawal
    /// @param timestamp Timestamp when the withdrawal was canceled
    event AdminWithdrawRemoved(bytes32 indexed id, address indexed token, address indexed to, uint256 amount, uint256 withdrawNonce, uint256 timestamp);

    /// @notice Emitted when a scheduled admin withdrawal is executed
    /// @param id Unique identifier of the executed withdrawal
    /// @param token Token address withdrawn
    /// @param to Recipient address receiving the tokens
    /// @param amount Amount withdrawn
    /// @param withdrawNonce Withdrawal nonce of the executed withdrawal
    /// @param timestamp Block timestamp when the withdrawal was executed
    event AdminWithdrawExecuted(bytes32 indexed id,address indexed token, address indexed to, uint256 amount, uint256 withdrawNonce, uint256 timestamp);
    
    /// @notice Initializes the vault implementation. Should be called once via proxy.
    /// @dev Sets admin, the token bridge contract and admin withdrawal delay.
    /// @param _admin Address of the admin who controls configuration and withdrawals
    /// @param _tokenBridgeService Address of the token bridge service authorized to lock/release
    /// @param _delay Delay in seconds before an admin withdrawal can be executed
    function initialize(
        address _admin,
        address _tokenBridgeService,
        uint256 _delay
    ) external;

    /// @notice Updates the admin address
    /// @param _admin The new admin address
    function setAdmin(address _admin) external;

    /// @notice Pauses or unpauses the vault
    /// @param _isPaused True to pause, false to unpause
    function changeState(bool _isPaused) external;

    /// @notice Enables or disables release operations
    /// @param _withdrawEnabled True to enable release, false to disable
    function changeReleaseState(bool _withdrawEnabled) external;

    /// @notice Schedules an admin withdrawal with delay
    /// @param token Token address to withdraw
    /// @param amount Amount to withdraw
    /// @param to Recipient of the withdrawal
    /// @return id The unique identifier of the scheduled withdrawal
    function addAdminWithdraw(address token, uint256 amount, address to) external returns (bytes32);

    /// @notice Cancels a previously scheduled admin withdrawal
    /// @param id Identifier of the scheduled withdrawal to cancel
    /// @return id The same identifier for confirmation
    function removeAddedAdminWithdraw(bytes32 id) external returns (bytes32);

    /// @notice Executes a scheduled admin withdrawal after the configured delay
    /// @param id Identifier of the scheduled withdrawal to execute
    function execAdminWithdraw(bytes32 id) external;

    /// @notice Sets the token bridge contract authorized to lock/release
    /// @param _tokenBridgeContract The token bridge service contract address
    function setTokenBridgeContract(address _tokenBridgeContract) external;

    /// @notice Upgrades the implementation logic behind the proxy
    /// @param newImplementation Address of the new implementation contract
    /// @return The same `newImplementation` address
    function upgradeImplementation(address newImplementation) external returns (address);

    /// @notice Sets per-token lock limits
    /// @dev All input arrays must be the same length. `globalMaxLimits[i] == 0` disables the global cap for that token.
    /// @param tokens Token addresses
    /// @param minLimits Minimum per-lock amounts
    /// @param maxLimits Maximum per-lock amounts
    /// @param globalMaxLimits Global maximum cumulative locked amounts (0 = no cap)
    function setLockLimits(address[] calldata tokens, uint256[] calldata minLimits, uint256[] calldata maxLimits, uint256[] calldata globalMaxLimits) external;

    /// @notice Sets per-token release limits
    /// @dev All input arrays must be the same length.
    /// @param tokens Token addresses
    /// @param minLimits Minimum per-release amounts
    /// @param maxLimits Maximum per-release amounts
    function setReleaseLimits(address[] calldata tokens, uint256[] calldata minLimits, uint256[] calldata maxLimits) external;

    /// @notice Locks ERC-20 tokens into the vault
    /// @param tokenAddr Token address to lock
    /// @param amount Amount to lock
    function lockTokens(address tokenAddr, uint256 amount) external;

    /// @notice Locks native currency by wrapping it, then locking the wrapped token
    /// @param tokenAddr Wrapped native token address (e.g. WETH)
    /// @param amount Amount of native currency sent and locked
    function lockNative(address tokenAddr, uint256 amount) external payable;

    /// @notice Releases tokens to a recipient
    /// @param token Token address to release
    /// @param amount Amount to release
    /// @param to Recipient address
    function release(address token,  uint256 amount, address to) external;

    /// @notice Returns the current implementation address used by the proxy
    /// @return The implementation contract address
    function getImplementationAddress() external view returns (address);

    /// @notice Reads configured lock limits for a token
    /// @param token Token address
    /// @return min The minimum per-lock amount
    /// @return max The maximum per-lock amount
    /// @return globalMax The global cumulative cap (0 = no cap)
    function getLockLimits(address token) external view returns (uint256, uint256, uint256);

    /// @notice Reads configured release limits for a token
    /// @param token Token address
    /// @return min The minimum per-release amount
    /// @return max The maximum per-release amount
    function getReleaseLimits(address token) external view returns (uint256, uint256);

    /// @notice Returns the token bridge contract address authorized to lock/release
    /// @return The token bridge contract address
    function getTokenBridgeContract() external view returns (address);

    /// @notice Returns how many tokens of a type are currently locked
    /// @param token Token address
    /// @return The locked balance for the token
    function getLockedTokenBalance(address token) external view returns (uint256);

    /// @notice Returns whether the vault is paused
    /// @return True if paused, false otherwise
    function checkIsVaultPaused() external view returns(bool);

    /// @notice Computes a unique identifier for a delayed admin withdrawal
    /// @param token Token address
    /// @param amount Amount
    /// @param to Recipient address
    /// @param _withdrawNonce Withdrawal nonce
    /// @return id The computed identifier
    function getId(address token, uint256 amount, address to, uint256 _withdrawNonce) external view returns (bytes32 id);

    /// @notice Returns the next withdrawal nonce
    /// @return The next withdrawal nonce value
    function getNextWithdrawNonce() external view returns (uint256);

    /// @notice Returns details of a scheduled admin withdrawal
    /// @param id Identifier of the scheduled withdrawal
    /// @return The stored `DelayedTransfer` struct
    function getAdminTransfers(bytes32 id) external view returns (IVault.DelayedTransfer memory);

    /// @notice Returns the configured delay for admin withdrawals
    /// @return Delay in seconds
    function getAdminWithdrawDelay() external view returns (uint256);

    /// @notice Returns the current admin address
    /// @return The admin address
    function admin() external view returns (address);
}
