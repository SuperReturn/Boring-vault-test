// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract SoneiumAddresses {
    // Liquid Ecosystem
    address public deployerAddress = 0xb654e5d7F1dbFCe3945551a72764e7b06DB25994;
    address public dev0Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public dev1Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public previoussuperUSD = 0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB;
    address public previoussSuperUSD = 0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd;
    // address public liquidV1PriceRouter = 0x693799805B502264f9365440B93C113D86a4fFF5;
    // should be a multisig address!
    address public liquidPayoutAddress = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    // CCIP token transfers.
    address public ccipRouter = 0x443a1bce545d56E2c3f20ED32eA588395FFce0f4;

    // should be update
    // address public uniswapV3NonFungiblePositionManager = 0x655C406EBFa14EE2006250925e54ec43AD184f8B;

    // should be deployed on minato later by balancer
    // address public balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    ERC20 public USDC = ERC20(0xbA9986D2381edf1DA03B0B9c1f8b00dc4AacC369);
    ERC20 public ASTR = ERC20(0xbA9986D2381edf1DA03B0B9c1f8b00dc4AacC369); // this one is fake
    ERC20 public USDAI = ERC20(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);
}
