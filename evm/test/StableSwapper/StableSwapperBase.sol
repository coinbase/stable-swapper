// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StableSwapper} from "../../src/StableSwapper.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title StableSwapperBase
 * @notice Base contract for StableSwapper tests providing common setup and utilities
 */
contract StableSwapperBase is Test {
    StableSwapper public implementation;
    StableSwapper public swapper;

    MockERC20 public usdc;
    MockERC20 public appStable;

    address public defaultAdmin;
    address public treasuryAuthority;
    address public configureAuthority;
    address public pauseAuthority;
    address public feeRecipient;

    address public wallet0;
    address public wallet1;
    address public wallet2;

    function setUp() public virtual {
        // Setup test accounts
        defaultAdmin = makeAddr("defaultAdmin");
        treasuryAuthority = makeAddr("treasuryAuthority");
        configureAuthority = makeAddr("configureAuthority");
        pauseAuthority = makeAddr("pauseAuthority");
        feeRecipient = makeAddr("feeRecipient");
        wallet0 = makeAddr("wallet0");
        wallet1 = makeAddr("wallet1");
        wallet2 = makeAddr("wallet2");

        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        appStable = new MockERC20("App Stable", "APPSTABLE", 6);

        // Deploy implementation
        implementation = new StableSwapper();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            defaultAdmin,
            treasuryAuthority,
            configureAuthority,
            pauseAuthority,
            feeRecipient,
            uint64(0), // 0% fee initially
            uint48(0) // 0 second delay for admin transfers in tests
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        swapper = StableSwapper(address(proxy));

        // Mint tokens to wallet0
        usdc.mint(wallet0, 1000 * 10 ** 6); // 1000 USDC
        appStable.mint(wallet0, 1000 * 10 ** 6); // 1000 AppStable

        // Mint tokens to treasury authority for liquidity operations
        usdc.mint(treasuryAuthority, 1000 * 10 ** 6);
        appStable.mint(treasuryAuthority, 1000 * 10 ** 6);
    }

    /**
     * @notice Helper function to setup basic two-token swap environment
     */
    function setupBasicSwapEnvironment() internal {
        // Configure authority adds tokens
        vm.startPrank(configureAuthority);
        swapper.addToken(address(usdc));
        swapper.addToken(address(appStable));
        vm.stopPrank();

        // Treasury authority deposits liquidity
        vm.startPrank(treasuryAuthority);
        usdc.transfer(address(swapper), 500 * 10 ** 6);
        appStable.transfer(address(swapper), 500 * 10 ** 6);
        vm.stopPrank();
    }
}
