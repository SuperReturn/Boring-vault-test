// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

contract OneInchDecoderAndSanitizer is BaseDecoderAndSanitizer {
    address public immutable oneInchRouter;

    constructor(address _boringVault, address _oneInchRouter) BaseDecoderAndSanitizer(_boringVault) {
        oneInchRouter = _oneInchRouter;
    }

    /**
     * @notice Decoder and sanitizer for 1Inch swap
     * @param desc The swap description parameters
     * @return addressesFound The addresses that need to be validated
     */
    function swap(
        address executor,
        DecoderCustomTypes.SwapDescription calldata desc,
        bytes calldata
    ) external pure returns (bytes memory addressesFound) {
        // Return all relevant addresses that need to be in the merkle tree
        addressesFound = abi.encodePacked(executor, desc.srcToken, desc.dstToken, desc.srcReceiver, desc.dstReceiver);
    }
}
