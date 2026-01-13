// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StableSwapper} from "../src/StableSwapper.sol";

/**
 * @title DeployStableSwapper
 * @notice Deployment script for StableSwapper using UUPS proxy pattern
 * @dev This script deploys:
 *      1. StableSwapper implementation contract
 *      2. ERC1967Proxy pointing to the implementation
 *      3. Initializes the proxy with authorities and fee configuration
 *
 * Usage:
 *   Set environment variables:
 *     - DEFAULT_ADMIN: Address with DEFAULT_ADMIN_ROLE (can upgrade contract and manage roles)
 *     - TREASURY_AUTHORITY: Address with TREASURY_AUTHORITY role (can manage liquidity)
 *     - CONFIGURE_AUTHORITY: Address with CONFIGURE_AUTHORITY role (can add tokens, update fees)
 *     - PAUSE_AUTHORITY: Address with PAUSE_AUTHORITY role (can pause operations)
 *     - FEE_RECIPIENT: Address that receives swap fees
 *     - FEE_RATE: Fee rate in basis points (e.g., 100 = 1%)
 *     - ADMIN_TRANSFER_DELAY: Delay in seconds for 2-step admin transfers (e.g., 259200 = 3 days)
 *
 *   Deploy to network:
 *     forge script script/DeployStableSwapper.s.sol:DeployStableSwapper \
 *       --rpc-url $RPC_URL \
 *       --broadcast \
 *       --verify
 *
 *   Dry run (no broadcast):
 *     forge script script/DeployStableSwapper.s.sol:DeployStableSwapper \
 *       --rpc-url $RPC_URL
 */
contract DeployStableSwapper is Script {
    /// @notice Emitted when deployment is successful
    event Deployed(
        address indexed implementation,
        address indexed proxy,
        address defaultAdmin,
        address treasuryAuthority,
        address configureAuthority,
        address pauseAuthority,
        address feeRecipient,
        uint64 feeRate,
        uint48 adminTransferDelay
    );

    /// @notice Main deployment function
    ///
    /// @dev Reads configuration from environment variables and deploys contracts
    function run() external {
        // Read configuration from environment variables
        address defaultAdmin = vm.envAddress("DEFAULT_ADMIN");
        address treasuryAuthority = vm.envAddress("TREASURY_AUTHORITY");
        address configureAuthority = vm.envAddress("CONFIGURE_AUTHORITY");
        address pauseAuthority = vm.envAddress("PAUSE_AUTHORITY");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint64 feeRate = uint64(vm.envUint("FEE_RATE"));
        uint48 adminTransferDelay = uint48(vm.envUint("ADMIN_TRANSFER_DELAY"));

        // Validate configuration
        require(defaultAdmin != address(0), "DEFAULT_ADMIN cannot be zero address");
        require(treasuryAuthority != address(0), "TREASURY_AUTHORITY cannot be zero address");
        require(configureAuthority != address(0), "CONFIGURE_AUTHORITY cannot be zero address");
        require(pauseAuthority != address(0), "PAUSE_AUTHORITY cannot be zero address");
        require(feeRecipient != address(0), "FEE_RECIPIENT cannot be zero address");
        require(feeRate <= 1000, "FEE_RATE must be <= 1000 (10%)");

        // Log deployment configuration
        console.log("\n=== StableSwapper Deployment Configuration ===");
        console.log("Default Admin:", defaultAdmin);
        console.log("Treasury Authority:", treasuryAuthority);
        console.log("Configure Authority:", configureAuthority);
        console.log("Pause Authority:", pauseAuthority);
        console.log("Fee Recipient:", feeRecipient);
        console.log("Fee Rate (basis points):", feeRate);
        console.log("Fee Rate (percentage):", (uint256(feeRate) * 100) / 10000, "%");
        console.log("Admin Transfer Delay (seconds):", adminTransferDelay);
        console.log("===========================================\n");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy contracts
        (address implementation, address proxy) = deploy(
            defaultAdmin,
            treasuryAuthority,
            configureAuthority,
            pauseAuthority,
            feeRecipient,
            feeRate,
            adminTransferDelay
        );

        vm.stopBroadcast();

        // Log deployment results
        console.log("\n=== Deployment Results ===");
        console.log("Implementation:", implementation);
        console.log("Proxy (StableSwapper):", proxy);
        console.log("==========================\n");

        // Emit deployment event
        emit Deployed(
            implementation,
            proxy,
            defaultAdmin,
            treasuryAuthority,
            configureAuthority,
            pauseAuthority,
            feeRecipient,
            feeRate,
            adminTransferDelay
        );
    }

    /// @notice Deploys StableSwapper implementation and proxy
    ///
    /// @param defaultAdmin Address with DEFAULT_ADMIN_ROLE
    /// @param treasuryAuthority Address with TREASURY_AUTHORITY role
    /// @param configureAuthority Address with CONFIGURE_AUTHORITY role
    /// @param pauseAuthority Address with PAUSE_AUTHORITY role
    /// @param feeRecipient Address that receives swap fees
    /// @param feeRate Fee rate in basis points (e.g., 100 = 1%)
    /// @param adminTransferDelay Delay in seconds for 2-step admin transfers
    ///
    /// @return implementation Address of the implementation contract
    /// @return proxy Address of the proxy contract (main entry point)
    function deploy(
        address defaultAdmin,
        address treasuryAuthority,
        address configureAuthority,
        address pauseAuthority,
        address feeRecipient,
        uint64 feeRate,
        uint48 adminTransferDelay
    ) public returns (address implementation, address proxy) {
        // Step 1: Deploy implementation contract
        console.log("Deploying StableSwapper implementation...");
        StableSwapper implementationContract = new StableSwapper();
        implementation = address(implementationContract);
        console.log("Implementation deployed at:", implementation);

        // Step 2: Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            defaultAdmin,
            treasuryAuthority,
            configureAuthority,
            pauseAuthority,
            feeRecipient,
            feeRate,
            adminTransferDelay
        );

        // Step 3: Deploy ERC1967 proxy with initialization
        console.log("Deploying ERC1967 proxy...");
        ERC1967Proxy proxyContract = new ERC1967Proxy(implementation, initData);
        proxy = address(proxyContract);
        console.log("Proxy deployed at:", proxy);

        // Step 4: Verify initialization
        StableSwapper stableSwapper = StableSwapper(proxy);

        // Verify contract version
        require(stableSwapper.contractVersion() == 1, "Contract version mismatch");

        // Verify authorities
        require(
            stableSwapper.hasRole(stableSwapper.DEFAULT_ADMIN_ROLE(), defaultAdmin), "Default admin not set correctly"
        );
        require(
            stableSwapper.hasRole(stableSwapper.TREASURY_AUTHORITY(), treasuryAuthority),
            "Treasury authority not set correctly"
        );
        require(
            stableSwapper.hasRole(stableSwapper.CONFIGURE_AUTHORITY(), configureAuthority),
            "Configure authority not set correctly"
        );
        require(
            stableSwapper.hasRole(stableSwapper.PAUSE_AUTHORITY(), pauseAuthority), "Pause authority not set correctly"
        );

        // Verify fee configuration
        require(stableSwapper.feeRecipient() == feeRecipient, "Fee recipient not set correctly");
        require(stableSwapper.feeRate() == feeRate, "Fee rate not set correctly");

        // Verify initial state
        require(stableSwapper.swapsEnabled(), "Swaps should be enabled");
        require(stableSwapper.liquidityEnabled(), "Liquidity should be enabled");
        require(!stableSwapper.whitelistEnabled(), "Whitelist should not be enabled");
        require(stableSwapper.getSupportedTokensCount() == 0, "No tokens should be supported initially");

        console.log("Deployment verification successful!");

        return (implementation, proxy);
    }
}
