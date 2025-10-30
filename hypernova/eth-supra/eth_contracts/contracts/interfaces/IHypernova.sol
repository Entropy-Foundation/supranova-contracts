// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

/// @title Hypernova Messaging Interface
/// @notice Defines the external API for posting cross-chain messages and managing Hypernova config.
interface IHypernova {
    /// @notice Emitted when the Hypernova pause state changes
    /// @param owner The admin performing the update
    /// @param paused True if paused, false otherwise
    event HNBridgePauseState(
        address indexed owner,
        bool paused
    );
    /// @notice Emitted when a message is posted
    /// @param caller The sender that posted the message
    /// @param messageId The sequential message id
    /// @param toChainId The destination chain id
    /// @param messageData The opaque message payload
    event MessagePosted(
        address indexed caller,
        uint256 indexed messageId,
        uint64 indexed toChainId,
        bytes messageData
    );
    
    /// @notice Emitted when the admin address is updated
    /// @param owner The caller performing the update (previous admin)
    /// @param admin The newly set admin address
    event UpdatedAdmin(address indexed owner,address admin);
    /// @notice Emitted when Hypernova config is added or updated
    /// @param admin The admin performing the update
    /// @param param1 The config that was updated
    event UpdatedHNConfig(address indexed admin, HNConfig param1);

    /// @notice Per-chain Hypernova configuration
    struct HNConfig {
        /// @notice Whether the chain is enabled
        bool enabled;
        /// @notice Committee updater margin (basis points)
        uint64 cm;
        /// @notice Hypernova verification fee margin (basis points)
        uint64 vm;
        // GasCost in Quants = gas_used * gas_unit_price => u64 * u64 => uint128 is enough. But In percentage calculaiton it might get oeverflowed. So, using u256
        /// @notice Committee updater gas cost in quants
        uint256 cg;
        // cr is rewarded in supra, supra balance transactions done in u64. (Max supra supply 100 billion)
        /// @notice Committee updater reward in SUPRA (u64)
        uint64 cr;
        // x is the traffic in a day to hypernova u64 seems fine
        /// @notice Estimated traffic parameter for the chain
        uint64 x;
        // V charged in supra, supra balance transactions done in u64. (Max supra supply 100 billion)
        /// @notice Verification fee V in SUPRA (u64)
        uint64 v;
    }
    
    /// @notice Initializes Hypernova (called once via proxy)
    /// @param _admin Admin address
    /// @param _msgId Initial message id
    function initialize(address _admin, uint256 _msgId) external;
    /// @notice Pauses or unpauses Hypernova
    /// @param _isPaused True to pause, false to unpause
    function changeState(bool _isPaused) external;
    /// @notice Updates the admin address
    /// @param _admin New admin address
    function setAdmin(address _admin) external;
    /// @notice Posts a message to a destination chain
    /// @param messageData Encoded message payload
    /// @param toChainId Destination chain id
    function postMessage(bytes memory messageData, uint64 toChainId) external;
    /// @notice Adds or updates per-chain Hypernova configuration
    /// @param enabled Whether the chain is enabled
    /// @param toChaiID Destination chain id
    /// @param cg Committee updater gas cost in quants
    /// @param cm Committee updater margin (basis points)
    /// @param vm Verification fee margin (basis points)
    /// @param x Traffic parameter
    function addOrUpdateHNConfig(
        bool enabled,
        uint64 toChaiID,
        uint256 cg,
        uint64 cm,
        uint64 vm,
        uint64 x
    ) external ;
    /// @notice Returns Hypernova config for a destination chain
    /// @param toChainId Destination chain id
    /// @return HNConfig The configuration
    function getHNConfig(uint64 toChainId) external view returns (HNConfig memory);
    /// @notice Returns the current implementation address used by the proxy
    function getImplementationAddress() external view returns (address);
    /// @notice Upgrades the Hypernova implementation behind the proxy
    /// @param newImplementation Address of the new implementation
    /// @return Address of the new implementation
    function upgradeImplementation(address newImplementation) external returns (address);
    /// @notice Returns the next message id
    function getNextMsgId() external view returns (uint256);
    /// @notice Computes verification fee V
    /// @param cr Committee updater reward in SUPRA
    /// @param x Traffic parameter
    /// @param vm Verification fee margin (basis points)
    /// @return v Verification fee in SUPRA (u64)
    function computeVerificationFee(uint64 cr, uint64 x, uint64 vm) external pure returns (uint64);
    /// @notice Computes committee updater reward CR
    /// @param cg Committee updater gas cost in quants
    /// @param cm Committee updater margin (basis points)
    /// @return cr Committee updater reward in SUPRA (u64)
    function computeCUreward(uint256 cg, uint64 cm) external pure returns (uint64);
    /// @notice Basis points base used for percentages (1e4)
    function PERCENTAGE_BASE() external view returns (uint64);
    /// @notice Whether Hypernova is paused
    function checkIsHypernovaPaused() external view returns(bool);
    /// @notice Returns admin address
    function admin() external view returns(address);
}
