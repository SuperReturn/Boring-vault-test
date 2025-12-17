// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract KatanaAddresses {
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

    ERC20 public USDC = ERC20(0x203A662b0BD271A6ed5a60EdFbd04bFce608FD36); // vbUSDC
    ERC20 public USDAI = ERC20(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);
    ERC20 public KAT = ERC20(0x3ba1fbC4c3aEA775d335b31fb53778f46FD3a330);

    address public merklDistributor = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    address[] public morphoVaults = [
        0xCE2b8e464Fc7b5E58710C24b7e5EBFB6027f29D7, // yearn
        0xE4248e2105508FcBad3fe95691551d1AF14015f7, // Gauntlet
        0x61D4F9D3797BA4dA152238c53a6f93Fb665C3c1d, // Steakhouse
        0x1445A01a57D7B7663CfD7B4EE0a8Ec03B379aabD, // Steakhouse High
        0x9aF031182fCe8BF0b296145f2e1f1Df5C3feCDE7, // Clearstar
        0x6a31358E58B8692cE5317181ff3379A5766A7ABA // Clearstar v2
    ];
}
