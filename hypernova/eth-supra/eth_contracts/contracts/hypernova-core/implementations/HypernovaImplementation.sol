// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

// import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "contracts/hypernova-core/implementations/Helpers.sol";
import "../../interfaces/IHypernova.sol";

/// @title Hypernova Implementation
/// @notice Posts cross-chain messages and manages per-chain Hypernova configuration.
/// @dev Upgradeable via ERC1967 proxy. Fulfills `IHypernova` interface.
contract HypernovaImplementation is Initializable, Helpers {
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the admin and initial message id
    function initialize(address _admin, uint256 _msgId) public initializer {
        _setAdmin(_admin);
        _setInitialMsgId(_msgId);
    }
    /// @notice Updates the admin address
    function setAdmin(address _admin) external onlyAdmin {
        _setAdmin(_admin);
        emit IHypernova.UpdatedAdmin(msg.sender, _admin);
    }
    /// @notice Posts a message to a destination chain
    function postMessage(bytes memory messageData, uint64 toChainId) external isNotPaused {
        if (!getHNConfig(toChainId).enabled) revert UnsupportedToChain();
        emit IHypernova.MessagePosted(
            msg.sender,
            msgId,
            toChainId,
            messageData
        );
        msgId++;
    }

    /** Adding a toChainID, Updating and computing fees
     * 
     * @param enabled - is toChainID is registered
     * @param toChaiID - destination chain id
     * @param cg - committee updater gas cost in $Quant : (gasUnits * gasPrice) in $Quant
     * @param cm - committee updater margin
     * @param vm - hn margin of verification fee
     * @param x - traffic to hn-core (unpredictable, add a realistic value)
     */
    /// @notice Adds or updates per-chain Hypernova configuration and computes derived values
    function addOrUpdateHNConfig(
        bool enabled,
        uint64 toChaiID,
        uint256 cg,
        uint64 cm,
        uint64 vm,
        uint64 x
    ) public onlyAdmin {
        if (checkZeroValue(toChaiID) || checkZeroValue(cg) || checkZeroValue(x)) revert InvalidInput();
        if (!isValidMargin(vm) || !isValidMargin(cm) ) revert InvalidMargin();

        uint64 cr = _computeCUreward(cg, cm);
        if (!isValidTrafficX(x, cr)) revert XCannotBeMore();
        uint64 v = _computeVerificationFee(cr, x, vm);

        IHypernova.HNConfig storage _hnConfig = hnConfig[toChaiID];
        _hnConfig.enabled = enabled;
        _hnConfig.cg = cg;
        _hnConfig.cm = cm;
        _hnConfig.vm = vm;
        _hnConfig.x = x;
        _hnConfig.v = v;
        _hnConfig.cr = cr;
        emit IHypernova.UpdatedHNConfig(msg.sender, _hnConfig);
    }
    
    /// @notice Returns Hypernova config for a destination chain
    function getHNConfig(uint64 toChainId) public view returns (IHypernova.HNConfig memory){
        return hnConfig[toChainId];
    }

    /// @notice Pauses or unpauses Hypernova
    function changeState(bool _isPaused) external onlyAdmin {
        isPaused = _isPaused;
        emit IHypernova.HNBridgePauseState(msg.sender, _isPaused);
    }

    /// @notice Returns whether Hypernova is paused
    function checkIsHypernovaPaused() public view returns(bool) {
        return isPaused;
    }
}
