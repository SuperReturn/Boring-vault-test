// SPDX-License-Identifier: Apache-2.0
//
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {SoneiumAddresses} from "test/resources/SoneiumAddresses.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {WithdrawZapTeller, ZapAtomicRequest} from "src/zaps/WithdrawZapTeller.sol";

contract USDAICancelExpireRequestInWithdrawZapTellerScript is Script, SoneiumAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    BoringVault boringVault;
    AtomicQueue queue;
    WithdrawZapTeller public withdrawZapTeller;

    function setUp() public {
        vm.createSelectFork("soneium");
        setSourceChainName("soneium");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));

        // Initialize contract instances
        boringVault = BoringVault(payable(previoussuperUSD));
        queue = AtomicQueue(deployer.getAddress(UsdaiVaultQueueName));
        withdrawZapTeller = WithdrawZapTeller(0x5E305dcB433D80519Ce2B5cb0f6A05Edb42776d2);
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address signer = vm.addr(privateKey);
        console.log("signer:", signer);

        address user = 0x1b4862F983AA573518B612f1bb1579F4b02796CB;
        ERC20 sSuperUSD = ERC20(withdrawZapTeller.sSuperUSD());

        (bytes32[] memory requestIds, ZapAtomicRequest[] memory requests) =
            withdrawZapTeller.getZapExistingWithdrawRequestsByUser(user);

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

        ZapAtomicRequest[] memory expiredRequests = new ZapAtomicRequest[](expiredCount);
        uint256 idx;
        for (uint256 i = 0; i < requests.length; i++) {
            if (block.timestamp > requests[i].deadline) {
                expiredRequests[idx] = requests[i];
                unchecked {
                    ++idx;
                }
            }
        }

        uint256 balanceBefore = sSuperUSD.balanceOf(user);
        console.log("user sSuperUSD balance before:", balanceBefore);

        vm.startBroadcast(privateKey);
        withdrawZapTeller.cancelZapAtomicRequestByAdmin(expiredRequests);
        vm.stopBroadcast();

        uint256 balanceAfter = sSuperUSD.balanceOf(user);
        console.log("user sSuperUSD balance after:", balanceAfter);
        require(balanceAfter > balanceBefore, "user sSuperUSD balance not restored after cancel");
        console.log("cancelZapAtomicRequestByAdmin done for", expiredCount, "expired requests");
    }
}
