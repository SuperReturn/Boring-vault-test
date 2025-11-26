// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract PlumeAddresses {
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
    address public ccipRouter = 0x5e5Fd4720E1CE826138D043aF578D69f48af502F;

    // should be update
    // address public uniswapV3NonFungiblePositionManager = 0x655C406EBFa14EE2006250925e54ec43AD184f8B;

    ERC20 public PUSD = ERC20(0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F);
    ERC20 public USDC = ERC20(0x78adD880A697070c1e765Ac44D65323a0DcCE913);
    ERC20 public USDAI = ERC20(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);

    address public merklDistributor = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address public WPLUME = 0xEa237441c92CAe6FC17Caaf9a7acB3f953be4bd1;

    address public roosterRouter = 0xa7620c9aC50F64C1B73F8601EB1Bfa4e0cf0C617;
    address public roosterPool = 0x05ACF22149Bb67A682e652674B6901F02CB57731; // WPLUME/USDC

    address[] public morphoVaults = [
        0xc0Df5784f28046D11813356919B869dDA5815B16, // re7pUSD
        0x0b14D0bdAf647c541d3887c5b1A4bd64068fCDA7 // MMCpUSD
    ];
}
