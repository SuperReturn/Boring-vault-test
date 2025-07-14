// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract MainnetAddresses {
    address public deployerAddress = 0x8E74f230a4E22adcD045EA9e482cAEe37BBE360c;
    address public dev0Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public dev1Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    address public liquidPayoutAddress = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    address public ccipRouter = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
    address public balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address public previousRolesAuthority = 0x3340D54fC3ce205B39960cF041D668AF3bdEffb9;
    address public previousVault = 0x874bCD1AfDfb0864F9362b79B61e37b5c1c9d574;
    address public previoussSuperUSDRolesAuthority = 0xe1D6063800965A7E812D5E12dE90155Ecb362E29;
    address public previoussSuperUSDVault = 0x59E86808d54e3B8Af2F8FFAfE6f51Bc62B4b29C7;

    ERC20 public USDC = ERC20(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
    ERC20 public USDT = ERC20(0x7069C635d6fCd1C3D0cd9b563CDC6373e06052ee);
    ERC20 public USDAI = ERC20(0x874bCD1AfDfb0864F9362b79B61e37b5c1c9d574);
    ERC20 public WETH = ERC20(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);
}
