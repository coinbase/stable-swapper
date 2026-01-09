// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title AuthorityTransfersTest
 * @notice Tests for the StableSwapper authority transfer functions
 */
contract AuthorityTransfersTest is StableSwapperBase {
    bytes32 public upgradeAuthorityRole;
    bytes32 public operationsAuthorityRole;
    bytes32 public pauseAuthorityRole;

    function setUp() public override {
        super.setUp();

        // Cache role identifiers to avoid view calls during expectRevert tests
        upgradeAuthorityRole = swapper.UPGRADE_AUTHORITY();
        operationsAuthorityRole = swapper.OPERATIONS_AUTHORITY();
        pauseAuthorityRole = swapper.PAUSE_AUTHORITY();
    }

    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_proposeAuthorityTransfer_reverts_whenCalledByWrongAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        // Pause authority trying to transfer operations authority
        vm.prank(pauseAuthority);
        vm.expectRevert();
        swapper.proposeAuthorityTransfer(operationsAuthorityRole, newAuthority);

        // Upgrade authority trying to transfer operations authority
        vm.prank(upgradeAuthority);
        vm.expectRevert();
        swapper.proposeAuthorityTransfer(operationsAuthorityRole, newAuthority);

        // Operations authority trying to transfer pause authority
        vm.prank(operationsAuthority);
        vm.expectRevert();
        swapper.proposeAuthorityTransfer(pauseAuthorityRole, newAuthority);

        // Upgrade authority trying to transfer pause authority
        vm.prank(upgradeAuthority);
        vm.expectRevert();
        swapper.proposeAuthorityTransfer(pauseAuthorityRole, newAuthority);

        // Operations authority trying to transfer upgrade authority
        vm.prank(operationsAuthority);
        vm.expectRevert();
        swapper.proposeAuthorityTransfer(upgradeAuthorityRole, newAuthority);

        // Pause authority trying to transfer upgrade authority
        vm.prank(pauseAuthority);
        vm.expectRevert();
        swapper.proposeAuthorityTransfer(upgradeAuthorityRole, newAuthority);
    }

    function test_proposeAuthorityTransfer_reverts_whenNewAuthorityIsZeroAddress_operations() public {
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.proposeAuthorityTransfer(operationsAuthorityRole, address(0));
    }

    function test_proposeAuthorityTransfer_reverts_whenNewAuthorityIsZeroAddress_pause() public {
        vm.prank(pauseAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.proposeAuthorityTransfer(pauseAuthorityRole, address(0));
    }

    function test_proposeAuthorityTransfer_reverts_whenNewAuthorityIsZeroAddress_upgrade() public {
        vm.prank(upgradeAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.proposeAuthorityTransfer(upgradeAuthorityRole, address(0));
    }

    function test_proposeAuthorityTransfer_reverts_whenPendingAuthorityIsAlreadySet_operations() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(operationsAuthority);
        swapper.proposeAuthorityTransfer(operationsAuthorityRole, newAuthority);

        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.PendingAuthorityAlreadySet.selector));
        swapper.proposeAuthorityTransfer(operationsAuthorityRole, newAuthority);
    }

    function test_proposeAuthorityTransfer_reverts_whenPendingAuthorityIsAlreadySet_pause() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(pauseAuthority);
        swapper.proposeAuthorityTransfer(pauseAuthorityRole, newAuthority);

        vm.prank(pauseAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.PendingAuthorityAlreadySet.selector));
        swapper.proposeAuthorityTransfer(pauseAuthorityRole, newAuthority);
    }

    function test_proposeAuthorityTransfer_reverts_whenPendingAuthorityIsAlreadySet_upgrade() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(upgradeAuthority);
        swapper.proposeAuthorityTransfer(upgradeAuthorityRole, newAuthority);

        vm.prank(upgradeAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.PendingAuthorityAlreadySet.selector));
        swapper.proposeAuthorityTransfer(upgradeAuthorityRole, newAuthority);
    }

    function test_acceptAuthority_reverts_whenNoPendingAuthority_operations() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(newAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.acceptAuthority(operationsAuthorityRole);
    }

    function test_acceptAuthority_reverts_whenNoPendingAuthority_pause() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(newAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.acceptAuthority(pauseAuthorityRole);
    }

    function test_acceptAuthority_reverts_whenNoPendingAuthority_upgrade() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(newAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.acceptAuthority(upgradeAuthorityRole);
    }

    function test_acceptAuthority_reverts_whenCalledByNonPendingAuthority_operations() public {
        address newAuthority = makeAddr("newAuthority");
        address wrongCaller = makeAddr("wrongCaller");

        vm.prank(operationsAuthority);
        swapper.proposeAuthorityTransfer(operationsAuthorityRole, newAuthority);

        vm.prank(wrongCaller);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NotPendingAuthority.selector));
        swapper.acceptAuthority(operationsAuthorityRole);
    }

    function test_acceptAuthority_reverts_whenCalledByNonPendingAuthority_pause() public {
        address newAuthority = makeAddr("newAuthority");
        address wrongCaller = makeAddr("wrongCaller");

        vm.prank(pauseAuthority);
        swapper.proposeAuthorityTransfer(pauseAuthorityRole, newAuthority);

        vm.prank(wrongCaller);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NotPendingAuthority.selector));
        swapper.acceptAuthority(pauseAuthorityRole);
    }

    function test_acceptAuthority_reverts_whenCalledByNonPendingAuthority_upgrade() public {
        address newAuthority = makeAddr("newAuthority");
        address wrongCaller = makeAddr("wrongCaller");

        vm.prank(upgradeAuthority);
        swapper.proposeAuthorityTransfer(upgradeAuthorityRole, newAuthority);

        vm.prank(wrongCaller);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NotPendingAuthority.selector));
        swapper.acceptAuthority(upgradeAuthorityRole);
    }

    function test_cancelAuthorityTransfer_reverts_whenNoPendingAuthority_operations() public {
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.cancelAuthorityTransfer(operationsAuthorityRole);
    }

    function test_cancelAuthorityTransfer_reverts_whenNoPendingAuthority_pause() public {
        vm.prank(pauseAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.cancelAuthorityTransfer(pauseAuthorityRole);
    }

    function test_cancelAuthorityTransfer_reverts_whenNoPendingAuthority_upgrade() public {
        vm.prank(upgradeAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.cancelAuthorityTransfer(upgradeAuthorityRole);
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_proposeAuthorityTransfer_proposesAndAcceptsTransfer_operations() public {
        address newOpsAuthority = makeAddr("newOpsAuthority");

        vm.prank(operationsAuthority);
        swapper.proposeAuthorityTransfer(operationsAuthorityRole, newOpsAuthority);

        assertEq(swapper.getPendingAuthority(operationsAuthorityRole), newOpsAuthority);

        vm.prank(newOpsAuthority);
        swapper.acceptAuthority(operationsAuthorityRole);

        assertTrue(swapper.hasRole(operationsAuthorityRole, newOpsAuthority));
        assertFalse(swapper.hasRole(operationsAuthorityRole, operationsAuthority));
        assertEq(swapper.getPendingAuthority(operationsAuthorityRole), address(0));
    }

    function test_proposeAuthorityTransfer_proposesAndAcceptsTransfer_pause() public {
        address newPauseAuthority = makeAddr("newPauseAuthority");

        vm.prank(pauseAuthority);
        swapper.proposeAuthorityTransfer(pauseAuthorityRole, newPauseAuthority);

        assertEq(swapper.getPendingAuthority(pauseAuthorityRole), newPauseAuthority);

        vm.prank(newPauseAuthority);
        swapper.acceptAuthority(pauseAuthorityRole);

        assertTrue(swapper.hasRole(pauseAuthorityRole, newPauseAuthority));
        assertFalse(swapper.hasRole(pauseAuthorityRole, pauseAuthority));
        assertEq(swapper.getPendingAuthority(pauseAuthorityRole), address(0));
    }

    function test_proposeAuthorityTransfer_proposesAndAcceptsTransfer_upgrade() public {
        address newUpgradeAuthority = makeAddr("newUpgradeAuthority");

        vm.prank(upgradeAuthority);
        swapper.proposeAuthorityTransfer(upgradeAuthorityRole, newUpgradeAuthority);

        assertEq(swapper.getPendingAuthority(upgradeAuthorityRole), newUpgradeAuthority);

        vm.prank(newUpgradeAuthority);
        swapper.acceptAuthority(upgradeAuthorityRole);

        assertTrue(swapper.hasRole(upgradeAuthorityRole, newUpgradeAuthority));
        assertFalse(swapper.hasRole(upgradeAuthorityRole, upgradeAuthority));
        assertEq(swapper.getPendingAuthority(upgradeAuthorityRole), address(0));
    }

    function test_cancelAuthorityTransfer_cancelsTransfer_operations() public {
        address newOpsAuthority = makeAddr("newOpsAuthority");

        vm.prank(operationsAuthority);
        swapper.proposeAuthorityTransfer(operationsAuthorityRole, newOpsAuthority);

        assertEq(swapper.getPendingAuthority(operationsAuthorityRole), newOpsAuthority);

        vm.prank(operationsAuthority);
        swapper.cancelAuthorityTransfer(operationsAuthorityRole);
        assertEq(swapper.getPendingAuthority(operationsAuthorityRole), address(0));
    }

    function test_cancelAuthorityTransfer_cancelsTransfer_pause() public {
        address newPauseAuthority = makeAddr("newPauseAuthority");

        vm.prank(pauseAuthority);
        swapper.proposeAuthorityTransfer(pauseAuthorityRole, newPauseAuthority);

        assertEq(swapper.getPendingAuthority(pauseAuthorityRole), newPauseAuthority);

        vm.prank(pauseAuthority);
        swapper.cancelAuthorityTransfer(pauseAuthorityRole);
        assertEq(swapper.getPendingAuthority(pauseAuthorityRole), address(0));
    }

    function test_cancelAuthorityTransfer_cancelsTransfer_upgrade() public {
        address newUpgradeAuthority = makeAddr("newUpgradeAuthority");

        vm.prank(upgradeAuthority);
        swapper.proposeAuthorityTransfer(upgradeAuthorityRole, newUpgradeAuthority);

        assertEq(swapper.getPendingAuthority(upgradeAuthorityRole), newUpgradeAuthority);

        vm.prank(upgradeAuthority);
        swapper.cancelAuthorityTransfer(upgradeAuthorityRole);
        assertEq(swapper.getPendingAuthority(upgradeAuthorityRole), address(0));
    }
}
