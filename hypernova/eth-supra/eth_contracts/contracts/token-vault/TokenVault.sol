// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol"; //@dev: Library

/// @title TokenVault Proxy
/// @notice Minimal ERC1967 proxy that delegates calls to `VaultImplementation`.
/// @dev The constructor wires the initial implementation and optional initialization calldata.
contract TokenVault is ERC1967Proxy {
    /// @notice Deploy the proxy and optionally initialize the implementation
    /// @param _implementationAddr Address of the implementation contract
    /// @param _data Initialization calldata to be delegatecalled on the implementation. Pass empty bytes to skip.
    constructor(address _implementationAddr, bytes memory _data) 
    ERC1967Proxy(_implementationAddr, _data)
    {}
}