// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

import {ITokenBridgeService} from "../../interfaces/ITokenBridgeService.sol";

contract State {
    /// @notice Max decimals allowed for Supra-wrapped FA tokens
    uint8 public constant MAX_ALLOWED_SUPRA_WRAPPED_FA_DECIMALS = 8;
    /// @notice Address with administrative control over the bridge
    address public admin;
    /// @dev Hypernova messaging contract address
    address hypernova;
    /// @dev Fee operator contract address
    address feeOperatorContract;
    /// @dev Token vault contract address
    address vault;
    /// @dev Wrapped native token address (e.g., WETH)
    address nativeToken;
    /// @dev Global pause flag for the bridge
    bool isPaused;
    /// @dev Per-destination-chain registered token info
    mapping(uint64 _toChainId => mapping(address => ITokenBridgeService.TokenInfo)) public supportedTokens;
    /// @dev Registered destination chains
    mapping(uint64 => bool) public supportedChains;
    /// @dev Total bridged amount per token per destination chain (uint256 for safety, enforced to uint64 range)
    mapping(uint64 _toChainId => mapping(address tokenAddr=> uint256)) public bridgedAmountPerToken;
}
