// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "contracts/tokenBridge-service/implementations/Helpers.sol";
import "contracts/interfaces/ITokenBridgeService.sol";
import "contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title Token Bridge Implementation
/// @notice Bridges ERC-20 and native assets using Hypernova messages with fee accounting.
/// @dev Upgradeable via ERC1967 proxy. Uses `ITokenBridgeService` interface.
contract TokenBridgeImplementation is Initializable, Helpers, ReentrancyGuard {
    using SafeERC20 for IERC20;
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes Hypernova, admin, fee operator, vault and wrapped native token
    function initialize(
        address _hypernova,
        address _admin,
        address _feeOperator,
        address _vaultAddr,
        address _nativeToken
    ) public initializer {
        _setFeeOperator(_feeOperator);
        _setAdmin(_admin);
        _setNativeToken(_nativeToken);
        _setVault(_vaultAddr);
        _setHypernova(_hypernova);
    }

    /// @notice Updates the admin address
    function setAdmin(address _admin) external onlyAdmin {
        _setAdmin(_admin);
        emit ITokenBridgeService.UpdatedAdmin(msg.sender, _admin);
    }
    /// @notice Updates the Hypernova contract address
    function setHypernova(address _hypernova) external onlyAdmin {
        _setHypernova(_hypernova);
        emit ITokenBridgeService.UpdatedHypernova(msg.sender, _hypernova);
    }

    /// @notice Updates the fee operator contract address
    function setFeeOperator(address _feeOperator) external onlyAdmin {
        _setFeeOperator(_feeOperator);
        emit ITokenBridgeService.UpdatedFeeOperator(msg.sender, _feeOperator);
    }

    /// @notice Updates the vault contract address
    function setVault(address _vault) external onlyAdmin {
        _setVault(_vault);
        emit ITokenBridgeService.UpdatedVault(msg.sender, _vault);
    }

    /// @notice Updates the wrapped native token address
    function setNativeToken(address _nativeToken) external onlyAdmin {
        _setNativeToken(_nativeToken);
        emit ITokenBridgeService.UpdatedNativeToken(msg.sender, _nativeToken);
    }
    function _registerTokenImpl(uint64 _toChainId, address tokenAddr, address _uniswapPool, bool _isFixedFee, uint256 _fixedServiceFee, uint256 _fixedRelayerReward, bool _register) internal {
        if (checkZeroAddr(tokenAddr)) revert InvalidInput();
        if (!isToChainIdRegistered(_toChainId)) {
            revert ChainIdNotRegistered();
        }

        ITokenBridgeService.TokenInfo storage tokenInfo = supportedTokens[_toChainId][tokenAddr];
        bool _isBaseToken;

        if (_uniswapPool != address(0)) { // uniswap is specified
            if (IUniswapV3Pool(_uniswapPool).token0() == tokenAddr) {
                _isBaseToken = true;
            }
        }

        (, bytes memory queriedDecimals) = tokenAddr.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 originalDecimals = abi.decode(queriedDecimals, (uint8));
        uint256 _decimalRate = originalDecimals > MAX_ALLOWED_SUPRA_WRAPPED_FA_DECIMALS
            ? 10 ** (originalDecimals - MAX_ALLOWED_SUPRA_WRAPPED_FA_DECIMALS)
            : 1;

        tokenInfo.isRegistered = _register;
        tokenInfo.uniswapPool = _uniswapPool;
        tokenInfo.isBaseToken = _isBaseToken;
        tokenInfo.decimalRate = _decimalRate;
        tokenInfo.isFixedFee = _isFixedFee;
        tokenInfo.fixedServiceFee = _fixedServiceFee;
        tokenInfo.fixedRelayerReward = _fixedRelayerReward;

        emit ITokenBridgeService.TokenRegistered(
            msg.sender, _toChainId, tokenAddr, _register, _uniswapPool, _isBaseToken,
            _isFixedFee, _fixedServiceFee, _fixedRelayerReward
        );
    }
    /// @notice Registers a token with a fixed fee, to fetch the fee statically
    /// @param _toChainId Destination chain id
    /// @param tokenAddr Token address on source chain
    /// @param _fixedServiceFee Fixed service fee (in source token decimals)
    /// @param _fixedRelayerReward Fixed relayer reward
    /// @param _register True to register, false to unregister
    function registerTokenWithFixedFee(uint64 _toChainId, address tokenAddr, uint256 _fixedServiceFee, uint256 _fixedRelayerReward, bool _register) external onlyAdmin {
        _registerTokenImpl(_toChainId, tokenAddr, address(0), true, _fixedServiceFee, _fixedRelayerReward, _register);
    }
    /// @notice Registers a token with a uniswap pool, to fetch the fee dynamically via the pool
    /// @param _toChainId Destination chain id
    /// @param tokenAddr Token address on source chain
    /// @param _uniswapPool Uniswap V3 pool address for the pair
    /// @param _register True to register, false to unregister
    function registerTokenWithDynamicFee(uint64 _toChainId, address tokenAddr, address _uniswapPool, bool _register) external onlyAdmin {
        if (checkZeroAddr(_uniswapPool)) revert InvalidInput();
        _registerTokenImpl(_toChainId, tokenAddr, _uniswapPool, false, 0, 0, _register);
    }

    /// @notice Registers or unregisters a destination chain id
    function registerChainId(uint64 _toChainId, bool _registered) external onlyAdmin {
        if (checkZeroValue(_toChainId)) revert InvalidInput();
        bool registered = supportedChains[_toChainId];
        if (registered && _registered) revert ChainIdAlreadyRegistered();
        if (!registered && !_registered) revert ChainIdNotRegistered();
        supportedChains[_toChainId] = _registered;
        emit ITokenBridgeService.ToChainRegistered(msg.sender, _toChainId, _registered);
    }


    /// @notice Bridges ERC-20 tokens to a destination chain
    /// @param tokenAddr Token address on source chain
    /// @param amount Amount to transfer (before fees)
    /// @param receiverAddr Encoded receiver address on destination
    /// @param payload Optional payload forwarded to destination
    /// @param toChainId Destination chain id
    function sendTokens(
        address tokenAddr,
        uint256 amount,
        bytes32 receiverAddr,
        bytes32 payload,
        uint64 toChainId
    ) external isNotPaused nonReentrant {
        if (
            checkZeroAddr(tokenAddr) ||
            checkZeroBytes32(receiverAddr) ||
            checkZeroValue(amount) ||
            checkZeroValue(toChainId)
        ) {
            revert InvalidInput();
        }
        if (!isToChainIdRegistered(toChainId)) {
            revert ChainIdNotRegistered();
        }
        ITokenBridgeService.TokenInfo memory tokenInfo = getRegisteredTokenInfo(toChainId, tokenAddr);
        if (!tokenInfo.isRegistered) {
            revert TokenNotRegistered();
        }

        // Enough Fee check is done in FeeOperator
        (uint64 finalAmount, uint64 feeCutToService, uint64 relayerReward, uint256 dust) = computeFeeDetails(toChainId, amount, tokenInfo);
        _updateBridgedAmountPerToken(toChainId, tokenAddr, finalAmount);

        // Verify token transfer by checking vault balance before and after
        uint256 transferAmount = amount - dust;
        uint256 vaultBalanceBefore = IERC20(tokenAddr).balanceOf(vault);
        IERC20(tokenAddr).safeTransferFrom(msg.sender, vault, transferAmount);
        uint256 vaultBalanceAfter = IERC20(tokenAddr).balanceOf(vault);
        
        // Ensure the vault received exactly the expected amount
        if (vaultBalanceAfter - vaultBalanceBefore != transferAmount) {
            revert TransferFailed();
        }
        
        getVault().lockTokens(tokenAddr, transferAmount);

        ITokenBridgeService.MessageData memory _messageData = ITokenBridgeService.MessageData({
            senderAddr: bytes32(uint256(uint160(msg.sender))),
            tokenAddress: bytes32(uint256(uint160(tokenAddr))),
            sourceChainId: uint64(block.chainid),
            payload: payload,
            finalAmount: finalAmount,
            feeCutToService: feeCutToService,
            relayerReward: relayerReward,
            receiverAddr: receiverAddr
        });

        bytes memory messageData = abi.encode(_messageData);
        getHypernova().postMessage(messageData, toChainId);
    }

    /// @notice Bridges native currency to a destination chain
    /// @param receiverAddr Encoded receiver address on destination
    /// @param amount Amount to transfer (must equal msg.value)
    /// @param payload Optional payload forwarded to destination
    /// @param toChainId Destination chain id
    function sendNative(
        bytes32 receiverAddr,
        uint256 amount,
        bytes32 payload,
        uint64 toChainId
    ) external payable isNotPaused nonReentrant {
        uint256 msgValue = msg.value;
        address _nativeToken = nativeToken;
        if (checkZeroBytes32(receiverAddr) || 
            checkZeroValue(toChainId) || 
            checkZeroValue(amount)) 
        revert InvalidInput();

        if (msgValue != amount) revert IncorrectAmount();

        if (!isToChainIdRegistered(toChainId)) {
            revert ChainIdNotRegistered();
        }

        ITokenBridgeService.TokenInfo memory tokenInfo = getRegisteredTokenInfo(toChainId, _nativeToken);
        if (!tokenInfo.isRegistered) {
            revert TokenNotRegistered();
        }

        // Enough Fee and Amount check is done in FeeOperator
        (uint64 finalAmount, uint64 feeCutToService, uint64 relayerReward, uint256 dust) = computeFeeDetails(toChainId, msgValue, tokenInfo);

        _updateBridgedAmountPerToken(toChainId, _nativeToken, finalAmount);

        getVault().lockNative{value: msgValue - dust}(_nativeToken, msgValue - dust);
        // refund dust
        if (dust > 0) {
            payable(msg.sender).transfer(dust);
        }

        ITokenBridgeService.MessageData memory _messageData = ITokenBridgeService.MessageData({
            senderAddr: bytes32(uint256(uint160(msg.sender))),
            tokenAddress: bytes32(uint256(uint160(_nativeToken))),
            sourceChainId: uint64(block.chainid),
            payload: payload,
            finalAmount: finalAmount,
            feeCutToService: feeCutToService,
            relayerReward: relayerReward,
            receiverAddr: receiverAddr
        });

        bytes memory messageData = abi.encode(_messageData);
        getHypernova().postMessage(messageData, toChainId);
    }
    /// @notice Upgrades the implementation behind the proxy to `newImplementation`
    function upgradeImplementation(
        address newImplementation
    ) external onlyAdmin returns (address) {
        if (checkZeroAddr(newImplementation)) revert InvalidInput();
        ERC1967Utils.upgradeToAndCall(newImplementation, "");
        return newImplementation;
    }

    /// @notice Pauses or unpauses the bridge
    function changeState(bool _isPaused) external onlyAdmin {
        isPaused = _isPaused;
        emit ITokenBridgeService.TokenBridgePauseState(msg.sender, _isPaused);
    }
}
