// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {DeployStableSwapper} from "../script/DeployStableSwapper.s.sol";
import {StableSwapper} from "../src/StableSwapper.sol";

/**
 * @title DeployStableSwapperTest
 * @notice Tests for the DeployStableSwapper deployment script
 */
contract DeployStableSwapperTest is Test {
    DeployStableSwapper deployer;
    
    address upgradeAuthority = makeAddr("upgradeAuthority");
    address operationsAuthority = makeAddr("operationsAuthority");
    address pauseAuthority = makeAddr("pauseAuthority");
    address feeRecipient = makeAddr("feeRecipient");
    uint64 feeRate = 100; // 1%

    function setUp() public {
        deployer = new DeployStableSwapper();
    }

    function test_deploy_success() public {
        // Test that deployment triggers the Initialized event from StableSwapper
        vm.recordLogs();

        (address implementation, address proxy) = deployer.deploy(
            upgradeAuthority,
            operationsAuthority,
            pauseAuthority,
            feeRecipient,
            feeRate
        );

        // Get recorded logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Verify that at least one log was emitted
        assertTrue(logs.length > 0, "Should emit at least one event");

        // Verify deployment addresses are valid
        assertNotEq(implementation, address(0), "Implementation should not be zero address");
        assertNotEq(proxy, address(0), "Proxy should not be zero address");
        assertNotEq(implementation, proxy, "Implementation and proxy should be different");

        // Verify proxy is initialized correctly
        StableSwapper stableSwapper = StableSwapper(proxy);
        
        assertEq(stableSwapper.contractVersion(), 1, "Contract version should be 1");
        assertEq(stableSwapper.feeRecipient(), feeRecipient, "Fee recipient should match");
        assertEq(stableSwapper.feeRate(), feeRate, "Fee rate should match");
        assertFalse(stableSwapper.swapsPaused(), "Swaps should not be paused");
        assertFalse(stableSwapper.liquidityPaused(), "Liquidity should not be paused");
        assertFalse(stableSwapper.whitelistEnabled(), "Whitelist should not be enabled");
        assertEq(stableSwapper.getSupportedTokensCount(), 0, "Should have no supported tokens");

        // Verify authorities
        assertTrue(
            stableSwapper.hasRole(stableSwapper.UPGRADE_AUTHORITY(), upgradeAuthority),
            "Upgrade authority should be set"
        );
        assertTrue(
            stableSwapper.hasRole(stableSwapper.OPERATIONS_AUTHORITY(), operationsAuthority),
            "Operations authority should be set"
        );
        assertTrue(
            stableSwapper.hasRole(stableSwapper.PAUSE_AUTHORITY(), pauseAuthority),
            "Pause authority should be set"
        );

        // Test operations authority can update fee rate
        vm.prank(operationsAuthority);
        stableSwapper.updateFeeRate(200);
        assertEq(stableSwapper.feeRate(), 200, "Operations authority should be able to update fee rate");

        // Test pause authority can pause swaps
        vm.prank(pauseAuthority);
        stableSwapper.pauseSwaps();
        assertTrue(stableSwapper.swapsPaused(), "Pause authority should be able to pause swaps");

        // Test pause authority can unpause swaps
        vm.prank(pauseAuthority);
        stableSwapper.unpauseSwaps();
        assertFalse(stableSwapper.swapsPaused(), "Pause authority should be able to unpause swaps");
    }

    function test_deploy_implementation_cannot_be_initialized() public {
        (address implementation,) = deployer.deploy(
            upgradeAuthority,
            operationsAuthority,
            pauseAuthority,
            feeRecipient,
            feeRate
        );

        // Try to initialize the implementation directly (should fail)
        StableSwapper impl = StableSwapper(implementation);
        
        vm.expectRevert();
        impl.initialize(
            upgradeAuthority,
            operationsAuthority,
            pauseAuthority,
            feeRecipient,
            feeRate
        );
    }

    function test_deploy_proxy_cannot_be_initialized_twice() public {
        (, address proxy) = deployer.deploy(
            upgradeAuthority,
            operationsAuthority,
            pauseAuthority,
            feeRecipient,
            feeRate
        );

        StableSwapper stableSwapper = StableSwapper(proxy);

        // Try to initialize again (should fail)
        vm.expectRevert();
        stableSwapper.initialize(
            upgradeAuthority,
            operationsAuthority,
            pauseAuthority,
            feeRecipient,
            feeRate
        );
    }
}

