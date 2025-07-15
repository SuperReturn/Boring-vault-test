// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {AtomicQueue} from "src/atomic-queue/AtomicQueue.sol";
import {AtomicSolverV4} from "src/atomic-queue/AtomicSolverV4.sol";
import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {console} from "forge-std/console.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";

contract SolveWithdrawRequestScript is Script, MainnetAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    AtomicQueue queue;
    AtomicSolverV4 solver;
    BoringVault vault;
    TellerWithMultiAssetSupport teller;
    
    function setUp() public {
        vm.createSelectFork("mainnet");
        setSourceChainName("sepolia");
        
        // Initialize contract instances
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        vault = BoringVault(payable(previousVault));
        queue = AtomicQueue(deployer.getAddress(UsdaiVaultQueueName));
        solver = AtomicSolverV4(deployer.getAddress(UsdaiVaultQueueSolverName));
        teller = TellerWithMultiAssetSupport(deployer.getAddress(UsdaiVaultTellerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(privateKey);
        
        address user = vm.addr(privateKey);
        AtomicQueue.AtomicRequest memory request = queue.getUserAtomicRequest(user, vault, USDC);
        
        // Calculate required assets based on atomic price
        uint256 assetsRequired = (uint256(request.offerAmount) * uint256(request.atomicPrice)) / 1e6;
        
        // Prepare solver parameters
        address[] memory users = new address[](1);
        users[0] = user;
        
        // Set reasonable limits
        uint256 minAssetDelta = 0; // Minimum profit we want to make
        uint256 maxAssets = assetsRequired; // Maximum assets we're willing to spend
        
        // Make sure solver has enough USDC approved
        USDC.approve(address(solver), maxAssets);
        
        // Call redeemSolve
        solver.redeemSolve(
            queue,
            ERC20(address(vault)), // offer (vault shares)
            USDC, // want (USDC)
            users,
            minAssetDelta,
            maxAssets,
            teller
        );
        
        vm.stopBroadcast();
        
        console.log("=== Solve Complete ===");
        console.log("User:", user);
        console.log("Shares Solved:", request.offerAmount);
        console.log("Assets Required:", assetsRequired);
    }
}
