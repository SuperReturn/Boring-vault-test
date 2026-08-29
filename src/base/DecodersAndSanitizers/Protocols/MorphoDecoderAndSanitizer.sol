// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

interface IMorphoRouter {
    function adapters(uint256) external view returns (address);
}

interface IMorphoAdapter {
    function depositToken() external view returns (address);
}

contract MorphoDecoderAndSanitizer is BaseDecoderAndSanitizer {
    address public immutable morphoRouter;

    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) {}

    function deposit(uint256, address receiver)
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver);
    }
    
    function withdraw(uint256, address receiver, address)
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver);
    }

    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata, // amounts
        bytes32[][] calldata // proofs
    ) external pure returns (bytes memory addressesFound) {
        for (uint256 i = 0; i < users.length; i++) {
            addressesFound = abi.encodePacked(addressesFound, users[i], tokens[i]);
        }
    }
}
