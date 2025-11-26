// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

contract MerklDropDecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== Merkl ===============================

    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) {}

    error MerklDropDecoderAndSanitizer__InputLengthMismatch();

    function claim(
        address account,
        uint256 ,
        bytes32 ,
        bytes32[] calldata
    ) external pure virtual returns (bytes memory sensitiveArguments) {
        // Since we're only dealing with a single account now, no need for length checks
        sensitiveArguments = abi.encodePacked(account);
    }
}
