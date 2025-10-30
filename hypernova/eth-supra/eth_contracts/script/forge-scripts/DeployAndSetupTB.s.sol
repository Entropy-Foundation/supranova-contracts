// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

import "../../lib/forge-std/src/Script.sol";
import {console} from "../../lib/forge-std/src/console.sol";
// Interfaces
import {IVault} from "contracts/interfaces/IVault.sol";
import {ITokenBridgeService} from "contracts/interfaces/ITokenBridgeService.sol";

// Proxy contracts
import {TokenBridge} from "contracts/tokenBridge-service/TokenBridge.sol";
import {TokenVault} from "contracts/token-vault/TokenVault.sol";

// Implekentation contracts
import {TokenBridgeImplementation} from "contracts/tokenBridge-service/implementations/TokenBridgeImplementation.sol";
import {VaultImplementation} from "contracts/token-vault/implementations/VaultImplementation.sol";


contract DeployAndSetupTB is Script {
    uint256 public constant DELAY = 1 hours;
    address public constant HYPERNOVA_CORE = 0x50888Fc24e1224E12f5C8a31310A47B98b2A7f75;
    address public constant FEE_OPERATOR = 0x350b2276a639aa51957cd921A9d94B4c42Da0446;
    address public constant ADMIN_TB = 0x6C027e024FA9a869F331279816b121d3d3C95491;
    address public constant ADMIN_V = 0x6C027e024FA9a869F331279816b121d3d3C95491;
    address public constant WETH9 = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;


    TokenBridge public tokenBridgeProxy;
    TokenVault public tokenVaultProxy;

    TokenBridgeImplementation public tokenBridgeImplementation;
    VaultImplementation public vaultImplementation;

    ITokenBridgeService public tokenBridge;
    IVault public tokenVault;

    function run() public {
        deployTB(
            HYPERNOVA_CORE,
            ADMIN_TB,
            ADMIN_V,
            FEE_OPERATOR,
            WETH9,
            DELAY
        );       

        // Comment out the following if the ADMIN is mutlisig
        // vm.startBroadcast();
        // uint256 min = 1;
        // uint256 max = type(uint256).max;
        // uint256 globalMax = 200 ether;
        // adminVaultSetup(min, max, globalMax, address(WETH9));
        // uint64 toChainId = 6;
        // bool enableToChain = true;
        // address tokenAddr = WETH9;
        // address _uniswapPool = address(0x3289680dD4d6C10bb19b899729cda5eEF58AEfF1);
        // bool _register = true;
        // adminTBSetup(
        //     toChainId, 
        //     enableToChain, 
        //     tokenAddr, 
        //     _uniswapPool,
        //     _register
        // );
        // vm.stopBroadcast();
    }

    function deployTB(
        address _hypernova, 
        address _admin, 
        address _adminVault,
        address _feeOperator,   
        address _weth, 
        uint256 _delay
    ) public 
    returns (ITokenBridgeService, IVault)
    {
        vm.startBroadcast();
        // Deploying implementations
        tokenBridgeImplementation = new TokenBridgeImplementation();
        vaultImplementation = new VaultImplementation();
        console.log("TokenBridgeImplementation: %s", address(tokenBridgeImplementation));
        console.log("VaultImplementation: %s", address(vaultImplementation));

        // Deploying proxy contracts
        tokenBridgeProxy = new TokenBridge(address(tokenBridgeImplementation), "");
        tokenVaultProxy = new TokenVault(address(vaultImplementation), "");
        tokenBridge = ITokenBridgeService(address(tokenBridgeProxy));
        tokenVault = IVault(address(tokenVaultProxy));
        require(address(tokenBridge) != address(0), "tokenBridge: Deployment Failed");
        require(address(tokenVault) != address(0), "tokenVault: Deployment Failed");

        console.log("tokenBridgeProxy : ", address(tokenBridge));
        console.log("vaultProxy : ", address(tokenVault));

        // Initializing implementations
        tokenBridge.initialize(
            _hypernova,
            _admin,
            _feeOperator,
            address(tokenVault),
            _weth
        );
        require(address(tokenBridge.admin()) == _admin, "tokenBridge: Initialise failed");
        tokenVault.initialize(
            _adminVault,
            address(tokenBridge),
            _delay
        );
        require(tokenVault.admin() == _adminVault, "tokenVault: Initialise failed");
        vm.stopBroadcast();
        return (tokenBridge, tokenVault);
    }

    function adminVaultSetup(uint256 min, uint256 max, uint256 _globalMax, address weth) public {
        address[] memory tokens = new address[](1); 
        tokens[0] = weth;

        uint256[] memory minLimit = new uint256[](1); 
        minLimit[0] = min;

        uint256[] memory maxLimit = new uint256[](1); 
        maxLimit[0] = max;

        uint256[] memory globalMax = new uint256[](1);
        globalMax[0] = _globalMax;

        tokenVault.setLockLimits(tokens, minLimit, maxLimit, globalMax);
        tokenVault.setReleaseLimits(tokens, minLimit, maxLimit);
    }


    // Admin needs to do the following setup. Admin is Gnosis Multisig, so these functions are not calleable from this script but adding for the reference
    function adminTBSetup(
        uint64 toChainId, 
        bool enableToChain, 
        address tokenAddr, 
        address _uniswapPool,
        bool _register
    ) public {
        tokenBridge.registerChainId(toChainId, enableToChain);
        require(tokenBridge.isToChainIdRegistered(toChainId) == enableToChain, "tokenBridge.registerChainId: Failed");
        tokenBridge.registerTokenWithDynamicFee(toChainId, tokenAddr, _uniswapPool, _register);
        require(tokenBridge.isTokenRegistered(toChainId, tokenAddr) == _register, "tokenBridge.registerToken: Failed");
    }

}
