// SPDX-License-Identifier: Apache-2.0
// source .env && forge script script/soneium/DeployedUSDAI/rescueToken.s.sol --broadcast  --skip test 
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
import {Ownable2StepWTR} from "src/zaps/Ownable2StepWTR.sol";
import {CancelledAtomicRequests} from "script/soneium/DeployedUSDAI/CancelledAtomicRequests.sol";
import {CancelledAtomicRequests2} from "script/soneium/DeployedUSDAI/CancelledAtomicRequests2.sol";

contract RescueTokenScript is Script, SoneiumAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    BoringVault boringVault;
    AtomicQueue queue;
    WithdrawZapTeller zapTeller;

    mapping(address => uint256) public receiverBalanceBefore;
    mapping(address => uint256) public receiverExpectedAmount;
    mapping(address => bool) public receiverRecorded;
    mapping(address => bool) public receiverVerified;

    error SenderNotFound(uint96 offerAmount, uint64 creationTime);

    function setUp() public {
        vm.createSelectFork("soneium");
        setSourceChainName("soneium");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        boringVault = BoringVault(payable(previoussuperUSD));
        queue = AtomicQueue(deployer.getAddress(UsdaiVaultQueueName));
        zapTeller = WithdrawZapTeller(0x5E305dcB433D80519Ce2B5cb0f6A05Edb42776d2);
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address signer = vm.addr(privateKey);
        console.log("signer:", signer);

        vm.startBroadcast(privateKey);
        
        // 1. getExistingZapWithdrawRequests from zapTeller
        (, ZapAtomicRequest[] memory zapRequests) = zapTeller.getExistingZapWithdrawRequests();

        // 2. match cancelled AtomicRequests by offerAmount to zap sender, build RescueTokenParam[]
        // AtomicRequest[] memory cancelledRequests = CancelledAtomicRequests.get();
        AtomicRequest[] memory cancelledRequests = CancelledAtomicRequests2.get();
        Ownable2StepWTR.RescueTokenParam[] memory params =
            new Ownable2StepWTR.RescueTokenParam[](cancelledRequests.length);

        uint256 totalAmount;
        for (uint256 i = 0; i < cancelledRequests.length; i++) {
            AtomicRequest memory atomicReq = cancelledRequests[i];

            address receiver = _findSenderByOfferAmount(zapRequests, atomicReq);

            params[i] = Ownable2StepWTR.RescueTokenParam({
                token: atomicReq.offer,
                amount: atomicReq.offerAmount,
                receiver: receiver
            });
            totalAmount += atomicReq.offerAmount;

            console.log("rescue index:", i);
            console.log("  receiver:", receiver);
            console.log("  amount:", atomicReq.offerAmount);
        }

        // 3. check the request amount and length
        uint256 expectedAmount = 37198273165 - 50186663;
        // 1: manually done; 3: not to zap teller
        uint256 expectedLength = 117-1-3;


        require(totalAmount == expectedAmount, "totalAmount mismatch");
        require(params.length == expectedLength, "params length mismatch");

        console.log("totalAmount:", totalAmount);
        console.log("params length:", params.length);

        for (uint256 i = 0; i < params.length; i++) {
            console.log("token:", params[i].token);
            console.log("amount:", params[i].amount);
            console.log("receiver:", params[i].receiver);
        }

        // 4. record the receiver balance of the token in the mapping by using token.balanceOf(receiver)
        for (uint256 i = 0; i < params.length; i++) {
            address receiver = params[i].receiver;
            if (!receiverRecorded[receiver]) {
                receiverBalanceBefore[receiver] = ERC20(params[i].token).balanceOf(receiver);
                receiverRecorded[receiver] = true;
            }
            receiverExpectedAmount[receiver] += params[i].amount;
        }

        // 5. rescue token by admin
        zapTeller.rescueTokens(params);

        // 6. check the receiver balance of the token in the mapping by using receiverBalanceBefore
        for (uint256 i = 0; i < params.length; i++) {
            address receiver = params[i].receiver;
            if (receiverVerified[receiver]) continue;
            receiverVerified[receiver] = true;

            uint256 balanceAfter = ERC20(params[i].token).balanceOf(receiver);
            require(
                balanceAfter == receiverBalanceBefore[receiver] + receiverExpectedAmount[receiver],
                "receiver balance mismatch"
            );
            console.log("verified receiver:", receiver);
            console.log("  balance before:", receiverBalanceBefore[receiver]);
            console.log("  balance after:", balanceAfter);
        }

        vm.stopBroadcast();
    }

    function _findSenderByOfferAmount(ZapAtomicRequest[] memory zapRequests, AtomicRequest memory atomicReq)
        internal
        pure
        returns (address sender)
    {
        for (uint256 i = 0; i < zapRequests.length; i++) {
            ZapAtomicRequest memory zap = zapRequests[i];
            if (zap.offerAmount != atomicReq.offerAmount) continue;

            if (
                zap.creationTime == atomicReq.creationTime && zap.deadline == atomicReq.deadline
                    && zap.user == atomicReq.user && zap.offer == atomicReq.offer && zap.want == atomicReq.want
            ) {
                return zap.sender;
            }
        }

        revert SenderNotFound(atomicReq.offerAmount, atomicReq.creationTime);
    }
}
