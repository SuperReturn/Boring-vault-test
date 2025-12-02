// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

contract RoosterDecoderAndSanitizer is BaseDecoderAndSanitizer {
    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) {}

    function exactInputSingle(DecoderCustomTypes.RoosterExactInputSingleParams calldata params) 
        external 
        pure 
        returns (bytes memory addressesFound) 
    {
        // Return all relevant addresses that need to be in the merkle tree
        addressesFound = abi.encodePacked(
            params.tokenIn,    // Input token address
            params.tokenOut,   // Output token address  
            params.recipient  // Recipient address
        );
    }
}
