// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapper} from "../../src/StableSwapper.sol";
import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title AuthorityTransfersTest
 * @notice Tests for the StableSwapper authority transfer functions
 */
contract AuthorityTransfersTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                              REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_proposeOperationsAuthorityTransfer_reverts_whenCalledByPauseAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(pauseAuthority);
        vm.expectRevert();
        swapper.proposeOperationsAuthorityTransfer(newAuthority);
    }

    function test_proposeOperationsAuthorityTransfer_reverts_whenCalledByUpgradeAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(upgradeAuthority);
        vm.expectRevert();
        swapper.proposeOperationsAuthorityTransfer(newAuthority);
    }

    function test_proposePauseAuthorityTransfer_reverts_whenCalledByOperationsAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(operationsAuthority);
        vm.expectRevert();
        swapper.proposePauseAuthorityTransfer(newAuthority);
    }

    function test_proposePauseAuthorityTransfer_reverts_whenCalledByUpgradeAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(upgradeAuthority);
        vm.expectRevert();
        swapper.proposePauseAuthorityTransfer(newAuthority);
    }

    function test_proposeUpgradeAuthorityTransfer_reverts_whenCalledByOperationsAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(operationsAuthority);
        vm.expectRevert();
        swapper.proposeUpgradeAuthorityTransfer(newAuthority);
    }

    function test_proposeUpgradeAuthorityTransfer_reverts_whenCalledByPauseAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(pauseAuthority);
        vm.expectRevert();
        swapper.proposeUpgradeAuthorityTransfer(newAuthority);
    }

    function test_proposeOperationsAuthorityTransfer_reverts_whenNewAuthorityIsZeroAddress() public {
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.proposeOperationsAuthorityTransfer(address(0));
    }

    function test_proposePauseAuthorityTransfer_reverts_whenNewAuthorityIsZeroAddress() public {
        vm.prank(pauseAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.proposePauseAuthorityTransfer(address(0));
    }

    function test_proposeUpgradeAuthorityTransfer_reverts_whenNewAuthorityIsZeroAddress() public {
        vm.prank(upgradeAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.CannotBeZeroAddress.selector, address(0)));
        swapper.proposeUpgradeAuthorityTransfer(address(0));
    }

    function test_proposeOperationsAuthorityTransfer_reverts_whenPendingAuthorityIsAlreadySet() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(operationsAuthority);
        swapper.proposeOperationsAuthorityTransfer(newAuthority);

        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.PendingAuthorityAlreadySet.selector));
        swapper.proposeOperationsAuthorityTransfer(newAuthority);
    }

    function test_proposePauseAuthorityTransfer_reverts_whenPendingAuthorityIsAlreadySet() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(pauseAuthority);
        swapper.proposePauseAuthorityTransfer(newAuthority);

        vm.prank(pauseAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.PendingAuthorityAlreadySet.selector));
        swapper.proposePauseAuthorityTransfer(newAuthority);
    }

    function test_proposeUpgradeAuthorityTransfer_reverts_whenPendingAuthorityIsAlreadySet() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(upgradeAuthority);
        swapper.proposeUpgradeAuthorityTransfer(newAuthority);

        vm.prank(upgradeAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.PendingAuthorityAlreadySet.selector));
        swapper.proposeUpgradeAuthorityTransfer(newAuthority);
    }

    function test_acceptOperationsAuthority_reverts_whenNoPendingAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(newAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.acceptOperationsAuthority();
    }

    function test_acceptOperationsAuthority_reverts_whenCalledByNonPendingAuthority() public {
        address newAuthority = makeAddr("newAuthority");
        address wrongCaller = makeAddr("wrongCaller");

        // Set up a pending authority transfer first
        vm.prank(operationsAuthority);
        swapper.proposeOperationsAuthorityTransfer(newAuthority);

        // Try to accept from wrong caller
        vm.prank(wrongCaller);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NotPendingAuthority.selector));
        swapper.acceptOperationsAuthority();
    }

    function test_acceptPauseAuthority_reverts_whenNoPendingAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(newAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.acceptPauseAuthority();
    }

    function test_acceptPauseAuthority_reverts_whenCalledByNonPendingAuthority() public {
        address newAuthority = makeAddr("newAuthority");
        address wrongCaller = makeAddr("wrongCaller");

        // Set up a pending authority transfer first
        vm.prank(pauseAuthority);
        swapper.proposePauseAuthorityTransfer(newAuthority);

        // Try to accept from wrong caller
        vm.prank(wrongCaller);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NotPendingAuthority.selector));
        swapper.acceptPauseAuthority();
    }

    function test_acceptUpgradeAuthority_reverts_whenNoPendingAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        vm.prank(newAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.acceptUpgradeAuthority();
    }

    function test_acceptUpgradeAuthority_reverts_whenCalledByNonPendingAuthority() public {
        address newAuthority = makeAddr("newAuthority");
        address wrongCaller = makeAddr("wrongCaller");

        // Set up a pending authority transfer first
        vm.prank(upgradeAuthority);
        swapper.proposeUpgradeAuthorityTransfer(newAuthority);

        // Try to accept from wrong caller
        vm.prank(wrongCaller);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NotPendingAuthority.selector));
        swapper.acceptUpgradeAuthority();
    }

    function test_cancelOperationsAuthorityTransfer_reverts_whenNoPendingAuthority() public {
        vm.prank(operationsAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.cancelOperationsAuthorityTransfer();
    }

    function test_cancelPauseAuthorityTransfer_reverts_whenNoPendingAuthority() public {
        vm.prank(pauseAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.cancelPauseAuthorityTransfer();
    }

    function test_cancelUpgradeAuthorityTransfer_reverts_whenNoPendingAuthority() public {
        vm.prank(upgradeAuthority);
        vm.expectRevert(abi.encodeWithSelector(StableSwapper.NoPendingAuthorityTransfer.selector));
        swapper.cancelUpgradeAuthorityTransfer();
    }

    /*//////////////////////////////////////////////////////////////
                            SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_proposeOperationsAuthorityTransfer_proposesAndAcceptsTransfer() public {
        address newOpsAuthority = makeAddr("newOpsAuthority");

        vm.prank(operationsAuthority);
        swapper.proposeOperationsAuthorityTransfer(newOpsAuthority);

        assertEq(swapper.pendingOperationsAuthority(), newOpsAuthority);

        vm.prank(newOpsAuthority);
        swapper.acceptOperationsAuthority();

        assertTrue(swapper.hasRole(swapper.OPERATIONS_AUTHORITY(), newOpsAuthority));
        assertFalse(swapper.hasRole(swapper.OPERATIONS_AUTHORITY(), operationsAuthority));
        assertEq(swapper.pendingOperationsAuthority(), address(0));
    }

    function test_proposePauseAuthorityTransfer_proposesAndAcceptsTransfer() public {
        address newPauseAuthority = makeAddr("newPauseAuthority");

        vm.prank(pauseAuthority);
        swapper.proposePauseAuthorityTransfer(newPauseAuthority);

        assertEq(swapper.pendingPauseAuthority(), newPauseAuthority);

        vm.prank(newPauseAuthority);
        swapper.acceptPauseAuthority();

        assertTrue(swapper.hasRole(swapper.PAUSE_AUTHORITY(), newPauseAuthority));
        assertFalse(swapper.hasRole(swapper.PAUSE_AUTHORITY(), pauseAuthority));
        assertEq(swapper.pendingPauseAuthority(), address(0));
    }

    function test_proposeUpgradeAuthorityTransfer_proposesAndAcceptsTransfer() public {
        address newUpgradeAuthority = makeAddr("newUpgradeAuthority");

        vm.prank(upgradeAuthority);
        swapper.proposeUpgradeAuthorityTransfer(newUpgradeAuthority);

        assertEq(swapper.pendingUpgradeAuthority(), newUpgradeAuthority);

        vm.prank(newUpgradeAuthority);
        swapper.acceptUpgradeAuthority();

        assertTrue(swapper.hasRole(swapper.UPGRADE_AUTHORITY(), newUpgradeAuthority));
        assertFalse(swapper.hasRole(swapper.UPGRADE_AUTHORITY(), upgradeAuthority));
        assertEq(swapper.pendingUpgradeAuthority(), address(0));
    }

    function test_cancelOperationsAuthorityTransfer_cancelsTransfer() public {
        address newOpsAuthority = makeAddr("newOpsAuthority");

        vm.prank(operationsAuthority);
        swapper.proposeOperationsAuthorityTransfer(newOpsAuthority);

        assertEq(swapper.pendingOperationsAuthority(), newOpsAuthority);

        vm.prank(operationsAuthority);
        swapper.cancelOperationsAuthorityTransfer();
        assertEq(swapper.pendingOperationsAuthority(), address(0));
    }

    function test_cancelPauseAuthorityTransfer_cancelsTransfer() public {
        address newPauseAuthority = makeAddr("newPauseAuthority");

        vm.prank(pauseAuthority);
        swapper.proposePauseAuthorityTransfer(newPauseAuthority);

        assertEq(swapper.pendingPauseAuthority(), newPauseAuthority);

        vm.prank(pauseAuthority);
        swapper.cancelPauseAuthorityTransfer();
        assertEq(swapper.pendingPauseAuthority(), address(0));
    }

    function test_cancelUpgradeAuthorityTransfer_cancelsTransfer() public {
        address newUpgradeAuthority = makeAddr("newUpgradeAuthority");

        vm.prank(upgradeAuthority);
        swapper.proposeUpgradeAuthorityTransfer(newUpgradeAuthority);

        assertEq(swapper.pendingUpgradeAuthority(), newUpgradeAuthority);

        vm.prank(upgradeAuthority);
        swapper.cancelUpgradeAuthorityTransfer();
        assertEq(swapper.pendingUpgradeAuthority(), address(0));
    }
}
