// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract ArbitrumAddresses {
    // Liquid Ecosystem
    address public deployerAddress = 0xb654e5d7F1dbFCe3945551a72764e7b06DB25994;
    address public dev0Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public dev1Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public previoussuperUSD = 0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB;
    address public previoussSuperUSD = 0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd;
    // address public liquidV1PriceRouter = 0x693799805B502264f9365440B93C113D86a4fFF5;
    // should be a multisig address!
    address public liquidPayoutAddress = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    address public ccipRouter = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8; // arbitrum
    address public oneInchRouter = 0x111111125421cA6dc452d289314280a0f8842A65; // arbitrum

    address public merklDistributor = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    ERC20 public USDAI = ERC20(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);

    ERC20 public USDC = ERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); // arbitrum
    ERC20 public WETH = ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // arbitrum

    address public MORPHO = 0x40BD670A58238e6E230c430BBb5cE6ec0d40df48;
    address public ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;

    address[] public morphoVaults = [
        0x4B6F1C9E5d470b97181786b26da0d0945A7cf027,
        0x5c0C306Aaa9F877de636f4d5822cA9F2E81563BA,
        0x7c574174DA4b2be3f705c6244B4BfA0815a8B3Ed,
        0x7e97fa6893871A2751B5fE961978DCCb2c201E65,
        0x36b69949d60d06ECcC14DE0Ae63f4E00cc2cd8B9,
        0x64A651D825FC70Ebba88f2E1BAD90be9A496C4b9,
        0x704761B6280BfABC7E397EfD34Fc15cd3b527d7D,
        0x87DEAE530841A9671326C9D5B9f91bdB11F3162c,
        0x9257eDDa03f9915857187e927eF501c53b1679b3,
        0xa53Cf822FE93002aEaE16d395CD823Ece161a6AC,
        0xa60643c90A542A95026C0F1dbdB0615fF42019Cf,
        0x250CF7c82bAc7cB6cf899b6052979d4B5BA1f9ca
    ];
}