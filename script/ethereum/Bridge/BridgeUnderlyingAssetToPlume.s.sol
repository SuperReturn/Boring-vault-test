// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {EthereumAddresses} from "test/resources/EthereumAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

struct BridgeData {
    uint32 chainSelector;
    address destinationChainReceiver;
    ERC20 bridgeFeeToken;
    uint64 messageGas;
    bytes data;
}

struct PredicateMessage {
    // the unique identifier for the task
    string taskId;
    // the expiration block number for the task
    uint256 expireByBlockNumber;
    // the operators that have signed the task
    address[] signerAddresses;
    // the signatures of the operators that have signed the task
    bytes[] signatures;
}

interface ICrossChainTeller {
    function previewFee(uint256 shareAmount, BridgeData calldata data) external view returns (uint256);
    function depositAndBridge(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        BridgeData calldata data,
        ICrossChainTeller teller,
        PredicateMessage calldata predicateMessage
    ) external payable;
}

/**
 * @title USDAI Deposit Integration Test
 * @notice This script demonstrates how to deposit USDC into the USDAI vault on Sepolia
 * @dev Run with: forge script script/USDAIIntegrationTest/Deposit.sol --rpc-url $MINATO_RPC_URL
 */
contract BridgeUnderlyingAssetToPlumeScript is Script, EthereumAddresses, ContractNames, MerkleTreeHelper {
    BoringVault vault;
    Deployer deployer;
    function setUp() public {
        vm.createSelectFork("mainnet");
        setSourceChainName("mainnet");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        vault = BoringVault(payable(deployer.getAddress(UsdaiVaultName)));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // address user = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        address tellerAddress1 = 0x16424eDF021697E34b800e1D98857536B0f2287B;
        address tellerAddress2 = 0x6104fe10ca937a086ba7AdbD0910A4733d380cB6;
        address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        ICrossChainTeller teller1 = ICrossChainTeller(tellerAddress1); // for preview fee
        ICrossChainTeller teller2 = ICrossChainTeller(tellerAddress2); // for deposit and bridge
        ICrossChainTeller officialTeller = ICrossChainTeller(0x16424eDF021697E34b800e1D98857536B0f2287B);

        uint256 depositAmount = 1 * 1e6; 
        uint256 minimumMint = depositAmount;

        BridgeData memory bridgeData = BridgeData({
            chainSelector: 30370,
            destinationChainReceiver: address(vault),
            bridgeFeeToken: ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            messageGas: 100000,
            data: abi.encode(0)
        });

        uint256 fee = teller1.previewFee(depositAmount, bridgeData);

        // get from the api: https://pusd.plume.org/api/compliance?user=0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB&chainId=30370&isDepositAndBridge=true
        PredicateMessage memory predicateMessage = PredicateMessage({
            taskId: "14232f82-21d6-4f99-a30e-43018e08f83c",
            expireByBlockNumber: 1749813902,
            signerAddresses: new address[](1),
            signatures: new bytes[](1)
        });
        predicateMessage.signerAddresses[0] = 0xDAc74b6f9B3609E914c924eB87Adff87A30fcDf6;
        predicateMessage.signatures[0] = hex"ff18f49c61f10e9c009eecfd78470160bfcdad0cef5621c752b96dbf08a9f2295fed5636ac6b013c9dbcb8f0a6fa99c129deea24f52960ab1551cfc54b4db2a41b";

        // usdc.approve(tellerAddress2, depositAmount);

        // teller2.depositAndBridge{value: fee}(
        //     usdc,
        //     depositAmount,
        //     minimumMint,
        //     bridgeData,
        //     officialTeller,
        //     predicateMessage
        // );

        uint256 opsAmt = 2;
        address[] memory targets = new address[](opsAmt);
        targets[0] = usdcAddress; // approve
        targets[1] = address(teller2); // depositAndBridge

        bytes[] memory targetData = new bytes[](opsAmt);
        targetData[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            tellerAddress2,
            depositAmount
        );
        targetData[1] = abi.encodeWithSignature(
            "depositAndBridge(address,uint256,uint256,(uint32,address,address,uint64,bytes),address,(string,uint256,address[],bytes[]))",
            usdcAddress,
            depositAmount,
            minimumMint,
            bridgeData,
            address(officialTeller),
            predicateMessage
        );

        uint256[] memory values = new uint256[](opsAmt);
        values[0] = 0;      
        values[1] = fee;    

        (bool sent, ) = address(vault).call{value: fee}("");
        require(sent, "Failed to fund vault");

        vault.manage(targets, targetData, values);

        vm.stopBroadcast();
    }
}