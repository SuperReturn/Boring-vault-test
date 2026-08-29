// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {PlumeAddresses} from "test/resources/PlumeAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";

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
    function deposit(
        address depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address recipient,
        address teller,
        PredicateMessage calldata predicateMessage
    ) external payable;
}

/**
 * @title USDAI Deposit Integration Test
 * @notice This script demonstrates how to deposit USDC into the USDAI vault on Sepolia
 * @dev Run with: forge script script/USDAIIntegrationTest/Deposit.sol --rpc-url $MINATO_RPC_URL
 */
contract SwapUSDCScript is Script, PlumeAddresses, ContractNames, MerkleTreeHelper {
    BoringVault vault;
    Deployer deployer;
    ManagerWithMerkleVerification manager;

    function setUp() public {
        vm.createSelectFork("plume");
        setSourceChainName("plume");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        vault = BoringVault(payable(previoussuperUSD));
        manager = ManagerWithMerkleVerification(deployer.getAddress(UsdaiVaultManagerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // address user = vm.addr(privateKey);

        // uint256 strategist = vm.envUint("PLUME_STRATEGIST_PUSD");
        vm.startBroadcast(privateKey);

        setAddress(true, plume, "boringVault", previoussuperUSD);
        setAddress(true, plume, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, plume, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, plume, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiPUSDDecoderAndSanitizerName));

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        _addPUSDFunctionLeafs(leafs, address(vault), 0x6104fe10ca937a086ba7AdbD0910A4733d380cB6);

        // 2. Generate the merkle tree and get the root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute
        uint256 opsAmt = 2;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[0]; // USDC approval
        manageLeafs[1] = leafs[1]; // USDC deposit

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // ICrossChainTeller teller2 = ICrossChainTeller(0x6104fe10ca937a086ba7AdbD0910A4733d380cB6); 

        uint256 depositAmount = 90000 * 1e6; 
        uint256 minimumMint = depositAmount;

        // get from the api: https://pusd.plume.org/api/compliance?user=0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB&chainId=98866&isDepositAndBridge=false&isZapper=false
        // latest: https://api-dev.nest.credit//v1/user/0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB/compliance?chainId=98866&isDepositAndBridge=false&isZapper=false
        PredicateMessage memory predicateMessage = PredicateMessage({
            taskId: "a4522ec1-fec3-4a2b-83c2-09c4c3c87bdd",
            expireByBlockNumber: 1767952954,
            signerAddresses: new address[](1),
            signatures: new bytes[](1)
        });
        predicateMessage.signerAddresses[0] = 0x5f936C12E43181662e85814b0cFd10334A33E5A1;
        // remove 0x in api signatures
        predicateMessage.signatures[0] = hex"b130687190934d8dd87d42acd890f9dd87465218f0145b7cbab3def5f387f49e60b421b7bb2f8691b9ddf7f9235bd38088a2ba78f8a949babc00bc85827b2e471b";

        // usdc.approve(tellerAddress2, depositAmount);

        // teller2.depositAndBridge{value: fee}(
        //     usdc,
        //     depositAmount,
        //     minimumMint,
        //     bridgeData,
        //     officialTeller,
        //     predicateMessage
        // );

        address[] memory targets = new address[](opsAmt);
        targets[0] = getAddress(sourceChain, "USDC"); // approve

        targets[1] = address(0x6104fe10ca937a086ba7AdbD0910A4733d380cB6); // depositAndBridge

        bytes[] memory targetData = new bytes[](opsAmt);
        targetData[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(0x6104fe10ca937a086ba7AdbD0910A4733d380cB6),
            depositAmount
        );
        targetData[1] = abi.encodeWithSignature(
            "deposit(address,uint256,uint256,address,address,(string,uint256,address[],bytes[]))",
            getAddress(sourceChain, "USDC"),
            depositAmount,
            minimumMint,
            address(vault),
            address(0x16424eDF021697E34b800e1D98857536B0f2287B),
            predicateMessage
        );

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiPUSDDecoderAndSanitizerName);
        decodersAndSanitizers[1] = deployer.getAddress(UsdaiPUSDDecoderAndSanitizerName);

        uint256[] memory values = new uint256[](opsAmt);
        values[0] = 0;      
        values[1] = 0;    

        // extra
        // string memory filePath = "./leafs/PUSDLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];
       
        _generateLeafs("./leafs/PUSDLeafs.json", leafs, merkleRoot, manageTree);

        manager.setManageRoot(vm.addr(vm.envUint("PLUME_STRATEGIST_PUSD")), merkleRoot);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("PLUME_STRATEGIST_PUSD"));

        manager.manageVaultWithMerkleVerification(
            manageProofs,
            decodersAndSanitizers,
            targets,
            targetData,
            values
        );

        vm.stopBroadcast();
    }
}