// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";
import {AtomicSolverV4} from "src/atomic-queue/AtomicSolverV4.sol";
import {SepoliaAddresses} from "test/resources/SepoliaAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {console} from "forge-std/console.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";

contract SolveWithdrawRequestScript is Script, SepoliaAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    AtomicQueue queue;
    AtomicSolverV4 solver;
    BoringVault boringVault;
    TellerWithMultiAssetSupport teller;
    
    function setUp() public {
        vm.createSelectFork("sepolia");
        setSourceChainName("sepolia");
        
        // Initialize contract instances
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        boringVault = BoringVault(payable(deployer.getAddress(sUsdaiVaultName)));
        queue = AtomicQueue(deployer.getAddress(sUsdaiVaultQueueName));
        solver = AtomicSolverV4(deployer.getAddress(sUsdaiVaultQueueSolverName));
        teller = TellerWithMultiAssetSupport(deployer.getAddress(sUsdaiVaultTellerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        
        vm.startBroadcast(privateKey);
        
        // Get user's request IDs
        (bytes32[] memory requestIds, AtomicRequest[] memory requests) = queue.getExistingWithdrawRequestsByUser(user);
        require(requestIds.length > 0, "No requests found");
        

        // Make sure solver has enough USDAI approved
        USDAI.approve(address(solver), type(uint256).max);
        
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
