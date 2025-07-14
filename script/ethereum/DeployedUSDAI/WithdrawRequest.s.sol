// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
import {AtomicQueue} from "src/atomic-queue/AtomicQueue.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

contract USDAIWithdrawRequestScript is Script, MainnetAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    BoringVault vault;
    TellerWithMultiAssetSupport teller;
    ArcticArchitectureLens lens;
    AccountantWithRateProviders accountant;
    AtomicQueue queue;

    // User's initial share balance
    uint256 initialShares;
    uint256 withdrawShares;

    function setUp() public {
        vm.createSelectFork("mainnet");
        setSourceChainName("sepolia");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        vault = BoringVault(payable(previousVault));
        teller = TellerWithMultiAssetSupport(deployer.getAddress(UsdaiVaultTellerName));
        lens = ArcticArchitectureLens(deployer.getAddress(UsdaiArcticArchitectureLensName));
        accountant = AccountantWithRateProviders(deployer.getAddress(UsdaiVaultAccountantName));
        queue = AtomicQueue(deployer.getAddress(UsdaiVaultQueueName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        
        initialShares = vault.balanceOf(user);
        
        withdrawShares = 1 * 1e3;
        vm.startBroadcast(privateKey);
        
        console.log("=== Initial State ===");
        console.log("User address:", user);
        console.log("USDC balance:", USDC.balanceOf(user) / 1e6, "USDC");
        console.log("Vault share balance:", vault.balanceOf(user) / 1e6, "shares");
        
        uint256 sharesValue = lens.balanceOfInAssets(user, vault, accountant);
        console.log("Value of shares in USDC:", sharesValue / 1e6, "USDC");
        
        // Check if user has shares to withdraw
        if (initialShares > withdrawShares) {
            console.log("\n=== Requesting Withdrawal via Queue ===");
            console.log("Requesting withdrawal of shares amount:", withdrawShares / 1e6, "shares");
            
            // Approve queue to spend shares
            vault.approve(address(queue), withdrawShares);

            // Create atomic request
            AtomicQueue.AtomicRequest memory request = AtomicQueue.AtomicRequest({
                deadline: uint64(block.timestamp + 10000 minutes), 
                atomicPrice: uint88(1e6),
                offerAmount: uint96(withdrawShares),
                inSolve: false
            });

            // Send request to queue
            queue.updateAtomicRequest(vault, USDT, request);

            console.log("Withdrawal request created");

            // Get the request details
            AtomicQueue.AtomicRequest memory userRequest = queue.getUserAtomicRequest(user, vault, USDT);
            console.log("\n=== Withdraw Request Details ===");
            console.log("Deadline:", userRequest.deadline);
            console.log("Atomic Price:", uint256(userRequest.atomicPrice) / 1e6);
            console.log("Offer Amount (shares):", uint256(userRequest.offerAmount) / 1e6);
            console.log("In Solve:", userRequest.inSolve);

        } else {
            console.log("No shares available for withdrawal");
        }
        
        vm.stopBroadcast();
    }
}
