// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {PlumeAddresses} from "test/resources/PlumeAddresses.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {WithdrawZapTeller, ZapAtomicRequest} from "src/zaps/WithdrawZapTeller.sol";

contract SolveByZapScript is Script, PlumeAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    WithdrawZapTeller public withdrawZapTeller;

    // User's initial share balance
    uint256 withdrawShares;

    function setUp() public {
        vm.createSelectFork("plume");
        setSourceChainName("plume");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        withdrawZapTeller = WithdrawZapTeller(deployer.getAddress(WithdrawZapTellerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PLUME_STRATEGIST_MERKL");
        address user = vm.addr(privateKey);
        
        vm.startBroadcast(privateKey);
        // Get user's zap withdrawal requests
        (bytes32[] memory requestIds, ZapAtomicRequest[] memory zapRequests) = withdrawZapTeller.getZapExistingWithdrawRequestsByUser(user);
        require(requestIds.length > 0, "No zap requests found");
        
        // Solve the first zap request
        withdrawZapTeller.solveByZap(zapRequests[0]);
        
        vm.stopBroadcast();
    }
}
