// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @title GenerateStorageLocation
 * @notice Generates ERC-7201 storage location from a namespace
 * @dev Formula: keccak256(abi.encode(uint256(keccak256(id)) - 1)) & ~bytes32(uint256(0xff))
 *
 * Usage:
 *   NAMESPACE="coinbase.storage.StableSwapper" forge script script/GenerateStorageLocation.s.sol:GenerateStorageLocation
 */
contract GenerateStorageLocation is Script {
    function run() external view {
        string memory namespace = vm.envString("NAMESPACE");

        bytes32 location = keccak256(abi.encode(uint256(keccak256(bytes(namespace))) - 1)) & ~bytes32(uint256(0xff));

        console.log("Namespace:", namespace);
        console.log("ERC-7201 Storage Location:");
        console.logBytes32(location);
    }
}
