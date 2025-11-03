// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {KatanaBokutoAddresses} from "test/resources/KatanaBokutoAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

/**
 * @title USDAI Deposit Integration Test
 * @notice This script demonstrates how to deposit USDC into the USDAI vault on Sepolia
 * @dev Run with: forge script script/USDAIIntegrationTest/Deposit.sol --rpc-url $MINATO_RPC_URL
 */
contract USDAIDepositScript is Script, KatanaBokutoAddresses, ContractNames, MerkleTreeHelper{
    // Test parameters
    uint256 public constant USDC_DEPOSIT_AMOUNT = 2 * 1e6; // 1 USDC (6 decimals)
    
    // Contract instances
    Deployer public deployer;
    BoringVault boringVault;
    TellerWithMultiAssetSupport teller;
    ArcticArchitectureLens lens;
    AccountantWithRateProviders accountant;

    function setUp() public {
        vm.createSelectFork("katanabokuto");
        setSourceChainName("katanabokuto");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        boringVault = BoringVault(payable(deployer.getAddress(UsdaiVaultName)));
        teller = TellerWithMultiAssetSupport(deployer.getAddress(UsdaiVaultTellerName));
        lens = ArcticArchitectureLens(deployer.getAddress(UsdaiArcticArchitectureLensName));
        accountant = AccountantWithRateProviders(deployer.getAddress(UsdaiVaultAccountantName));
    }

    function run() public {
        // Get the private key from environment variable
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        
        // Start broadcasting transactions
        vm.startBroadcast(privateKey);
        
        // Deposit USDC
        if (USDC.balanceOf(user) >= USDC_DEPOSIT_AMOUNT) {
            console.log("\n=== Depositing USDC ===");

            USDC.approve(address(boringVault), USDC_DEPOSIT_AMOUNT);

            // // Deposit USDC
            uint256 sharesBefore = boringVault.balanceOf(user);
            teller.deposit(USDC, USDC_DEPOSIT_AMOUNT, 0);
            uint256 sharesAfter = boringVault.balanceOf(user);
            
            console.log("Actual shares received:", (sharesAfter - sharesBefore) / 1e6);
        } else {
            console.log("Insufficient USDC balance for deposit");
        }

        vm.stopBroadcast();
    }
}