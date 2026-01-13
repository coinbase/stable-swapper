// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

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

    address defaultAdmin = makeAddr("defaultAdmin");
    address treasuryAuthority = makeAddr("treasuryAuthority");
    address configureAuthority = makeAddr("configureAuthority");
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
            defaultAdmin, treasuryAuthority, configureAuthority, pauseAuthority, feeRecipient, feeRate, 0
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
        assertTrue(stableSwapper.swapsEnabled(), "Swaps should be enabled");
        assertTrue(stableSwapper.liquidityEnabled(), "Liquidity should be enabled");
        assertFalse(stableSwapper.whitelistEnabled(), "Whitelist should not be enabled");
        assertEq(stableSwapper.getSupportedTokensCount(), 0, "Should have no supported tokens");

        // Verify authorities
        assertTrue(
            stableSwapper.hasRole(stableSwapper.DEFAULT_ADMIN_ROLE(), defaultAdmin), "Upgrade authority should be set"
        );
        assertTrue(
            stableSwapper.hasRole(stableSwapper.TREASURY_ROLE(), treasuryAuthority), "Operations role should be set"
        );
        assertTrue(
            stableSwapper.hasRole(stableSwapper.CONFIGURE_ROLE(), configureAuthority), "Configure role should be set"
        );
        assertTrue(stableSwapper.hasRole(stableSwapper.PAUSE_ROLE(), pauseAuthority), "Pause role should be set");

        // Test configure role can update fee rate
        vm.prank(configureAuthority);
        stableSwapper.updateFeeRate(200);
        assertEq(stableSwapper.feeRate(), 200, "Configure role should be able to update fee rate");

        // Test pause role can disable swaps
        vm.prank(pauseAuthority);
        stableSwapper.updateSwapStatus(false);
        assertFalse(stableSwapper.swapsEnabled(), "Pause role should be able to disable swaps");

        // Test pause role can enable swaps
        vm.prank(pauseAuthority);
        stableSwapper.updateSwapStatus(true);
        assertTrue(stableSwapper.swapsEnabled(), "Pause role should be able to enable swaps");
    }

    function test_deploy_implementation_cannot_be_initialized() public {
        (address implementation,) = deployer.deploy(
            defaultAdmin, treasuryAuthority, configureAuthority, pauseAuthority, feeRecipient, feeRate, 0
        );

        // Try to initialize the implementation directly (should fail)
        StableSwapper impl = StableSwapper(implementation);

        vm.expectRevert();
        impl.initialize(defaultAdmin, treasuryAuthority, configureAuthority, pauseAuthority, feeRecipient, feeRate, 0);
    }

    function test_deploy_proxy_cannot_be_initialized_twice() public {
        (, address proxy) = deployer.deploy(
            defaultAdmin, treasuryAuthority, configureAuthority, pauseAuthority, feeRecipient, feeRate, 0
        );

        StableSwapper stableSwapper = StableSwapper(proxy);

        // Try to initialize again (should fail)
        vm.expectRevert();
        stableSwapper.initialize(
            defaultAdmin, treasuryAuthority, configureAuthority, pauseAuthority, feeRecipient, feeRate, 0
        );
    }
}
