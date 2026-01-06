// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

contract EulerDecoderAndSanitizer is BaseDecoderAndSanitizer {

    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) {}

    function deposit(uint256, address receiver) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver);
    }

    function withdraw(uint256, address receiver, address owner) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver, owner);
    }
}
