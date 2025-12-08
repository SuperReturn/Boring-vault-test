// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {KatanaAddresses} from "test/resources/KatanaAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

/**
 * @title USDAI Deposit Integration Test
 * @notice This script demonstrates how to deposit USDC into the USDAI vault on Katana  testnet
 * @dev Run with: forge script script/USDAIIntegrationTest/Deposit.sol --rpc-url $KATANA_BOKUTO_RPC_URL
 */
contract sUSDAIDepositScript is Script, KatanaAddresses, ContractNames, MerkleTreeHelper{
    // Test parameters
    uint256 public constant USDAI_DEPOSIT_AMOUNT = 2 * 1e5; // 1 USDAI (6 decimals)
    
    // Contract instances
    Deployer public deployer;
    BoringVault boringVault;
    TellerWithMultiAssetSupport teller;
    ArcticArchitectureLens lens;
    AccountantWithRateProviders accountant;

    function setUp() public {
        vm.createSelectFork("katana");
        setSourceChainName("katana");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        boringVault = BoringVault(payable(previoussSuperUSD));
        teller = TellerWithMultiAssetSupport(deployer.getAddress(sUsdaiVaultTellerName));
        lens = ArcticArchitectureLens(deployer.getAddress(sUsdaiArcticArchitectureLensName));
        accountant = AccountantWithRateProviders(deployer.getAddress(sUsdaiVaultAccountantName));
    }

    function run() public {
        // Get the private key from environment variable
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        
        // Start broadcasting transactions
        vm.startBroadcast(privateKey);
        
        // Deposit USDC
        if (USDAI.balanceOf(user) >= USDAI_DEPOSIT_AMOUNT) {
            console.log("\n=== Depositing USDAI ===");

            USDAI.approve(address(boringVault), USDAI_DEPOSIT_AMOUNT);

            // // Deposit USDAI
            uint256 sharesBefore = boringVault.balanceOf(user);
            teller.deposit(USDAI, USDAI_DEPOSIT_AMOUNT, 0);
            uint256 sharesAfter = boringVault.balanceOf(user);
            
            console.log("Actual shares received:", (sharesAfter - sharesBefore) / 1e6);
        } else {
            console.log("Insufficient USDAI balance for deposit");
        }

        vm.stopBroadcast();
    }
}