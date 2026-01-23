// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {ArbitrumAddresses} from "test/resources/ArbitrumAddresses.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

contract USDAICancelRequestScript is Script, ArbitrumAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    BoringVault boringVault;
    TellerWithMultiAssetSupport teller;
    ArcticArchitectureLens lens;
    AccountantWithRateProviders accountant;
    AtomicQueue queue;

    function setUp() public {
        vm.createSelectFork("arbitrum");
        setSourceChainName("arbitrum");
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

        vm.startBroadcast(privateKey);
        
        // Get all existing withdraw requests for the user
        (bytes32[] memory requestIds, AtomicRequest[] memory requests) = queue.getExistingWithdrawRequests();
        
        console.log("Total requests for user:", requests.length);
        console.log("Current timestamp:", block.timestamp);
        console.log("Expired requests:");
        
        uint256 expiredCount = 0;
        
        // First pass: count expired requests and log them
        for (uint256 i = 0; i < requests.length; i++) {
            AtomicRequest memory request = requests[i];
            
            // Check if request is expired
            if (block.timestamp > request.deadline) {
                expiredCount++;
                console.log("-------------------");
                console.log("Request ID:", vm.toString(requestIds[i]));
                console.log("User:", request.user);
                console.log("Offer Token:", request.offer);
                console.log("Want Token:", request.want);
                console.log("Offer Amount:", request.offerAmount);
                console.log("Deadline:", request.deadline);
                console.log("Creation Time:", request.creationTime);
                console.log("Expired by:", block.timestamp - request.deadline, "seconds");
            }
        }
        
        // Second pass: collect expired requests for batch cancellation
        if (expiredCount > 0) {
            AtomicRequest[] memory expiredRequests = new AtomicRequest[](expiredCount);
            uint256 expiredIndex = 0;
            
            for (uint256 i = 0; i < requests.length; i++) {
                if (block.timestamp > requests[i].deadline) {
                    expiredRequests[expiredIndex] = requests[i];
                    expiredIndex++;
                }
            }
            
            console.log("Cancelling", expiredCount, "expired requests...");
            queue.cancelAtomicRequestByAdmin(expiredRequests);
            console.log("Successfully cancelled expired requests");
        } else {
            console.log("No expired requests found to cancel");
        }
        
        console.log("-------------------");
        console.log("Total expired requests:", expiredCount);
        console.log("Total active requests:", requests.length - expiredCount);
        
        vm.stopBroadcast();
    }
}