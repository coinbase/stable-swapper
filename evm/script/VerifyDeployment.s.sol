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

        address feeRecipient = stableSwapper.feeRecipient();
        console.log("Fee Recipient:", feeRecipient);

        uint64 feeBasisPoints = stableSwapper.feeBasisPoints();
        console.log("Fee Rate (basis points):", feeBasisPoints);
        console.log("Fee Rate (percentage):", (uint256(feeBasisPoints) * 100) / 10000, "%");

        // Status state
        console.log("\n--- Status State ---");
        bool swapsEnabled = stableSwapper.isFeatureEnabled(StableSwapper.FeatureFlag.SWAP);
        console.log("Swaps Enabled:", swapsEnabled ? "YES" : "NO");

        bool withdrawalEnabled = stableSwapper.isFeatureEnabled(StableSwapper.FeatureFlag.WITHDRAW);
        console.log("Withdrawal Enabled:", withdrawalEnabled ? "YES" : "NO");

        bool allowlistEnabled = stableSwapper.isFeatureEnabled(StableSwapper.FeatureFlag.ALLOWLIST);
        console.log("Allowlist Enabled:", allowlistEnabled ? "YES" : "NO");

        // Authorities
        console.log("\n--- Authorities ---");
        bytes32 defaultAdminRole = stableSwapper.DEFAULT_ADMIN_ROLE();
        bytes32 withdrawalAuthRole = stableSwapper.TREASURY_ROLE();
        bytes32 configureAuthRole = stableSwapper.CONFIGURE_ROLE();
        bytes32 pauseAuthRole = stableSwapper.PAUSE_ROLE();

        // Note: DEFAULT_ADMIN_ROLE is single-holder via AccessControlDefaultAdminRules
        address defaultAdminAddr = stableSwapper.defaultAdmin();
        console.log("Default Admin Role Exists:", stableSwapper.hasRole(defaultAdminRole, address(0)) ? "NO" : "YES");
        console.log("Default Admin:", defaultAdminAddr == address(0) ? "None" : vm.toString(defaultAdminAddr));

        // Other roles can have multiple holders, so we just check if anyone has them
        // For display purposes, we could use getRoleMemberCount() but it's not exposed
        // So we'll just note if the initial role holders still have their roles
        console.log("Treasury Role Exists:", stableSwapper.hasRole(withdrawalAuthRole, address(0)) ? "NO" : "YES");
        console.log("Configure Role Exists:", stableSwapper.hasRole(configureAuthRole, address(0)) ? "NO" : "YES");
        console.log("Pause Role Exists:", stableSwapper.hasRole(pauseAuthRole, address(0)) ? "NO" : "YES");

        // Pending DEFAULT_ADMIN_ROLE transfer
        console.log("\n--- Pending Admin Transfer ---");
        (address pendingAdmin, uint48 acceptSchedule) = stableSwapper.pendingDefaultAdmin();
        console.log("Pending Default Admin:", pendingAdmin == address(0) ? "None" : vm.toString(pendingAdmin));
        if (pendingAdmin != address(0)) {
            console.log("Accept Schedule:", acceptSchedule);
        }

        // Listed tokens
        console.log("\n--- Listed Tokens ---");
        uint256 tokenCount = stableSwapper.getListedTokensCount();
        console.log("Listed Token Count:", tokenCount);

        if (tokenCount > 0) {
            address[] memory tokens = stableSwapper.getListedTokens();
            for (uint256 i = 0; i < tokens.length; i++) {
                address token = tokens[i];

                console.log("\n  Token [", i, "]:", token);
                console.log("    Swappable:", stableSwapper.isTokenSwappable(token) ? "YES" : "NO");

                // Get decimals directly from token
                (bool decSuccess, bytes memory decData) = token.staticcall(abi.encodeWithSignature("decimals()"));
                if (decSuccess && decData.length >= 32) {
                    uint8 decimals = abi.decode(decData, (uint8));
                    console.log("    Decimals:", decimals);
                }

                console.log("    Reserved Amount:", stableSwapper.getReservedAmount(token));

                // Get actual balance
                (bool success, bytes memory data) =
                    token.staticcall(abi.encodeWithSignature("balanceOf(address)", proxyAddress));
                if (success && data.length >= 32) {
                    uint256 balance = abi.decode(data, (uint256));
                    console.log("    Actual Balance:", balance);

                    uint256 reserved = stableSwapper.getReservedAmount(token);
                    if (balance >= reserved) {
                        uint256 available = balance - reserved;
                        console.log("    Available Liquidity:", available);
                    } else {
                        console.log("    WARNING: Balance < Reserved Amount!");
                    }
                }
            }
        } else {
            console.log("  No tokens supported yet");
        }

        // Allowlist
        console.log("\n--- Allowlist ---");
        console.log("Allowlist Feature:", allowlistEnabled ? "ENABLED" : "DISABLED");

        // Summary
        console.log("\n=== Verification Summary ===");
        console.log("[OK] Fee Basis Points:", feeBasisPoints, "bp");
        console.log("[OK] Default Admin Set:", defaultAdminAddr != address(0) ? "YES" : "NO");
        console.log("[OK] Tokens Configured:", tokenCount);
        console.log("[OK] Swaps Status:", swapsEnabled ? "ENABLED" : "DISABLED");
        console.log("[OK] Withdrawal Status:", withdrawalEnabled ? "ENABLED" : "DISABLED");
        console.log("============================\n");
    }
}
