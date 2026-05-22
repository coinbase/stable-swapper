// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../../src/StableSwapper.sol";

import {StableSwapperBase} from "../../lib/StableSwapperBase.sol";

/**
 * @title AuthorityTransfersTest
 * @notice Tests for the StableSwapper role management functions
 * @dev Tests both 2-step DEFAULT_ADMIN_ROLE transfers and standard role grant/revoke for other roles
 */
contract AuthorityTransfersTest is StableSwapperBase {
    bytes32 public defaultAdminRole;
    bytes32 public treasuryAuthorityRole;
    bytes32 public configureAuthorityRole;
    bytes32 public pauseAuthorityRole;

    function setUp() public override {
        super.setUp();

        defaultAdminRole = swapper.DEFAULT_ADMIN_ROLE();
        treasuryAuthorityRole = swapper.TREASURY_ROLE();
        configureAuthorityRole = swapper.CONFIGURE_ROLE();
        pauseAuthorityRole = swapper.PAUSE_ROLE();
    }

    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_beginDefaultAdminTransfer_reverts_whenCalledByNonAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(treasuryAuthority);
        vm.expectRevert();
        swapper.beginDefaultAdminTransfer(newAdmin);
    }

    function test_acceptDefaultAdminTransfer_reverts_whenNoPendingTransfer() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(newAdmin);
        vm.expectRevert();
        swapper.acceptDefaultAdminTransfer();
    }

    function test_acceptDefaultAdminTransfer_reverts_whenCalledByWrongAddress() public {
        address newAdmin = makeAddr("newAdmin");
        address wrongCaller = makeAddr("wrongCaller");

        vm.prank(defaultAdmin);
        swapper.beginDefaultAdminTransfer(newAdmin);

        vm.warp(block.timestamp + 1);

        vm.prank(wrongCaller);
        vm.expectRevert();
        swapper.acceptDefaultAdminTransfer();
    }

    function test_cancelDefaultAdminTransfer_reverts_whenCalledByNonAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(defaultAdmin);
        swapper.beginDefaultAdminTransfer(newAdmin);

        vm.prank(treasuryAuthority);
        vm.expectRevert();
        swapper.cancelDefaultAdminTransfer();
    }

    function test_grantRole_reverts_whenCalledByNonAdmin_treasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(configureAuthority);
        vm.expectRevert();
        swapper.grantRole(treasuryAuthorityRole, newTreasury);
    }

    function test_grantRole_reverts_whenCalledByNonAdmin_configure() public {
        address newConfigure = makeAddr("newConfigure");

        vm.prank(pauseAuthority);
        vm.expectRevert();
        swapper.grantRole(configureAuthorityRole, newConfigure);
    }

    function test_grantRole_reverts_whenCalledByNonAdmin_pause() public {
        address newPause = makeAddr("newPause");

        vm.prank(treasuryAuthority);
        vm.expectRevert();
        swapper.grantRole(pauseAuthorityRole, newPause);
    }

    function test_revokeRole_reverts_whenCalledByNonAdmin_treasury() public {
        vm.prank(configureAuthority);
        vm.expectRevert();
        swapper.revokeRole(treasuryAuthorityRole, treasuryAuthority);
    }

    function test_revokeRole_reverts_whenCalledByNonAdmin_configure() public {
        vm.prank(pauseAuthority);
        vm.expectRevert();
        swapper.revokeRole(configureAuthorityRole, configureAuthority);
    }

    function test_revokeRole_reverts_whenCalledByNonAdmin_pause() public {
        vm.prank(treasuryAuthority);
        vm.expectRevert();
        swapper.revokeRole(pauseAuthorityRole, pauseAuthority);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_beginDefaultAdminTransfer_beginsTransfer() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(defaultAdmin);
        swapper.beginDefaultAdminTransfer(newAdmin);

        (address pendingAdmin,) = swapper.pendingDefaultAdmin();
        assertEq(pendingAdmin, newAdmin);
    }

    function test_acceptDefaultAdminTransfer_completesTransfer() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(defaultAdmin);
        swapper.beginDefaultAdminTransfer(newAdmin);

        vm.warp(block.timestamp + 1);

        vm.prank(newAdmin);
        swapper.acceptDefaultAdminTransfer();

        assertTrue(swapper.hasRole(defaultAdminRole, newAdmin));
        assertFalse(swapper.hasRole(defaultAdminRole, defaultAdmin));

        (address pendingAdmin,) = swapper.pendingDefaultAdmin();
        assertEq(pendingAdmin, address(0));
    }

    function test_cancelDefaultAdminTransfer_cancelsTransfer() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(defaultAdmin);
        swapper.beginDefaultAdminTransfer(newAdmin);

        (address pendingAdminBefore,) = swapper.pendingDefaultAdmin();
        assertEq(pendingAdminBefore, newAdmin);

        vm.prank(defaultAdmin);
        swapper.cancelDefaultAdminTransfer();

        (address pendingAdminAfter,) = swapper.pendingDefaultAdmin();
        assertEq(pendingAdminAfter, address(0));
        assertTrue(swapper.hasRole(defaultAdminRole, defaultAdmin));
    }

    function test_grantRole_grantsRole_treasury() public {
        address newTreasury = makeAddr("newTreasury");

        assertFalse(swapper.hasRole(treasuryAuthorityRole, newTreasury));

        vm.prank(defaultAdmin);
        swapper.grantRole(treasuryAuthorityRole, newTreasury);

        assertTrue(swapper.hasRole(treasuryAuthorityRole, newTreasury));
        assertTrue(swapper.hasRole(treasuryAuthorityRole, treasuryAuthority));
    }

    function test_grantRole_grantsRole_configure() public {
        address newConfigure = makeAddr("newConfigure");

        assertFalse(swapper.hasRole(configureAuthorityRole, newConfigure));

        vm.prank(defaultAdmin);
        swapper.grantRole(configureAuthorityRole, newConfigure);

        assertTrue(swapper.hasRole(configureAuthorityRole, newConfigure));
        assertTrue(swapper.hasRole(configureAuthorityRole, configureAuthority));
    }

    function test_grantRole_grantsRole_pause() public {
        address newPause = makeAddr("newPause");

        assertFalse(swapper.hasRole(pauseAuthorityRole, newPause));

        vm.prank(defaultAdmin);
        swapper.grantRole(pauseAuthorityRole, newPause);

        assertTrue(swapper.hasRole(pauseAuthorityRole, newPause));
        assertTrue(swapper.hasRole(pauseAuthorityRole, pauseAuthority));
    }

    function test_revokeRole_revokesRole_treasury() public {
        vm.prank(defaultAdmin);
        swapper.revokeRole(treasuryAuthorityRole, treasuryAuthority);

        assertFalse(swapper.hasRole(treasuryAuthorityRole, treasuryAuthority));
    }

    function test_revokeRole_revokesRole_configure() public {
        vm.prank(defaultAdmin);
        swapper.revokeRole(configureAuthorityRole, configureAuthority);

        assertFalse(swapper.hasRole(configureAuthorityRole, configureAuthority));
    }

    function test_revokeRole_revokesRole_pause() public {
        vm.prank(defaultAdmin);
        swapper.revokeRole(pauseAuthorityRole, pauseAuthority);

        assertFalse(swapper.hasRole(pauseAuthorityRole, pauseAuthority));
    }

    /*//////////////////////////////////////////////////////////////
                    FUNCTIONAL TESTS AFTER ROLE CHANGES
    //////////////////////////////////////////////////////////////*/

    function test_newTreasuryAuthority_canWithdrawLiquidity() public {
        address newTreasury = makeAddr("newTreasury");

        // Setup tokens and liquidity
        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(usdc), true);

        vm.prank(treasuryAuthority);
        usdc.transfer(address(swapper), 500 * 10 ** 6);

        // Grant role to new treasury authority
        vm.prank(defaultAdmin);
        swapper.grantRole(treasuryAuthorityRole, newTreasury);

        // New treasury role holder should be able to withdraw
        vm.prank(newTreasury);
        swapper.withdrawLiquidity(address(usdc), 100 * 10 ** 6, newTreasury);

        assertEq(usdc.balanceOf(newTreasury), 100 * 10 ** 6);
    }

    function test_newConfigureAuthority_canAddTokens() public {
        address newConfigure = makeAddr("newConfigure");

        // Grant role to new configure role holder
        vm.prank(defaultAdmin);
        swapper.grantRole(configureAuthorityRole, newConfigure);

        // New configure role holder should be able to add tokens
        vm.prank(newConfigure);
        swapper.updateTokenListing(address(usdc), true);

        assertTrue(swapper.getListedTokensCount() == 1);
    }

    function test_newPauseAuthority_canPauseSwaps() public {
        address newPause = makeAddr("newPause");

        // Grant role to new pause role holder
        vm.prank(defaultAdmin);
        swapper.grantRole(pauseAuthorityRole, newPause);

        // New pause role holder should be able to pause swaps
        vm.prank(newPause);
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.SWAP, false);

        assertFalse(swapper.isFeatureEnabled(StableSwapper.FeatureFlag.SWAP));
    }

    function test_revokedTreasuryAuthority_cannotWithdrawLiquidity() public {
        // Setup tokens and liquidity
        vm.prank(configureAuthority);
        swapper.updateTokenListing(address(usdc), true);

        vm.prank(treasuryAuthority);
        usdc.transfer(address(swapper), 500 * 10 ** 6);

        // Revoke treasury role
        vm.prank(defaultAdmin);
        swapper.revokeRole(treasuryAuthorityRole, treasuryAuthority);

        // Original treasury role holder should not be able to withdraw
        vm.prank(treasuryAuthority);
        vm.expectRevert();
        swapper.withdrawLiquidity(address(usdc), 100 * 10 ** 6, treasuryAuthority);
    }

    function test_revokedConfigureAuthority_cannotAddTokens() public {
        // Revoke configure role
        vm.prank(defaultAdmin);
        swapper.revokeRole(configureAuthorityRole, configureAuthority);

        // Original configure role holder should not be able to add tokens
        vm.prank(configureAuthority);
        vm.expectRevert();
        swapper.updateTokenListing(address(usdc), true);
    }

    function test_revokedPauseAuthority_cannotPauseSwaps() public {
        // Revoke pause role
        vm.prank(defaultAdmin);
        swapper.revokeRole(pauseAuthorityRole, pauseAuthority);

        // Original pause role holder should not be able to pause swaps
        vm.prank(pauseAuthority);
        vm.expectRevert();
        swapper.setFeatureFlag(StableSwapper.FeatureFlag.SWAP, false);
    }

    function test_newDefaultAdmin_canGrantRoles() public {
        address newAdmin = makeAddr("newAdmin");
        address newTreasury = makeAddr("newTreasury");

        // Transfer admin role
        vm.prank(defaultAdmin);
        swapper.beginDefaultAdminTransfer(newAdmin);

        vm.warp(block.timestamp + 1);

        vm.prank(newAdmin);
        swapper.acceptDefaultAdminTransfer();

        // New admin should be able to grant roles
        vm.prank(newAdmin);
        swapper.grantRole(treasuryAuthorityRole, newTreasury);

        assertTrue(swapper.hasRole(treasuryAuthorityRole, newTreasury));
    }
}
