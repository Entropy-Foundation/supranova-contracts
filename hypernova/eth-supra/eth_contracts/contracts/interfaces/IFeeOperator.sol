// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

import "./ITokenBridgeService.sol";
import "./ISupraSValueFeed.sol";
/// @title Fee Operator Interface
/// @notice Defines the external API for computing bridge fees and managing fee configurations.
/// @dev Implemented by an upgradeable Fee Operator behind an ERC1967 proxy.
interface IFeeOperator {
    struct FeeConfig {
        /// @notice Whether the fee configuration is enabled for a chain
        bool enabled;
        // GasCost in Quants = gas_used * gas_unit_price => u64 * u64 => uint128 is enough. But In percentage calculaiton it might get oeverflowed. So, using u256
        /// @notice Committee updater gas cost in quants
        uint256 rg;
        /// @notice Relayer reward margin (basis points, base 1e4)
        uint64 rm;
        /// @notice Service fee margin (basis points, base 1e4)
        uint64 sm;
        
        /// @notice Threshold amount in USDT for micro tier
        uint64 tierMicroUSDT;
        // In between is tierStandard
        /// @notice Threshold amount in USDT for whale tier
        uint128 tierWhaleUSDT;

        /// @notice Percentage (basis points) for micro tier
        uint64 tierMicroPercentage;
        /// @notice Percentage (basis points) for standard tier
        uint64 tierStandardPercentage;
        /// @notice Percentage (basis points) for whale tier
        uint64 tierWhalePercentage;
    }
    /// @notice Emitted when the Fee Operator pause state changes
    /// @param owner The admin performing the update
    /// @param paused True if paused, false otherwise
    event FeeOperatorPauseState(address indexed owner, bool paused);
    /// @notice Emitted when the token bridge fee config is added or updated
    /// @param admin The admin performing the update
    /// @param param1 The updated fee configuration
    event UpdatedTBFeeConfig(address indexed admin, FeeConfig param1);
    /// @notice Emitted when the admin address is updated
    /// @param owner The caller performing the update (previous admin)
    /// @param admin The newly set admin address
    event UpdatedAdmin(address indexed owner,address admin);
    /// @notice Emitted when the Hypernova address is updated
    /// @param owner The admin performing the update
    /// @param hypernova The new Hypernova contract address
    event UpdatedHypernova(address indexed owner,address hypernova);
    /// @notice Emitted when the S-Value feed address or pair index is updated
    /// @param owner The admin performing the update
    /// @param sValueFeed The new S-Value feed contract address
    /// @param supraUsdtPairIndex The new SUPRA/USDT pair index
    event UpdatedSValueFeed(address indexed owner, address sValueFeed, uint256 supraUsdtPairIndex);

    /// @notice Initializes the Fee Operator (called once via proxy)
    /// @param _admin Admin address
    /// @param _hypernova Hypernova contract address
    /// @param _sValueFeed S-Value feed contract address
    /// @param supraUsdtPairIndex SUPRA/USDT pair index in the S-Value feed
    function initialize(
        address _admin,
        address _hypernova,
        address _sValueFeed,
        uint256 supraUsdtPairIndex
    ) external;
    /// @notice Updates the admin address
    /// @param _admin New admin address
    function setAdmin(address _admin) external;
    /// @notice Pauses or unpauses the Fee Operator
    /// @param _isPaused True to pause, false to unpause
    function changeState(bool _isPaused) external;
    /// @notice Updates the Hypernova contract address
    /// @param _hypernova New Hypernova contract address
    function setHypernova(address _hypernova) external;
    /// @notice Updates the S-Value feed and pair index
    /// @param _sValueFeed New S-Value feed contract address
    /// @param supraUsdtPairIndex New SUPRA/USDT pair index
    function setSValueFeed(address _sValueFeed, uint256 supraUsdtPairIndex) external;
    /// @notice Adds or updates the fee configuration for a destination chain
    /// @param enabled Whether the configuration is enabled
    /// @param toChaiID Destination chain id
    /// @param rg Relayer gas cost in quants
    /// @param rm Relayer margin (basis points)
    /// @param sm Service margin (basis points)
    /// @param tierMicroUSDT Threshold for micro tier in USDT
    /// @param tierWhaleUSDT Threshold for whale tier in USDT
    /// @param tierMicroPercentage Fee percentage for micro tier (basis points)
    /// @param tierStandardPercentage Fee percentage for standard tier (basis points)
    /// @param tierWhalePercentage Fee percentage for whale tier (basis points)
    function addOrUpdateTBFeeConfig(
        bool enabled,
        uint64 toChaiID, 
        uint256 rg, 
        uint64 rm, 
        uint64 sm,
        uint64 tierMicroUSDT,
        uint128 tierWhaleUSDT,
        uint64 tierMicroPercentage,
        uint64 tierStandardPercentage,
        uint64 tierWhalePercentage
    ) external;
    
    /// @notice Returns fee configuration for a destination chain
    /// @param toChainId Destination chain id
    /// @return FeeConfig The current configuration
    function getTBFeeConfig(uint64 toChainId) external view returns (IFeeOperator.FeeConfig memory);
    /// @notice Computes the fee details for a given amount and token info
    /// @param toChainId Destination chain id
    /// @param amount Amount to bridge (source token decimals)
    /// @param _tokenInfo Registered token info
    /// @return finalAmount Amount after service fee (u64)
    /// @return feeCutToService Service fee amount (u64)
    /// @return relayerRewardInBridgedAsset Relayer reward in bridged asset (u64)
    /// @return dust Amount not transferred due to decimal normalization
    function getFeeDetails(uint64 toChainId, uint256 amount, ITokenBridgeService.TokenInfo memory _tokenInfo) external view returns (uint64 finalAmount, uint64 feeCutToService, uint64 relayerRewardInBridgedAsset, uint256 dust);
    /// @notice Computes relayer reward from parameters
    /// @param v Value parameter from Hypernova config
    /// @param rg Gas cost in quants
    /// @param rm Relayer margin (basis points)
    /// @return rr Relayer reward (u64)
    function computeRelayerReward(uint64 v, uint256 rg, uint64 rm) external pure returns (uint64);
    /// @notice Computes service fee for a transfer
    /// @param amount Amount to bridge (source token decimals)
    /// @param tokenAmountInUsdt Amount in USDT
    /// @param relayerRewardInBridgedAsset Relayer reward in bridged asset units
    /// @param _tbFeeConfig Fee configuration
    /// @return s Service fee amount
    function computeServiceFee(uint256 amount, uint256 tokenAmountInUsdt, uint256 relayerRewardInBridgedAsset, FeeConfig memory _tbFeeConfig) external pure returns (uint256);
    /// @notice Returns Hypernova contract interface
    function getHypernova() external view returns (IHypernova);
    /// @notice Returns the S-Value feed interface and pair index
    function getSValueFeed() external view returns (ISupraSValueFeed, uint256 supraUsdtPairIndex);
    /// @notice Upgrades the Fee Operator implementation behind the proxy
    /// @param newImplementation Address of the new implementation
    /// @return Address of the new implementation
    function upgradeImplementation(address newImplementation) external returns (address);
    /// @notice Returns the current implementation address used by the proxy
    function getImplementationAddress() external view returns (address);
    /// @notice Basis points base used for percentages (1e4)
    function PERCENTAGE_BASE() external view returns (uint64);
    /// @notice Normalization decimals constant used for price conversion
    function NORMALIZED_DECIMALS() external view returns (uint64);
    /// @notice Converts relayer reward in SUPRA to USDT value
    /// @param relayerRewardInSupra Relayer reward in SUPRA (u64)
    /// @return relayerRewardInUsdt Value in USDT
    function getRelayerRewardInUsdt(uint64 relayerRewardInSupra) external view returns (uint256 relayerRewardInUsdt);
    /// @notice Computes amount in USDT and relayer reward in bridged asset using Uniswap pool ratios
    /// @param uniPriceOracle Uniswap V3 pool address
    /// @param amount Amount of tokens (source decimals)
    /// @param isBridgeTokenBaseToken Whether the token is pool's token0
    /// @param relayerRewardInUsdt Relayer reward in USDT
    /// @return tokenAmountInUsdt Equivalent amount in USDT
    /// @return relayerRewardInBridgedAsset Relayer reward in bridged asset units
    function getAmountInUsdtAndtRelayerRewardInBridgedAsset(address uniPriceOracle, uint256 amount, bool isBridgeTokenBaseToken, uint256 relayerRewardInUsdt) external view returns (uint256 tokenAmountInUsdt, uint256 relayerRewardInBridgedAsset);
    /// @notice Whether the Fee Operator is paused
    function checkIsFeeOperatorPaused() external view returns(bool);
    /// @notice Returns admin address
    function admin() external view returns(address);

}