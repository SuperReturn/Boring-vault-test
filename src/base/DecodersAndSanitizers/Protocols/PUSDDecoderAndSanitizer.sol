// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

contract PUSDDecoderAndSanitizer is BaseDecoderAndSanitizer {
    struct PredicateMessage {
        string taskId;
        uint256 expireByBlockNumber;
        address[] signerAddresses;
        bytes[] signatures;
    }

    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) {}

    function deposit(
        IERC20 ,
        uint256 ,
        uint256 ,
        address recipient,
        address,
        PredicateMessage calldata
    ) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(recipient);
    }
}
