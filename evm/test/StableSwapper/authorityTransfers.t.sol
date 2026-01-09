// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {StableSwapperBase} from "./StableSwapperBase.sol";

/**
 * @title AuthorityTransfersTest
 * @notice Tests for the StableSwapper authority transfer functions
 */
contract AuthorityTransfersTest is StableSwapperBase {
    /*//////////////////////////////////////////////////////////////
                    OPERATIONS AUTHORITY TRANSFER
    //////////////////////////////////////////////////////////////*/
    
    function test_proposeOperationsAuthorityTransfer_reverts_whenCalledByPauseAuthority() public {
        address newAuthority = makeAddr("newAuthority");
        
        vm.prank(pauseAuthority);
        vm.expectRevert();
        swapper.proposeOperationsAuthorityTransfer(newAuthority);
    }
    
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
    
    /*//////////////////////////////////////////////////////////////
                      PAUSE AUTHORITY TRANSFER
    //////////////////////////////////////////////////////////////*/
    
    function test_proposePauseAuthorityTransfer_reverts_whenCalledByOperationsAuthority() public {
        address newAuthority = makeAddr("newAuthority");
        
        vm.prank(operationsAuthority);
        vm.expectRevert();
        swapper.proposePauseAuthorityTransfer(newAuthority);
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
}

