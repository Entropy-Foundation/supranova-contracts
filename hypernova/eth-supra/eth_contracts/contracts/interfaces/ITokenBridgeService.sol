// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;
import {IHypernova} from "./IHypernova.sol";
import {IFeeOperator} from "./IFeeOperator.sol";
/// @title Token Bridge Service Interface
/// @notice Defines the external API for bridging tokens and native value across chains via Hypernova.
/// @dev Implemented by an upgradeable Token Bridge contract behind an ERC1967 proxy.
interface ITokenBridgeService {

    // Events
    /// @notice Emitted when the admin address is updated
    /// @param owner The caller performing the update (previous admin)
    /// @param admin The newly set admin address
    event UpdatedAdmin(address indexed owner,address admin);
    /// @notice Emitted when the Hypernova address is updated
    /// @param owner The admin performing the update
    /// @param hypernova The new Hypernova contract address
    event UpdatedHypernova(address indexed owner,address hypernova);
    /// @notice Emitted when the Vault address is updated
    /// @param owner The admin performing the update
    /// @param vault The new vault contract address
    event UpdatedVault(address indexed owner,address vault);
    /// @notice Emitted when the FeeOperator address is updated
    /// @param owner The admin performing the update
    /// @param relayOperator The new FeeOperator contract address
    event UpdatedFeeOperator(address indexed owner, address relayOperator);
    /// @notice Emitted when the wrapped native token address is updated
    /// @param owner The admin performing the update
    /// @param nativeToken The new wrapped native token (e.g. WETH)
    event UpdatedNativeToken(address indexed owner,address nativeToken);
    /// @notice Emitted when a token (and associated pool) is registered/unregistered for a target chain
    /// @param owner The admin performing the update
    /// @param toChainId The destination chain id
    /// @param tokenAddr The token address on the source chain
    /// @param registered True if registering, false if unregistering
    /// @param uniswapPool The Uniswap V3 pool used for price/ratio reference
    /// @param isBaseToken Whether the token is the pool's token0
    /// @param isFixedFee Whether the token uses fixed fees
    /// @param fixedServiceFee Fixed service fee (if isFixedFee is true)
    /// @param fixedRelayerReward Fixed relayer reward (if isFixedFee is true)
    event TokenRegistered(
        address indexed owner,
        uint64 toChainId,
        address tokenAddr,
        bool registered,
        address uniswapPool,
        bool isBaseToken,
        bool isFixedFee,
        uint256 fixedServiceFee,
        uint256 fixedRelayerReward
    );
    /// @notice Emitted when a destination chain registration status is changed
    /// @param owner The admin performing the update
    /// @param toChainId The destination chain id
    /// @param status The new registration status
    event ToChainRegistered(address indexed owner, uint256 toChainId, bool status);
    /// @notice Emitted when the bridge pause state changes
    /// @param owner The admin performing the update
    /// @param paused True if paused, false otherwise
    event TokenBridgePauseState(address indexed owner, bool paused);
    
    // Structs
    /// @notice Payload posted to Hypernova describing a bridge transfer
    struct MessageData {
        /// @notice Encoded sender address (address cast into bytes32)
        bytes32 senderAddr;
        /// @notice Encoded token address (address cast into bytes32)
        bytes32 tokenAddress;
        /// @notice Source chain id
        uint64 sourceChainId;
        /// @notice Optional payload passed through to the destination
        bytes32 payload;
        /// @notice Amount to be minted/released on destination after fees
        uint64 finalAmount;
        /// @notice Portion of fee allocated to the bridge service
        uint64 feeCutToService;
        /// @notice Relayer reward paid for delivery
        uint64 relayerReward;
        /// @notice Encoded receiver address on the destination
        bytes32 receiverAddr;
    }
    /// @notice Registered token settings for a destination chain
    struct TokenInfo {
        /// @notice Whether the token is currently registered for the destination chain
        bool isRegistered;
        /// @notice Uniswap V3 pool address used for pricing
        address uniswapPool;
        /// @notice Whether the token is the pool's token0
        bool isBaseToken;
        /// @notice Decimal scaling rate to normalize to MAX_ALLOWED_SUPRA_WRAPPED_FA_DECIMALS
        uint256 decimalRate;
        /// @notice Whether the token uses fixed fees instead of dynamic pricing
        bool isFixedFee;
        /// @notice Fixed service fee (used when isFixedFee is true)
        uint256 fixedServiceFee;
        /// @notice Fixed relayer reward (used when isFixedFee is true)
        uint256 fixedRelayerReward;
    }

    // Functions
    /// @notice Initializes the bridge implementation (called once via proxy)
    /// @param _hypernova Hypernova contract address
    /// @param _admin Admin address
    /// @param _feeOperator Fee operator contract address
    /// @param _vaultAddr Token vault contract address
    /// @param _nativeToken Wrapped native token address (e.g. WETH)
    function initialize(
        address _hypernova,
        address _admin,
        address _feeOperator,
        address _vaultAddr,
        address _nativeToken
    ) external;
    /// @notice Updates the admin address
    /// @param _admin New admin address
    function setAdmin(address _admin) external;
    /// @notice Sets the Hypernova contract address
    /// @param _hypernova New Hypernova contract address
    function setHypernova(address _hypernova) external ;
    /// @notice Sets the vault contract address
    /// @param _vault New vault address
    function setVault(address _vault) external;
    /// @notice Sets the fee operator contract address
    /// @param _feeOperator New fee operator address
    function setFeeOperator(address _feeOperator) external;
    /// @notice Sets the wrapped native token address
    /// @param _nativeToken New wrapped native token address
    function setNativeToken(address _nativeToken) external;
    /// @notice Returns the current admin address
    function admin() external view returns (address);
    /// @notice Pauses or unpauses the bridge
    /// @param _isPaused True to pause, false to unpause
    function changeState(bool _isPaused) external;
    /// @notice Upgrades the bridge implementation behind the proxy
    /// @param newImplementation Address of the new implementation
    function upgradeImplementation(address newImplementation) external;
    /// @notice Registers or unregisters a destination chain id
    /// @param _toChainId Destination chain id
    /// @param _registered True to register, false to unregister
    function registerChainId(uint64 _toChainId, bool _registered) external;
    /// @notice Registers a token with a fixed fee, to fetch the fee statically
    /// @param _toChainId Destination chain id
    /// @param tokenAddr Token address on source chain
    /// @param _fixedServiceFee Fixed service fee (in source token decimals)
    /// @param _fixedRelayerReward Fixed relayer reward
    /// @param _register True to register, false to unregister
    function registerTokenWithFixedFee(uint64 _toChainId, address tokenAddr, uint256 _fixedServiceFee, uint256 _fixedRelayerReward, bool _register) external;
    
    /// @notice Registers a token with a uniswap pool, to fetch the fee dynamically via the pool
    /// @param _toChainId Destination chain id
    /// @param tokenAddr Token address on source chain
    /// @param _uniswapPool Uniswap V3 pool address for the pair
    /// @param _register True to register, false to unregister
    function registerTokenWithDynamicFee(uint64 _toChainId, address tokenAddr, address _uniswapPool, bool _register) external;
    /// @notice Bridges ERC-20 tokens to a destination chain
    /// @param tokenAddr Token address on source chain
    /// @param amount Amount to transfer (before fees)
    /// @param receiverAddr Encoded receiver address on destination
    /// @param payload Optional payload forwarded to destination
    /// @param toChainId Destination chain id
    function sendTokens(address tokenAddr, uint256 amount, bytes32 receiverAddr, bytes32 payload, uint64 toChainId) external;
    /// @notice Bridges native currency to a destination chain
    /// @param receiverAddr Encoded receiver address on destination
    /// @param amount Amount to transfer (must equal msg.value)
    /// @param payload Optional payload forwarded to destination
    /// @param toChainId Destination chain id
    function sendNative(bytes32 receiverAddr, uint256 amount, bytes32 payload, uint64 toChainId) external payable;

    /// @notice Returns the current implementation address used by the proxy
    function getImplementationAddress() external view returns (address); 
    /// @notice Returns the Hypernova contract interface
    function getHypernova() external view returns (IHypernova);
    /// @notice Returns the FeeOperator contract interface
    function getFeeOperator() external view returns (IFeeOperator);
    /// @notice Returns the vault contract address
    function getVault() external view returns(address);
    /// @notice Returns the wrapped native token address
    function getNativeToken() external view returns (address);
    /// @notice Whether the token is registered for a given destination chain
    /// @param chainId Destination chain id
    /// @param tokenAddr Token address
    function isTokenRegistered(uint64 chainId, address tokenAddr) external view returns (bool);
    /// @notice Whether the destination chain id is registered
    /// @param chainId Destination chain id
    function isToChainIdRegistered(uint64 chainId) external view returns(bool);
    /// @notice Returns registered token information for a destination chain
    /// @param chainId Destination chain id
    /// @param tokenAddr Token address
    /// @return TokenInfo The token information
    function getRegisteredTokenInfo(uint64 chainId, address tokenAddr) external view returns (ITokenBridgeService.TokenInfo memory);
    /// @notice Computes fee breakdown and dust for a given amount and token info
    /// @param _toChainId Destination chain id
    /// @param _amount Amount to bridge
    /// @param _tokenInfo Registered token information
    /// @return finalAmount Amount after fees
    /// @return feeCutToService Fee allocated to the service
    /// @return relayerReward Reward allocated to relayer
    /// @return dust Amount not transferred due to decimal rounding
    function computeFeeDetails(uint64 _toChainId, uint256 _amount, ITokenBridgeService.TokenInfo memory _tokenInfo) external view returns (uint64 finalAmount, uint64 feeCutToService, uint64 relayerReward, uint256 dust);
    /// @notice Whether the token bridge is paused
    function checkIsTokenBridgePaused() external view returns(bool);
    /// @notice Computes fee details for a given amount and token address
    /// @param _toChainId Destination chain id
    /// @param _amount Amount to bridge
    /// @param _tokenAddr Token address
    /// @return finalAmount Amount after fees
    /// @return feeCutToService Fee allocated to the service
    /// @return relayerReward Reward allocated to relayer
    /// @return dust Amount not transferred due to decimal rounding
    function getFeeForAmount(uint64 _toChainId, uint256 _amount, address _tokenAddr) external view returns (uint64 finalAmount, uint64 feeCutToService, uint64 relayerReward, uint256 dust);

    /// @notice Max decimals allowed for Supra-wrapped FA tokens
    function MAX_ALLOWED_SUPRA_WRAPPED_FA_DECIMALS() external view returns (uint8);
}