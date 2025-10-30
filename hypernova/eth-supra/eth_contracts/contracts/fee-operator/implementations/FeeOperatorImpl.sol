// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "contracts/fee-operator/implementations/Helpers.sol";
import "../../interfaces/IFeeOperator.sol";
import "../../interfaces/ITokenBridgeService.sol";

/*  
    CUR = CUG / (1 - CUM)
    V = (CUR / X)  / (1 - VM) 
    RR = (V + RG) / (1 - RM)
    S = RR / (1 - SM)
    
    CUG and RG to absolute values.
    Compute CUR, V, RR and S using CUM = 10%, RM = 20%, VM = 10% (Example values)
*/
/// @title Fee Operator Implementation
/// @notice Computes bridge fees and maintains per-chain fee configurations.
/// @dev Upgradeable via ERC1967 proxy. Fulfills `IFeeOperator` interface.
contract FeeOperatorImpl is Initializable, Helpers {
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes admin, hypernova and S-Value feed
    function initialize(address _admin, address _hypernova, address _sValueFeed, uint256 _supraUsdtPairIndex)
        public
        initializer
    {
        _setAdmin(_admin);
        _setHypernova(_hypernova);
        _setSValueFeed(_sValueFeed, _supraUsdtPairIndex);
    }

    /// @notice Updates the admin address
    function setAdmin(address _admin) external onlyAdmin {
        _setAdmin(_admin);
        emit IFeeOperator.UpdatedAdmin(msg.sender, _admin);
    }

    /// @notice Updates the Hypernova contract address
    function setHypernova(address _hypernova) external onlyAdmin {
        _setHypernova(_hypernova);
        emit IFeeOperator.UpdatedHypernova(msg.sender, _hypernova);
    }

    /// @notice Updates the S-Value feed contract and pair index
    function setSValueFeed(address _sValueFeed, uint256 _supraUsdtPairIndex) external onlyAdmin {
        _setSValueFeed(_sValueFeed, _supraUsdtPairIndex);
        emit IFeeOperator.UpdatedSValueFeed(msg.sender, _sValueFeed, _supraUsdtPairIndex);
    }

    /// @notice Adds or updates the fee configuration for a destination chain
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
    ) public onlyAdmin {
        // Not checking rm, sm because the margins can be 0
        if (
            checkZeroValue(toChaiID) || checkZeroValue(rg) || checkZeroValue(tierMicroUSDT)
                || checkZeroValue(tierWhaleUSDT)
        ) revert InvalidInput();
        if (!isValidMargin(rm) || !isValidMargin(sm)) revert InvalidMargin();
        if (
            !isValidPercentage(tierMicroPercentage) || !isValidPercentage(tierStandardPercentage)
                || !isValidPercentage(tierWhalePercentage)
        ) revert InvalidPercentage();

        IFeeOperator.FeeConfig storage feeConfig = feeConfigs[toChaiID];
        feeConfig.enabled = enabled;
        feeConfig.rg = rg;
        feeConfig.rm = rm;
        feeConfig.sm = sm;
        feeConfig.tierMicroUSDT = tierMicroUSDT;
        feeConfig.tierWhaleUSDT = tierWhaleUSDT;
        feeConfig.tierMicroPercentage = tierMicroPercentage;
        feeConfig.tierStandardPercentage = tierStandardPercentage;
        feeConfig.tierWhalePercentage = tierWhalePercentage;

        emit IFeeOperator.UpdatedTBFeeConfig(msg.sender, feeConfig);
    }

    /// @notice Returns fee configuration for a destination chain
    function getTBFeeConfig(uint64 toChainId) public view isNotPaused returns (IFeeOperator.FeeConfig memory) {
        return feeConfigs[toChainId];
    }
    /// @notice Computes the fee details for a given amount and token info
    function getFeeDetails(uint64 toChainId, uint256 amount, ITokenBridgeService.TokenInfo memory _tokenInfo) public view isNotPaused returns (uint64 finalAmount, uint64 feeCutToService, uint64 relayerRewardInBridgedAsset, uint256 dust)
    {
        if (checkZeroValue(amount)) revert InvalidInput();
        if (!_tokenInfo.isRegistered) revert TokenNotRegistered();

        IHypernova.HNConfig memory hypernovaConfig = getHypernova().getHNConfig(toChainId);
        IFeeOperator.FeeConfig memory tbFeeConfig = getTBFeeConfig(toChainId);
        if (!hypernovaConfig.enabled) revert HNConfigIsNotEnabled();
        if (!tbFeeConfig.enabled) revert FeeConfigIsNotEnabled();
        uint64 relayerRewardInSupra = _computeRelayerReward(hypernovaConfig.v, tbFeeConfig.rg, tbFeeConfig.rm);
        uint256 relayerRewardInUsdt = getRelayerRewardInUsdt(relayerRewardInSupra);

        uint256 serviceFeesAsset;
        uint256 relayerFeesAsset;
        if (_tokenInfo.isFixedFee) {
            // fixed fee model
            serviceFeesAsset = _tokenInfo.fixedServiceFee;
            relayerFeesAsset = _tokenInfo.fixedRelayerReward;
        }else {
            (uint256 tokenAmountInUsdt, uint256 _relayerRewardInBridgedAsset) = getAmountInUsdtAndtRelayerRewardInBridgedAsset(_tokenInfo.uniswapPool, amount, _tokenInfo.isBaseToken, relayerRewardInUsdt);
            serviceFeesAsset = _computeServiceFee(amount, tokenAmountInUsdt, _relayerRewardInBridgedAsset, tbFeeConfig);
            relayerFeesAsset = _relayerRewardInBridgedAsset;
        }

        uint256 normalizedFeeCutToService = normalizeDecimals(serviceFeesAsset, _tokenInfo.decimalRate);
        if (!isSafeToCastToU64(normalizedFeeCutToService)) revert InvalidSValue(normalizedFeeCutToService); // "Service fee is too higher than the wrapped bridged asset supply (u64)")
        feeCutToService = uint64(normalizedFeeCutToService);

        uint256 normalizedRelayerRewardInBridgedAsset = normalizeDecimals(relayerFeesAsset, _tokenInfo.decimalRate);
        if (!isSafeToCastToU64(normalizedRelayerRewardInBridgedAsset)) revert InvalidRRinBridgedAssetValue(normalizedRelayerRewardInBridgedAsset); //"Relayer reward is too higher than the wrapped bridged asset supply (u64)")
        relayerRewardInBridgedAsset = uint64(normalizedRelayerRewardInBridgedAsset);

        uint256 normalizedAmount = normalizeDecimals(amount, _tokenInfo.decimalRate);
        if (normalizedFeeCutToService >= normalizedAmount) revert InsufficientAmount(normalizedAmount, normalizedFeeCutToService, normalizedRelayerRewardInBridgedAsset);

        uint256 normalizedFinalAmount = normalizedAmount - normalizedFeeCutToService;
        if (!isSafeToCastToU64(normalizedFinalAmount)) revert InvalidAmountValue(normalizedFinalAmount);
        finalAmount = uint64(normalizedFinalAmount);

        dust = amount - deNormalizeDecimals(normalizedAmount, _tokenInfo.decimalRate);
    }

    /// @notice Pauses or unpauses the Fee Operator
    function changeState(bool _isPaused) external onlyAdmin {
        isPaused = _isPaused;
        emit IFeeOperator.FeeOperatorPauseState(msg.sender, _isPaused);
    }

    /// @notice Returns whether the Fee Operator is paused
    function checkIsFeeOperatorPaused() public view returns (bool) {
        return isPaused;
    }
}
