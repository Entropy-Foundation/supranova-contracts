// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Supra Labs

pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockToken} from "test/mock/mERC20.sol";
import {MockWETH} from "test/mock/mWETH.sol";
import {MockUSDC} from "test/mock/mUSDC.sol";
import {MockUSDT} from "test/mock/mUSDT.sol";
import {MockWBTC} from "test/mock/mWBTC.sol";
import {MockSupraSValueFeed} from "test/mock/mSupraSValueFeed.sol";
import {MockUniswapV3Pool_WETH_USDT} from "test/mock/mUniswapV3Pool_WETH_USDT.sol";
import {MockUniswapV3Pool_USDC_USDT} from "test/mock/mUniswapV3Pool_USDC_USDT.sol";
import {MockUniswapV3Pool_WBTC_USDT} from "test/mock/mUniswapV3Pool_WBTC_USDT.sol";
import {MockSolvBTC} from "test/mock/mSolvBTC.sol";
import {IHypernova} from "contracts/interfaces/IHypernova.sol";
import {IFeeOperator} from "contracts/interfaces/IFeeOperator.sol";
import {ITokenBridgeService} from "contracts/interfaces/ITokenBridgeService.sol";
import {IVault} from "contracts/interfaces/IVault.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {ISupraSValueFeed} from "contracts/interfaces/ISupraSValueFeed.sol";
import {IUniswapV3Pool} from "contracts/interfaces/IUniswapV3Pool.sol";

import {DeployAndSetupHN} from "script/forge-scripts/DeployAndSetupHN.s.sol";
import {DeployAndSetupFO} from "script/forge-scripts/DeployAndSetupFO.s.sol";
import {DeployAndSetupTB} from "script/forge-scripts/DeployAndSetupTB.s.sol";

contract InitDeploy is Test {
    address public constant ADMIN = address(0xADADAD);
    address public constant ADMIN_V = address(0xADADAD);
    uint256 public constant MSG_ID = 0;
    IHypernova public hypernova;
    IFeeOperator public feeOperator;
    ITokenBridgeService public tokenBridge;
    IVault public vault;
    IWETH public weth;
    IERC20 public usdc;
    IERC20 public usdt;
    IERC20 public wbtc;
    IERC20 public solvBTC;
    MockToken public mockERC20;
    MockWETH public mockweth;
    ISupraSValueFeed public sValueFeed;
    uint256 public supraUsdtPairIndex;
    IUniswapV3Pool public uniswapV3Pool_WETH_USDT;
    IUniswapV3Pool public uniswapV3Pool_USDC_USDT;
    IUniswapV3Pool public uniswapV3Pool_WBTC_USDT;
    IUniswapV3Pool public uniswapV3Pool_USDT_WETH_sepolia;

    function init() public {
        _init();

        DeployAndSetupHN hnDeployer = new DeployAndSetupHN();
        hypernova = hnDeployer.deployHN(ADMIN);

        DeployAndSetupFO foDeployer = new DeployAndSetupFO();
        feeOperator = foDeployer.deployFO(ADMIN, address(hypernova), address(sValueFeed), supraUsdtPairIndex);

        uint256 _delay = 3600;
        DeployAndSetupTB tbDeployer = new DeployAndSetupTB();
        (tokenBridge, vault) = tbDeployer.deployTB(address(hypernova), ADMIN, ADMIN_V, address(feeOperator), address(weth), _delay);
    }

    function _init() internal {
        mockERC20 = new MockToken();
        if (block.chainid == 1 ) { // Mainnet
            weth = IWETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
            usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
            usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
            wbtc = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
            solvBTC = IERC20(0x7A56E1C57C7475CCf742a1832B028F0456652F97);
            sValueFeed = ISupraSValueFeed(0xD02cc7a670047b6b012556A88e275c685d25e0c9);
            supraUsdtPairIndex = 500;
            uniswapV3Pool_WETH_USDT = IUniswapV3Pool(0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36);
            uniswapV3Pool_USDC_USDT = IUniswapV3Pool(0x3416cF6C708Da44DB2624D63ea0AAef7113527C6);
            uniswapV3Pool_WBTC_USDT = IUniswapV3Pool(0x56534741CD8B152df6d48AdF7ac51f75169A83b2);
            // Need to update the pull oracle on mainnet, cause no one yet used the DORA on mainnet for price feed SUPRA_USDT (500)
            // The following only works in mainnet fork test
            _updateMainnetDORAPullOracle();
        } else if (block.chainid == 11155111) { // Sepolia
            weth = IWETH(payable(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14));
            usdc = IERC20(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
            usdt = IERC20(0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0);
            wbtc = IERC20(0x29f2D40B0605204364af54EC677bD022dA425d03);
            solvBTC = IERC20(0xE33109766662932a26d978123383ff9E7bdeF346);
            sValueFeed = ISupraSValueFeed(0x131918bC49Bb7de74aC7e19d61A01544242dAA80);
            supraUsdtPairIndex = 500;
            uniswapV3Pool_USDT_WETH_sepolia = IUniswapV3Pool(0x3289680dD4d6C10bb19b899729cda5eEF58AEfF1);
            uniswapV3Pool_USDC_USDT = IUniswapV3Pool(0xfef3Ae91E2050AcCB4dA6033C6EB3b1BC4E3a1a5);
            uniswapV3Pool_WBTC_USDT = IUniswapV3Pool(0x4b053461dd564CF8e0d2F9E3b73D78BD837de765);
        } else { // Local
            weth = IWETH(address(new MockWETH()));
            usdc = IERC20(address(new MockUSDC()));
            usdt = IERC20(address(new MockUSDT()));
            wbtc = IERC20(address(new MockWBTC()));
            solvBTC = IERC20(address(new MockSolvBTC()));
            sValueFeed = ISupraSValueFeed(address(new MockSupraSValueFeed()));
            supraUsdtPairIndex = 500;
            uniswapV3Pool_WETH_USDT = IUniswapV3Pool(address(new MockUniswapV3Pool_WETH_USDT(address(weth), address(0xffffffffff))));
            uniswapV3Pool_USDC_USDT = IUniswapV3Pool(address(new MockUniswapV3Pool_USDC_USDT(address(usdc), address(0xffffffffff))));
            uniswapV3Pool_WBTC_USDT = IUniswapV3Pool(address(new MockUniswapV3Pool_WBTC_USDT(address(wbtc), address(usdt))));
        }
    }
    function _updateMainnetDORAPullOracle() internal {
        ISupraPullOracleForTest.PriceData memory data = ISupraPullOracleForTest(0x2FA6DbFe4291136Cf272E1A3294362b6651e8517).verifyOracleProof(hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000050d34481e29bfff2b6b66dc1638c897539d83a815c0aeb5f2964defa5b4163f922835031cc524cde2a6c3075335650d2d858dd4e2d3060cc7c2c84dda1ce62b406fab0e1c6711d2bf169e0f7c0cda504ce4d3665e0c8fe2c45a4b9248f78f79700000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000260000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000001f4000000000000000000000000000000000000000000000000000d68e343b46800000000000000000000000000000000000000000000000000000001988e4b0d340000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000001988e4b0d200000000000000000000000000000000000000000000000000000000000000009731e8aaabd41ba12ac360b4160701d190505b23e9329c57c3d9e21c3afc7a482f66a3893b8ae109734eba604cb44b431b78f012a2a9558369e0412fd2bc3a31e027fc9f9a1d39bb51602bdc47df652e6179c06e5b7811f7051370eb4f6329b0d5a83183e1a72ca1e6f1729626662f19887e203eb4481be644135e447485b3b512eb2081ff719cd01788fe61ee19671679df3a67bc1b6c378f13b58fa0ea46c1297e66980e8803f1c8f28aebe33c374f15b7b74026105a33e9d8fdcd11c4f0a8de9c445f1aab8dd2083ce37709e9c7a9ad71f2619dce9e30b21846500108f68ba6e710c0458c02e7e04d79a5d5fedcb26f492298ecefd582b4b7604e96d1fe72ec506b4cd6c1bbed0acd16edcc32205de92c68fb2c32ea4185d7dca997db447ad0000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000");
        // PriceData({ pairs: [500], prices: [4133000000000000 [4.133e15]], decimal: [18] })
        require(data.pairs.length == 1);
    }
    function adminHNSetup(
        bool enabled,
        uint64 toChaiID,
        uint256 cg,
        uint64 cm,
        uint64 _vm,
        uint64 x
    ) public {
        hypernova.addOrUpdateHNConfig(
            enabled,
            toChaiID,
            cg,
            cm,
            _vm,
            x
        );
    }
    function adminFOSetup(
        address _sValueFeed,
        uint256 _supraUsdtPairIndex,
        bool enabledToChainID,
        uint64 toChaiID,
        uint256 rg,
        uint64 rm,
        uint64 sm,
        uint64 tierMicroUSDT,
        uint128 tierWhaleUSDT,
        uint64 tierMicroPercentage,
        uint64 tierStandardPercentage,
        uint64 tierWhalePercentage
    ) public {
        feeOperator.setSValueFeed(_sValueFeed, _supraUsdtPairIndex);
        feeOperator.addOrUpdateTBFeeConfig(
            enabledToChainID,
            toChaiID, 
            rg, 
            rm, 
            sm,
            tierMicroUSDT,
            tierWhaleUSDT,
            tierMicroPercentage,
            tierStandardPercentage,
            tierWhalePercentage
        );
    }

    function adminVaultSetup(uint256 min, uint256 max, uint256 _globalMax, address _tokenAddr) public {
        address[] memory tokens = new address[](1); 
        tokens[0] = _tokenAddr;

        uint256[] memory minLimit = new uint256[](1); 
        minLimit[0] = min;

        uint256[] memory maxLimit = new uint256[](1); 
        maxLimit[0] = max;
        
        uint256[] memory globalMax = new uint256[](1);
        globalMax[0] = _globalMax;

        vault.setLockLimits(tokens, minLimit, maxLimit, globalMax);
        vault.setReleaseLimits(tokens, minLimit, maxLimit);
    }

    function adminTBSetup(
        uint64 toChainId, 
        bool enableToChain, 
        address tokenAddr, 
        address _uniswapPool,
        bool _register,
        bool _isFixedFee,
        uint256 _fixedServiceFee,
        uint256 _fixedRelayerReward
    ) public {
        tokenBridge.registerChainId(toChainId, enableToChain);
        require(tokenBridge.isToChainIdRegistered(toChainId) == enableToChain, "tokenBridge.registerChainId: Failed");
        
        if (_isFixedFee) {
            // Use fixed fee registration when uniswap pool is provided
            tokenBridge.registerTokenWithFixedFee(toChainId, tokenAddr, _fixedServiceFee, _fixedRelayerReward, _register);
        } else {
            // Use dynamic fee registration when uniswap pool is zero
            tokenBridge.registerTokenWithDynamicFee(toChainId, tokenAddr, _uniswapPool, _register);
        }
        
        require(tokenBridge.isTokenRegistered(toChainId, tokenAddr) == _register, "tokenBridge.registerToken: Failed");
    }
}
interface ISupraPullOracleForTest {
    /// @notice Verified price data
    struct PriceData {
        // List of pairs
        uint256[] pairs;
        // List of prices
        // prices[i] is the price of pairs[i]
        uint256[] prices;
        // List of decimals
        // decimals[i] is the decimals of pairs[i]
        uint256[] decimal;
    }
    function verifyOracleProof(bytes calldata _bytesProof) external returns (PriceData memory);
}