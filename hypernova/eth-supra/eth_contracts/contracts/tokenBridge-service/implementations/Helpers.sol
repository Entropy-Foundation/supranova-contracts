// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

import "contracts/tokenBridge-service/implementations/State.sol";
import "contracts/interfaces/IHypernova.sol";
import "contracts/interfaces/IFeeOperator.sol";
import "contracts/interfaces/IVault.sol";
import {ISupraSValueFeed} from "contracts/interfaces/ISupraSValueFeed.sol";
import "contracts/tokenBridge-service/implementations/Errors.sol";
import {ERC1967Utils} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol"; //@dev: Library
/// @title Token Bridge Helper utilities
/// @notice Internal helpers, getters and modifiers used by the token bridge implementation.
/// @dev Exposes view functions that are part of the `ITokenBridgeService` API.
contract Helpers is State, Errors {
    /// @dev Sets the admin address, reverts on zero address
    function _setAdmin(address _admin) internal {
        if (_admin != address(0)) {
            admin = _admin;
        } else revert InvalidInput();
    }

    /// @notice Restricts caller to admin only
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert UnauthorizedSender();
        }
        _;
    }

    /// @notice Reverts when bridge is paused
    modifier isNotPaused() {
        if (isPaused) {
            revert BridgePaused();
        }
        _;
    }
    /// @dev Sets the Hypernova contract address
    function _setHypernova(address _hypernova) internal {
        if (checkZeroAddr(_hypernova)) revert InvalidInput();
        hypernova = _hypernova;
    }
    /// @dev Sets the fee operator contract address
    function _setFeeOperator(address _feeOperatorContract) internal {
        if (checkZeroAddr(_feeOperatorContract)) revert InvalidInput();
        feeOperatorContract = _feeOperatorContract;
    }
    /// @dev Sets the wrapped native token address
    function _setNativeToken(address _nativeToken) internal {
        if (checkZeroAddr(_nativeToken)) revert InvalidInput();
        nativeToken = _nativeToken;
    }
    /// @dev Sets the vault contract address
    function _setVault(address _vault) internal {
        if (checkZeroAddr(_vault)) revert InvalidInput();
        vault = _vault;
    }

    /// @dev Updates per-token bridged total and ensures it stays within uint64 range
    function _updateBridgedAmountPerToken(uint64 _toChainId, address _tokenAddr, uint64 _finalAmount) internal {
        uint256 currentAmount = bridgedAmountPerToken[_toChainId][_tokenAddr];
        if ((currentAmount + _finalAmount) > type(uint64).max) {
            revert OutGoingBridgeAmountLimitForTokenIsReached(_toChainId, _tokenAddr, _finalAmount);
        }
        bridgedAmountPerToken[_toChainId][_tokenAddr] = currentAmount + _finalAmount;
    }

    /// @notice Returns the Hypernova contract interface
    function getHypernova() public view returns (IHypernova){
        return IHypernova(hypernova);
    }
    /// @notice Returns the vault contract interface
    function getVault() public view returns(IVault){
        return IVault(vault);
    }
    /// @notice Returns the fee operator contract interface
    function getFeeOperator() public view returns (IFeeOperator) {
        return IFeeOperator(feeOperatorContract);
    }
    /// @notice Returns the wrapped native token address
    function getNativeToken() public view returns (address) {
        return nativeToken;
    }
    /// @notice Returns the current implementation address used by the proxy
    function getImplementationAddress() public view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @notice Whether the token is registered for a given destination chain
    function isTokenRegistered(uint64 chainId, address tokenAddr) public view returns (bool) {
        return supportedTokens[chainId][tokenAddr].isRegistered;
    }

    /// @notice Whether the destination chain id is registered
    function isToChainIdRegistered(uint64 chainId) public view returns(bool){
        return supportedChains[chainId];
    }
    /// @notice Returns registered token information for a destination chain
    function getRegisteredTokenInfo(uint64 chainId, address tokenAddr) public view returns (ITokenBridgeService.TokenInfo memory) {
        return supportedTokens[chainId][tokenAddr];
    }

    /// @notice Computes fee breakdown via FeeOperator
    function computeFeeDetails(uint64 _toChainId, uint256 _amount, ITokenBridgeService.TokenInfo memory _tokenInfo) public view returns (uint64 finalAmount, uint64 feeCutToService, uint64 relayerReward, uint256 dust){
        (finalAmount, feeCutToService, relayerReward, dust) = getFeeOperator().getFeeDetails(_toChainId, _amount, _tokenInfo);
    }

    /// @notice Computes fee details for a given amount and token address
    function getFeeForAmount(uint64 _toChainId, uint256 _amount, address _tokenAddr) public view returns (uint64 finalAmount, uint64 feeCutToService, uint64 relayerReward, uint256 dust){
        ITokenBridgeService.TokenInfo memory tokenInfo = getRegisteredTokenInfo(_toChainId, _tokenAddr);
        if (!tokenInfo.isRegistered) {
            revert TokenNotRegistered();
        }
        // Enough Fee and Amount check is done in FeeOperator
        (finalAmount, feeCutToService, relayerReward, dust) = computeFeeDetails(_toChainId, _amount, tokenInfo);
    }
    /// @notice Returns whether the bridge is paused
    function checkIsTokenBridgePaused() public view returns(bool) {
        return isPaused;
    }
    /// @dev Helper to check zero uint
    function checkZeroValue(uint256 value) internal pure returns (bool) {
        return value == 0;
    }

    /// @dev Helper to check zero address
    function checkZeroAddr(address value) internal pure returns (bool) {
        return value == address(0);
    }

    /// @dev Helper to check zero bytes32
    function checkZeroBytes32(bytes32 value) internal pure returns (bool) {
        return value == bytes32(0);
    }
}
