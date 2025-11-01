// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract SepoliaAddresses {
    // Liquid Ecosystem
    address public deployerAddress = 0x5D2049062E081065d08F9Df0743Cf9FBaD7508Aa;
    address public dev0Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public dev1Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    // address public liquidV1PriceRouter = 0x693799805B502264f9365440B93C113D86a4fFF5;
    // should be a multisig address!
    address public liquidPayoutAddress = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    address public ccipRouter = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    ERC20 public USDC = ERC20(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
    ERC20 public USDAI = ERC20(0x349C2520A5DE5de0b5Af8F9ebA20846A4E849a4d);
}
