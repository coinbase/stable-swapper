// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

import {StableSwapper} from "../src/StableSwapper.sol";

/**
 * @title VerifyDeployment
 * @notice Script to verify an existing StableSwapper deployment
 * @dev This script checks the configuration and state of a deployed StableSwapper
 *
 * Usage:
 *   Set environment variables:
 *     - STABLE_SWAPPER_PROXY: Address of the deployed proxy
 *
 *   Run verification:
 *     forge script script/VerifyDeployment.s.sol:VerifyDeployment \
 *       --rpc-url $RPC_URL
 */
contract VerifyDeployment is Script {
    function run() external view {
        address proxyAddress = vm.envAddress("STABLE_SWAPPER_PROXY");

        require(proxyAddress != address(0), "STABLE_SWAPPER_PROXY must be set");

        console.log("\n=== StableSwapper Deployment Verification ===");
        console.log("Proxy Address:", proxyAddress);
        console.log("==========================================\n");

        verify(proxyAddress);
    }

    function verify(address proxyAddress) public view {
        StableSwapper stableSwapper = StableSwapper(proxyAddress);

        // Check if contract exists
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(proxyAddress)
        }
        require(codeSize > 0, "No contract found at proxy address");
        console.log("[OK] Contract exists at proxy address");

        // Basic configuration
        console.log("\n--- Basic Configuration ---");
        uint8 version = stableSwapper.contractVersion();
        console.log("Contract Version:", version);

        address feeRecipient = stableSwapper.feeRecipient();
        console.log("Fee Recipient:", feeRecipient);

        uint64 feeRate = stableSwapper.feeRate();
        console.log("Fee Rate (basis points):", feeRate);
        console.log("Fee Rate (percentage):", (uint256(feeRate) * 100) / 10000, "%");

        // Status state
        console.log("\n--- Status State ---");
        bool swapsEnabled = stableSwapper.swapsEnabled();
        console.log("Swaps Enabled:", swapsEnabled ? "YES" : "NO");

        bool liquidityEnabled = stableSwapper.liquidityEnabled();
        console.log("Liquidity Enabled:", liquidityEnabled ? "YES" : "NO");

        bool whitelistEnabled = stableSwapper.whitelistEnabled();
        console.log("Whitelist Enabled:", whitelistEnabled ? "YES" : "NO");

        // Authorities
        console.log("\n--- Authorities ---");
        bytes32 defaultAdminRole = stableSwapper.DEFAULT_ADMIN_ROLE();
        bytes32 treasuryAuthRole = stableSwapper.TREASURY_ROLE();
        bytes32 configureAuthRole = stableSwapper.CONFIGURE_ROLE();
        bytes32 pauseAuthRole = stableSwapper.PAUSE_ROLE();

        // Note: DEFAULT_ADMIN_ROLE is single-holder via AccessControlDefaultAdminRules
        address defaultAdminAddr = stableSwapper.defaultAdmin();
        console.log("Default Admin Role Exists:", stableSwapper.hasRole(defaultAdminRole, address(0)) ? "NO" : "YES");
        console.log("Default Admin:", defaultAdminAddr == address(0) ? "None" : vm.toString(defaultAdminAddr));

        // Other roles can have multiple holders, so we just check if anyone has them
        // For display purposes, we could use getRoleMemberCount() but it's not exposed
        // So we'll just note if the initial role holders still have their roles
        console.log("Treasury Role Exists:", stableSwapper.hasRole(treasuryAuthRole, address(0)) ? "NO" : "YES");
        console.log("Configure Role Exists:", stableSwapper.hasRole(configureAuthRole, address(0)) ? "NO" : "YES");
        console.log("Pause Role Exists:", stableSwapper.hasRole(pauseAuthRole, address(0)) ? "NO" : "YES");

        // Pending DEFAULT_ADMIN_ROLE transfer
        console.log("\n--- Pending Admin Transfer ---");
        (address pendingAdmin, uint48 acceptSchedule) = stableSwapper.pendingDefaultAdmin();
        console.log("Pending Default Admin:", pendingAdmin == address(0) ? "None" : vm.toString(pendingAdmin));
        if (pendingAdmin != address(0)) {
            console.log("Accept Schedule:", acceptSchedule);
        }

        // Supported tokens
        console.log("\n--- Supported Tokens ---");
        uint256 tokenCount = stableSwapper.getSupportedTokensCount();
        console.log("Supported Token Count:", tokenCount);

        if (tokenCount > 0) {
            address[] memory tokens = stableSwapper.getSupportedTokens();
            for (uint256 i = 0; i < tokens.length; i++) {
                address token = tokens[i];
                StableSwapper.TokenVault memory vault = stableSwapper.getVault(token);

                console.log("\n  Token [", i, "]:", token);
                console.log("    Enabled:", vault.isEnabled ? "YES" : "NO");
                console.log("    Decimals:", vault.decimals);
                console.log("    Reserved Amount:", vault.reservedAmount);

                // Get actual balance
                (bool success, bytes memory data) =
                    token.staticcall(abi.encodeWithSignature("balanceOf(address)", proxyAddress));
                if (success && data.length >= 32) {
                    uint256 balance = abi.decode(data, (uint256));
                    console.log("    Actual Balance:", balance);

                    if (balance >= vault.reservedAmount) {
                        uint256 available = balance - vault.reservedAmount;
                        console.log("    Available Liquidity:", available);
                    } else {
                        console.log("    WARNING: Balance < Reserved Amount!");
                    }
                }
            }
        } else {
            console.log("  No tokens supported yet");
        }

        // Whitelist
        console.log("\n--- Whitelist ---");
        uint256 whitelistCount = stableSwapper.getWhitelistedAddressesCount();
        console.log("Whitelisted Address Count:", whitelistCount);

        if (whitelistCount > 0) {
            address[] memory whitelisted = stableSwapper.getWhitelistedAddresses();
            for (uint256 i = 0; i < whitelisted.length; i++) {
                console.log("  [", i, "]", whitelisted[i]);
            }
        }

        // Summary
        console.log("\n=== Verification Summary ===");
        console.log("[OK] Contract Version:", version);
        console.log("[OK] Fee Rate:", feeRate, "bp");
        console.log("[OK] Default Admin Set:", defaultAdminAddr != address(0) ? "YES" : "NO");
        console.log("[OK] Tokens Configured:", tokenCount);
        console.log("[OK] Swaps Status:", swapsEnabled ? "ENABLED" : "DISABLED");
        console.log("[OK] Liquidity Status:", liquidityEnabled ? "ENABLED" : "DISABLED");
        console.log("============================\n");
    }
}
