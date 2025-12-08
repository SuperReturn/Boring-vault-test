// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {KatanaAddresses} from "test/resources/KatanaAddresses.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

contract USDAIWithdrawRequestScript is Script, KatanaAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    BoringVault boringVault;
    TellerWithMultiAssetSupport teller;
    ArcticArchitectureLens lens;
    AccountantWithRateProviders accountant;
    AtomicQueue queue;

    // User's initial share balance
    uint256 initialShares;
    uint256 withdrawShares;

    function setUp() public {
        vm.createSelectFork("katana");
        setSourceChainName("katana");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        boringVault = BoringVault(payable(previoussuperUSD));
        teller = TellerWithMultiAssetSupport(deployer.getAddress(UsdaiVaultTellerName));
        lens = ArcticArchitectureLens(deployer.getAddress(UsdaiArcticArchitectureLensName));
        accountant = AccountantWithRateProviders(deployer.getAddress(UsdaiVaultAccountantName));
        queue = AtomicQueue(deployer.getAddress(UsdaiVaultQueueName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        
        initialShares = boringVault.balanceOf(user);
        
        withdrawShares = 1 * 1e5;
        vm.startBroadcast(privateKey);

        // Check if user has shares to withdraw
        if (initialShares >= withdrawShares) {
            console.log("\n=== Requesting Withdrawal via Queue ===");
            console.log("Requesting withdrawal of shares amount:", withdrawShares / 1e6, "shares");
            
            // Approve queue to spend shares
            boringVault.approve(address(queue), withdrawShares);

            // Create atomic request
            AtomicRequest memory request = AtomicRequest({
                deadline: uint64(block.timestamp + 10000 minutes), 
                creationTime: uint64(block.timestamp),
                offerAmount: uint96(withdrawShares),
                user: user,
                offer: address(boringVault),
                want: address(USDC)
            });

            // Send request to queue
            queue.updateAtomicRequest(request);

            console.log("Withdrawal request created");

            // Get the request IDs and display the first one
            // bytes32[] memory requestIds = queue.getUserAtomicRequestIds(user, boringVault, USDC);
            // if (requestIds.length > 0) {
            //     console.log("Request ID:", uint256(requestIds[0]));
                
            //     // Decode request information from ID
            //     (,,,uint64 deadline, uint88 atomicPrice, uint96 offerAmount) = 
            //         abi.decode(requestIds[0], (address, address, address, uint64, uint88, uint96));
                
            //     console.log("Request details:");
            //     console.log("- Deadline:", deadline);
            //     console.log("- Atomic Price:", atomicPrice);
            //     console.log("- Offer Amount:", offerAmount);
            // }
        } else {
            console.log("No shares available for withdrawal");
        }
        
        vm.stopBroadcast();
    }
}
