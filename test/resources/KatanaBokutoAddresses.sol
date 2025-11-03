// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract KatanaBokutoAddresses {
    // Liquid Ecosystem
    //address public deployerAddress = 0x5D2049062E081065d08F9Df0743Cf9FBaD7508Aa;
    address public deployerAddress = 0x8F7a43819df55B1181C1Bd15948b0be9eF2fD385;
    address public dev0Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public dev1Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    // address public liquidV1PriceRouter = 0x693799805B502264f9365440B93C113D86a4fFF5;
    // should be a multisig address!
    address public liquidPayoutAddress = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    //address public ccipRouter = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    ERC20 public USDC = ERC20(0xc2a4C310F2512A17Ac0047cf871aCAed3E62bB4B); // vbusdc
    ERC20 public USDAI = ERC20(0xBD004e02D00AA0b23FE9224D1902A4EEc94952e4);
}
