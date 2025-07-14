// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

/**
 * @title USDAI Deposit Integration Test
 * @notice This script demonstrates how to deposit USDC into the USDAI vault on Sepolia
 * @dev Run with: forge script script/USDAIIntegrationTest/Deposit.sol --rpc-url $MINATO_RPC_URL
 */
contract USDAIDepositScript is Script, MainnetAddresses, ContractNames, MerkleTreeHelper{
    // Test parameters
    uint256 public constant USDAI_DEPOSIT_AMOUNT = 1 * 1e3; // 1 USDAI (6 decimals)
    
    // Contract instances
    Deployer public deployer;
    BoringVault vault;
    TellerWithMultiAssetSupport teller;
    ArcticArchitectureLens lens;
    AccountantWithRateProviders accountant;

    function setUp() public {
        vm.createSelectFork("mainnet");
        setSourceChainName("sepolia");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        vault = BoringVault(payable(previoussSuperUSDVault));
        teller = TellerWithMultiAssetSupport(deployer.getAddress(sUsdaiVaultTellerName));
        lens = ArcticArchitectureLens(deployer.getAddress(sUsdaiArcticArchitectureLensName));
        accountant = AccountantWithRateProviders(deployer.getAddress(sUsdaiVaultAccountantName));

        console.log("vault", address(vault));
        console.log("teller", address(teller));
        console.log("lens", address(lens));
        console.log("accountant", address(accountant));
    }

    function run() public {
        // Get the private key from environment variable
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        
        // Start broadcasting transactions
        vm.startBroadcast(privateKey);
        
        // Deposit USDAI
        if (USDAI.balanceOf(user) >= USDAI_DEPOSIT_AMOUNT) {
            console.log("\n=== Depositing USDAI ===");
            
            // Calculate expected shares
            uint256 expectedUsdaiShares = lens.previewDeposit(
                USDAI,
                USDAI_DEPOSIT_AMOUNT,
                vault,
                accountant
            );
            console.log("Expected shares from USDAI deposit:", expectedUsdaiShares / 1e6);
            
            // Approve USDAI for deposit
            USDAI.approve(address(vault), USDAI_DEPOSIT_AMOUNT);
            console.log("USDAI approved for deposit");
            
            // Deposit USDAI
            uint256 sharesBefore = vault.balanceOf(user);
            teller.deposit(USDAI, USDAI_DEPOSIT_AMOUNT, 0);
            uint256 sharesAfter = vault.balanceOf(user);
            
            console.log("Actual shares received:", (sharesAfter - sharesBefore) / 1e6);
        } else {
            console.log("Insufficient USDAI balance for deposit");
        }
        
        vm.stopBroadcast();
    }
}