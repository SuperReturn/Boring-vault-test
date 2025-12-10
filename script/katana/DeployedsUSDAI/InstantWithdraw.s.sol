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

contract sUSDAIInstantWithdrawScript is Script, KatanaAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    BoringVault boringVault;
    TellerWithMultiAssetSupport teller;
    ArcticArchitectureLens lens;
    AccountantWithRateProviders accountant;
    AtomicQueue queue;

    function setUp() public {
        vm.createSelectFork("katana");
        setSourceChainName("katana");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        boringVault = BoringVault(payable(deployer.getAddress(sUsdaiVaultName)));
        teller = TellerWithMultiAssetSupport(deployer.getAddress(sUsdaiVaultTellerName));
        lens = ArcticArchitectureLens(deployer.getAddress(sUsdaiArcticArchitectureLensName));
        accountant = AccountantWithRateProviders(deployer.getAddress(sUsdaiVaultAccountantName));
        queue = AtomicQueue(deployer.getAddress(sUsdaiVaultQueueName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        vm.startBroadcast(privateKey);
        ERC20(address(boringVault)).approve(address(queue), 1e5);
        queue.instantWithdraw(ERC20(address(boringVault)), USDAI, 1e5, 0, teller);
        
        vm.stopBroadcast();
    }
}
