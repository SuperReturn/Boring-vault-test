// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract PlumeTestnetAddresses {
    // Liquid Ecosystem
    address public deployerAddress = 0x6A0FE0ab71583F23Ea62904cd2C98DD18E0F9096;
    address public dev0Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public dev1Address = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public previoussuperUSD = 0x1C6DfA6C99d83aE8b872C32119575ce24407767C;
    address public previoussSuperUSD = 0xE47B7cA2C2c8fDbB29A38d63804A795E8F899616;
    // address public liquidV1PriceRouter = 0x693799805B502264f9365440B93C113D86a4fFF5;
    // should be a multisig address!
    address public liquidPayoutAddress = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    // CCIP token transfers.
    address public ccipRouter = 0x5e5Fd4720E1CE826138D043aF578D69f48af502F;

    // should be update
    // address public uniswapV3NonFungiblePositionManager = 0x655C406EBFa14EE2006250925e54ec43AD184f8B;

    ERC20 public PUSD = ERC20(0x1E0E030AbCb4f07de629DCCEa458a271e0E82624);
    ERC20 public USDC = ERC20(0x78adD880A697070c1e765Ac44D65323a0DcCE913);
    ERC20 public USDAI = ERC20(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);

    address public WPLUME = 0xEa237441c92CAe6FC17Caaf9a7acB3f953be4bd1;
}
