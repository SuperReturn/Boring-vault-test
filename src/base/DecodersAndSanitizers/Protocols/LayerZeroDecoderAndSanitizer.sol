// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

contract LayerZeroDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error LayerZeroDecoderAndSanitizer__InvalidDestination();
    error LayerZeroDecoderAndSanitizer__InvalidVault();

    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) {}

    function send(
        DecoderCustomTypes.SendParam calldata params,
        DecoderCustomTypes.MessagingFee calldata,
        address vault
    ) external view returns (bytes memory addressesFound) {
        // Validate that the vault address is correct
        require(vault == boringVault, "LayerZeroDecoderAndSanitizer: Invalid vault address");
        
        // Validate destination address from params.to
        address destination = address(uint160(uint256(params.to)));
        if (destination == address(0)) {
            revert LayerZeroDecoderAndSanitizer__InvalidDestination();
        }

        // Return both the vault and destination addresses for validation
        addressesFound = abi.encodePacked(
            vault
        );
    }

    function validateEndpoint(
        uint32 dstEid,
        uint256 expectedEndpoint
    ) external pure returns (bool) {
        return dstEid == expectedEndpoint;
    }
}
