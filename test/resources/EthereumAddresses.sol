// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract EthereumAddresses {
    // Liquid Ecosystem
    address public deployerAddress = 0xb654e5d7F1dbFCe3945551a72764e7b06DB25994;
    address public dev0Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public dev1Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public previoussuperUSD = 0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB;
    address public previoussSuperUSD = 0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd;
    // address public liquidV1PriceRouter = 0x693799805B502264f9365440B93C113D86a4fFF5;
    // should be a multisig address!
    address public liquidPayoutAddress = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    address public ccipRouter = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 public USDAI = ERC20(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);

    address public merklDistributor = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    // same as eulerVaults in MerkleTreeHelper.sol
    address [] public eulerVaults = [
        0x53AfE3343f322c4189Ab69E0D048efd154259419,
        0x98281466aBcF48eAAD8c6E22dEdD18A3426A93b4,
        0xe0a80d35bB6618CBA260120b279d357978c42BCE
    ];
}
