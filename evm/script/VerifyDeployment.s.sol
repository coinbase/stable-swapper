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

        // Pause state
        console.log("\n--- Pause State ---");
        bool swapsPaused = stableSwapper.swapsPaused();
        console.log("Swaps Paused:", swapsPaused ? "YES" : "NO");

        bool liquidityPaused = stableSwapper.liquidityPaused();
        console.log("Liquidity Paused:", liquidityPaused ? "YES" : "NO");

        bool whitelistEnabled = stableSwapper.whitelistEnabled();
        console.log("Whitelist Enabled:", whitelistEnabled ? "YES" : "NO");

        // Authorities
        console.log("\n--- Authorities ---");
        bytes32 upgradeAuthRole = stableSwapper.UPGRADE_AUTHORITY();
        bytes32 opsAuthRole = stableSwapper.OPERATIONS_AUTHORITY();
        bytes32 pauseAuthRole = stableSwapper.PAUSE_AUTHORITY();

        address upgradeAuth = stableSwapper.getRoleHolder(upgradeAuthRole);
        console.log("Upgrade Authority:", upgradeAuth == address(0) ? "None" : vm.toString(upgradeAuth));

        address opsAuth = stableSwapper.getRoleHolder(opsAuthRole);
        console.log("Operations Authority:", opsAuth == address(0) ? "None" : vm.toString(opsAuth));

        address pauseAuth = stableSwapper.getRoleHolder(pauseAuthRole);
        console.log("Pause Authority:", pauseAuth == address(0) ? "None" : vm.toString(pauseAuth));

        // Pending authority transfers
        console.log("\n--- Pending Authority Transfers ---");
        address pendingUpgrade = stableSwapper.getPendingAuthority(upgradeAuthRole);
        console.log("Pending Upgrade Authority:", pendingUpgrade == address(0) ? "None" : vm.toString(pendingUpgrade));

        address pendingOps = stableSwapper.getPendingAuthority(opsAuthRole);
        console.log("Pending Operations Authority:", pendingOps == address(0) ? "None" : vm.toString(pendingOps));

        address pendingPause = stableSwapper.getPendingAuthority(pauseAuthRole);
        console.log("Pending Pause Authority:", pendingPause == address(0) ? "None" : vm.toString(pendingPause));

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
        console.log(
            "[OK] Authorities Set:",
            upgradeAuth != address(0) && opsAuth != address(0) && pauseAuth != address(0) ? "YES" : "NO"
        );
        console.log("[OK] Tokens Configured:", tokenCount);
        console.log("[OK] Swaps Status:", swapsPaused ? "PAUSED" : "ACTIVE");
        console.log("[OK] Liquidity Status:", liquidityPaused ? "PAUSED" : "ACTIVE");
        console.log("============================\n");
    }
}
