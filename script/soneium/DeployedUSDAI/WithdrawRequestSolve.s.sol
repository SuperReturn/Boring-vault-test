// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";
import {AtomicSolverV4} from "src/atomic-queue/AtomicSolverV4.sol";
import {SoneiumAddresses} from "test/resources/SoneiumAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {console} from "forge-std/console.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";

contract SolveWithdrawRequestScript is Script, SoneiumAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    AtomicQueue queue;
    AtomicSolverV4 solver;
    BoringVault boringVault;
    TellerWithMultiAssetSupport teller;
    
    function setUp() public {
        vm.createSelectFork("soneium");
        setSourceChainName("soneium");
        
        // Initialize contract instances
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        boringVault = BoringVault(payable(previoussuperUSD));
        queue = AtomicQueue(deployer.getAddress(UsdaiVaultQueueName));
        solver = AtomicSolverV4(deployer.getAddress(UsdaiVaultQueueSolverName));
        teller = TellerWithMultiAssetSupport(deployer.getAddress(UsdaiVaultTellerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        
        vm.startBroadcast(privateKey);
        
        // Get user's request IDs
        (bytes32[] memory requestIds, AtomicRequest[] memory requests) = queue.getExistingWithdrawRequestsByUser(user);
        require(requestIds.length > 0, "No requests found");

        // Call redeemSolve
        solver.redeemSolve(
            queue,
            0,
            type(uint256).max,
            teller,
            requests[0]
        );
        
        vm.stopBroadcast();
        
        // console.log("=== Solve Complete ===");
        // console.log("User:", user);
        // console.log("Shares Solved:", offerAmount);
        // console.log("Assets Required:", assetsRequired);
        // console.log("Request Deadline:", deadline);
        // console.log("Atomic Price:", atomicPrice);
    }
}
