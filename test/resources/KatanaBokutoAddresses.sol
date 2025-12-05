// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract KatanaBokutoAddresses {
    // Liquid Ecosystem
    address public deployerAddress = 0xb654e5d7F1dbFCe3945551a72764e7b06DB25994;
    address public dev0Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public dev1Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public previoussuperUSD = 0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB;
    address public previoussSuperUSD = 0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd;
    // address public liquidV1PriceRouter = 0x693799805B502264f9365440B93C113D86a4fFF5;
    // should be a multisig address!
    address public liquidPayoutAddress = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    //address public ccipRouter = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    ERC20 public USDC = ERC20(0xd00Ab814Ff27F3183CE2B0f0C07Df72006b64876); // mock vbusdc
    //ERC20 public USDC = ERC20(0xc2a4C310F2512A17Ac0047cf871aCAed3E62bB4B); // real testnet vdusdc
    ERC20 public USDAI = ERC20(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);
}
