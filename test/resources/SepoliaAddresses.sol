// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract SepoliaAddresses {
    // Liquid Ecosystem
    address public deployerAddress = 0x0468F9Cd7b967f4E012C2a63aB44cBdd638524C5;
    address public dev0Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public dev1Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    // address public liquidV1PriceRouter = 0x693799805B502264f9365440B93C113D86a4fFF5;
    // should be a multisig address!
    address public liquidPayoutAddress = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    address public ccipRouter = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    ERC20 public USDC = ERC20(0x22b592e31BC672DcF5DEAEa8e2dFe54254D0F855);
    ERC20 public USDAI = ERC20(0x7dB5b582284E0dc441695AA364909275b9ddde3D);
}
