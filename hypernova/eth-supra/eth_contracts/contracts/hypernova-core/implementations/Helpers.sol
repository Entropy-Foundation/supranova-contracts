// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

import "contracts/hypernova-core/implementations/State.sol";
import "contracts/hypernova-core/implementations/Errors.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

/// @title Hypernova Helper utilities
/// @notice Internal helpers, getters and math for the Hypernova implementation.
/// @dev Exposes view/pure functions that are part of the `IHypernova` API.
contract Helpers is State, Errors {
    /// @dev Sets the admin address, reverts on zero address
    function _setAdmin(address _admin) internal {
        if (_admin != address(0)) {
            admin = _admin;
        } else revert InvalidInput();
    }
    /// @dev Sets the initial message id
    function _setInitialMsgId(uint256 _msgId) internal {
        msgId = _msgId;
    }

    /// @notice Restricts caller to admin only
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert UnauthorizedSender();
        }
        _;
    }
    /// @notice Reverts when Hypernova is paused
    modifier isNotPaused() {
        if (isPaused) {
            revert HNBridgePaused();
        }
        _;
    }
    /**  V = (CUR / X)  / (1 - VM) 
     * 
     * @param cr - committee updater rewards in Quants
     * @param x - traffic to hn-core (unpredictable, add a realistic value)
     * @param vm - hn margin of verification fee
     *      
     *   V = (CUR / X)  / (1 - VM)
     *      CUR = CUR_in_quants
     *      X = HN traffic in one sync period 
     *        => X = 10
     *      VM = (V - CUR)/V
     *         => VM = 10% => 0.1
     * 
     * returns - 
     */
    /// @notice Computes verification fee V (reverts if invalid inputs)
    function computeVerificationFee(uint64 cr, uint64 x, uint64 vm) public pure returns (uint64) {
        if (checkZeroValue(cr) || checkZeroValue(x)) revert InvalidInput();
        if (!isValidMargin(vm)) revert InvalidMargin();
        if (!isValidTrafficX(x, cr)) revert XCannotBeMore();
        return _computeVerificationFee(cr, x, vm);
    }
    /// @dev Internal verification fee computation
    function _computeVerificationFee(uint64 cr, uint64 x, uint64 vm) internal pure returns (uint64 v) {
        uint256 _v = FullMath.mulDiv((cr / x), PERCENTAGE_BASE, (PERCENTAGE_BASE - vm));
        if (_v > type(uint64).max) revert InvalidVComputation(_v);
        v = uint64(_v);
    }
    /** CUR = CUG / (1 - CUM)
     * 
     * @param cg - committee updater gas cost in Quants: (gasUnits * gasPrice) in $Quants (8 decimals)
     * @param cm - committee updater margin
     *      CUG = Gas Units * Gas Price => CUG in Quants => CUG in Quants
     *      Gas Units = 558 + 139 + 858 = 1555
     *      Gas Price = 100 quants
     *      CUG in Quants = 155500 quants
     *     
     *       CUR = CUG / (1 - CUM)
     *       CUG = CUG_in_supra
     *       CUM = (CUR - CUG)/CUR 
     *           => CUM = 10% => 0.1
     * returns - CUR in $Quants (8 decimals)
     */
    /// @notice Computes committee updater reward CR (reverts if invalid inputs)
    function computeCUreward(uint256 cg, uint64 cm) public pure returns (uint64) {
        if (checkZeroValue(cg)) revert InvalidInput();
        if (!isValidMargin(cm)) revert InvalidMargin();
        return _computeCUreward(cg, cm);
    }
    /// @dev Internal CU reward computation
    function _computeCUreward(uint256 cg, uint64 cm) internal pure returns (uint64 cr) {
        uint256 _cr = FullMath.mulDiv(cg, PERCENTAGE_BASE, (PERCENTAGE_BASE - cm));
        if (_cr > type(uint64).max) revert InvalidCRComputation(_cr);
        cr = uint64(_cr);
    }

    /// @notice Returns the current implementation address used by the proxy
    function getImplementationAddress() public view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @notice Upgrades the implementation behind the proxy to `newImplementation`
    function upgradeImplementation(
        address newImplementation
    ) external onlyAdmin returns (address) {
        if (newImplementation == address(0)) revert InvalidInput();
        ERC1967Utils.upgradeToAndCall(newImplementation, "");
        return newImplementation;
    }
    function getNextMsgId() external view returns (uint256) {
       return msgId;
    }

    /// @dev Helper to check zero uint
    function checkZeroValue(uint256 value) internal pure returns (bool) {
        return value == 0;
    }

    /// @dev Helper to validate a margin value in basis points
    function isValidMargin(uint64 value) internal pure returns (bool) {
        return value < PERCENTAGE_BASE;
    }

    /// @dev Helper to validate traffic parameter relative to CR
    function isValidTrafficX(uint64 x, uint256 cr) internal pure returns (bool) {
        return x <= cr; 
        
    }
}
