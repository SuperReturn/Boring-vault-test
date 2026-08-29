// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {SoneiumAddresses} from "test/resources/SoneiumAddresses.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

contract USDAICancelRequestScript is Script, SoneiumAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    BoringVault boringVault;
    AtomicQueue queue;

    function setUp() public {
        vm.createSelectFork("soneium");
        setSourceChainName("soneium");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        boringVault = BoringVault(payable(previoussuperUSD));
        queue = AtomicQueue(deployer.getAddress(UsdaiVaultQueueName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        console.log("signer:", user);

        vm.startBroadcast(privateKey);
        
        (bytes32[] memory requestIds, AtomicRequest[] memory requests) = queue.getExistingWithdrawRequests();

        console.log("Current block.timestamp:", block.timestamp);
        console.log("requestIds length:", requestIds.length);

        uint256 expiredCount;
        for (uint256 i = 0; i < requests.length; i++) {
            if (block.timestamp > requests[i].deadline) {
                expiredCount++;
                console.log("expired requestId:", vm.toString(requestIds[i]));
                console.log("  deadline:", requests[i].deadline);
            }
        }
        console.log("expired count:", expiredCount);

        if (expiredCount > 0) {
            AtomicRequest[] memory expiredRequests = new AtomicRequest[](expiredCount);
            uint256 idx;
            for (uint256 i = 0; i < requests.length; i++) {
                if (block.timestamp > requests[i].deadline) {
                    expiredRequests[idx] = requests[i];
                    unchecked {
                        ++idx;
                    }
                }
            }
            console.log("expiredRequests length:", expiredRequests.length);
            // cancelAtomicRequestByAdmin takes AtomicRequest[]; batch all expired in one call
            queue.cancelAtomicRequestByAdmin(expiredRequests);
            console.log("cancelAtomicRequestByAdmin done for", expiredCount, "expired requests");
        }
        
        vm.stopBroadcast();
    }
}
