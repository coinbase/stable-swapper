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
 *     - UPGRADE_AUTHORITY: Address with upgrade authority role
 *     - OPERATIONS_AUTHORITY: Address with operations authority role
 *     - PAUSE_AUTHORITY: Address with pause authority role
 *     - FEE_RECIPIENT: Address that receives swap fees
 *     - FEE_RATE: Fee rate in basis points (e.g., 100 = 1%)
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
        address upgradeAuthority,
        address operationsAuthority,
        address pauseAuthority,
        address feeRecipient,
        uint64 feeRate
    );

    /// @notice Main deployment function
    ///
    /// @dev Reads configuration from environment variables and deploys contracts
    function run() external {
        // Read configuration from environment variables
        address upgradeAuthority = vm.envAddress("UPGRADE_AUTHORITY");
        address operationsAuthority = vm.envAddress("OPERATIONS_AUTHORITY");
        address pauseAuthority = vm.envAddress("PAUSE_AUTHORITY");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint64 feeRate = uint64(vm.envUint("FEE_RATE"));

        // Validate configuration
        require(upgradeAuthority != address(0), "UPGRADE_AUTHORITY cannot be zero address");
        require(operationsAuthority != address(0), "OPERATIONS_AUTHORITY cannot be zero address");
        require(pauseAuthority != address(0), "PAUSE_AUTHORITY cannot be zero address");
        require(feeRecipient != address(0), "FEE_RECIPIENT cannot be zero address");
        require(feeRate <= 1000, "FEE_RATE must be <= 1000 (10%)");

        // Log deployment configuration
        console.log("\n=== StableSwapper Deployment Configuration ===");
        console.log("Upgrade Authority:", upgradeAuthority);
        console.log("Operations Authority:", operationsAuthority);
        console.log("Pause Authority:", pauseAuthority);
        console.log("Fee Recipient:", feeRecipient);
        console.log("Fee Rate (basis points):", feeRate);
        console.log("Fee Rate (percentage):", (uint256(feeRate) * 100) / 10000, "%");
        console.log("===========================================\n");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy contracts
        (address implementation, address proxy) =
            deploy(upgradeAuthority, operationsAuthority, pauseAuthority, feeRecipient, feeRate);

        vm.stopBroadcast();

        // Log deployment results
        console.log("\n=== Deployment Results ===");
        console.log("Implementation:", implementation);
        console.log("Proxy (StableSwapper):", proxy);
        console.log("==========================\n");

        // Emit deployment event
        emit Deployed(
            implementation, proxy, upgradeAuthority, operationsAuthority, pauseAuthority, feeRecipient, feeRate
        );
    }

    /// @notice Deploys StableSwapper implementation and proxy
    ///
    /// @param upgradeAuthority Address with upgrade authority role
    /// @param operationsAuthority Address with operations authority role
    /// @param pauseAuthority Address with pause authority role
    /// @param feeRecipient Address that receives swap fees
    /// @param feeRate Fee rate in basis points (e.g., 100 = 1%)
    ///
    /// @return implementation Address of the implementation contract
    /// @return proxy Address of the proxy contract (main entry point)
    function deploy(
        address upgradeAuthority,
        address operationsAuthority,
        address pauseAuthority,
        address feeRecipient,
        uint64 feeRate
    ) public returns (address implementation, address proxy) {
        // Step 1: Deploy implementation contract
        console.log("Deploying StableSwapper implementation...");
        StableSwapper implementationContract = new StableSwapper();
        implementation = address(implementationContract);
        console.log("Implementation deployed at:", implementation);

        // Step 2: Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            StableSwapper.initialize.selector,
            upgradeAuthority,
            operationsAuthority,
            pauseAuthority,
            feeRecipient,
            feeRate
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
            stableSwapper.hasRole(stableSwapper.UPGRADE_AUTHORITY(), upgradeAuthority),
            "Upgrade authority not set correctly"
        );
        require(
            stableSwapper.hasRole(stableSwapper.OPERATIONS_AUTHORITY(), operationsAuthority),
            "Operations authority not set correctly"
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
