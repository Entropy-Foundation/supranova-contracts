// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity ^0.8.20;

import {ITokenBridgeService} from "../../contracts/interfaces/ITokenBridgeService.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";

contract TBsendNative is Script {

    ITokenBridgeService public tb = ITokenBridgeService(0x7cECd42A15A691EF693512b1D508F1465ec5DA16);
    function run() public {
        vm.startBroadcast();
        address WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        bytes32 receiverAddr = bytes32(0xc73f79b50794d6f0d7e5bceebea64afcb7717cb221f00a85b056dd649ab750ff);
        bytes32 payload = bytes32("Hello!");
        uint64 supraChaiId = 8;
        uint256 amount = 0.0001 ether;
        for (uint i = 0; i<1; i++) {
            // Sending ETH
            tb.sendNative{value: amount}(receiverAddr, amount, payload, supraChaiId);

            // Sending WETH
            // IWETH(WETH9).approve(address(tb), amount);
            // tb.sendTokens(WETH9, amount, receiverAddr, payload, supraChaiId);

            // Sending USDC
            // IWETH(USDC).approve(address(tb), amount);
            // tb.sendTokens(USDC, amount, receiverAddr, payload, supraChaiId);
            // revert();
        }
        vm.stopBroadcast();
    }
}
