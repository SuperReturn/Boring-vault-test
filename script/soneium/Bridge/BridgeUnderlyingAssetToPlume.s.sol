// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {LayerZeroTeller} from "src/base/Roles/CrossChain/Bridges/LayerZero/LayerZeroTeller.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {SoneiumAddresses} from "test/resources/SoneiumAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {IStargatePool} from "src/interfaces/IStargatePool.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {console} from "forge-std/console.sol";

/**
 * @title USDAI Deposit Integration Test
 * @notice This script demonstrates how to deposit USDC and ASTR into the USDAI vault on Minato
 * @dev Run with: forge script script/USDAIIntegrationTest/Deposit.sol --rpc-url $MINATO_RPC_URL
 */
contract BridgeUnderlyingAssetToPlumeScript is Script, SoneiumAddresses, ContractNames, MerkleTreeHelper {
    Deployer public deployer;
    BoringVault vault;
    ManagerWithMerkleVerification manager;
    address stargatePoolUSDC = address(0x45f1A95A4D3f3836523F5c83673c797f4d4d263B);

    uint256 public sharesToBridge = 50000e6;
    ERC20 internal constant NATIVE_ERC20 = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    function setUp() public {
        vm.createSelectFork("soneium");
        setSourceChainName("soneium");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        vault = BoringVault(payable(previoussuperUSD));
        manager = ManagerWithMerkleVerification(deployer.getAddress(UsdaiVaultManagerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        // uint256 strategist = vm.envUint("SONEIUM_STRATEGIST_LAYERZERO");
        vm.startBroadcast(privateKey);

        setAddress(true, soneium, "boringVault", previoussuperUSD);
        setAddress(true, soneium, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, soneium, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, soneium, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiLayerZeroDecoderAndSanitizerName));

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        _addLayerZeroLeafs(leafs, ERC20(getAddress(sourceChain, "USDC")), stargatePoolUSDC, layerZeroPlumeEndpointId);

        // 2. Generate the merkle tree and get the root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute
        uint256 opsAmt = 2;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[0]; // USDC approval
        manageLeafs[1] = leafs[1]; // USDC send

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        IStargatePool.SendParam memory sendParam = IStargatePool.SendParam({
            dstEid: uint32(layerZeroPlumeEndpointId),
            to: bytes32(uint256(uint160(address(vault)))),
            amountLD: sharesToBridge,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        IStargatePool.MessagingFee memory fee = IStargatePool(stargatePoolUSDC).quoteSend(
            sendParam,
            false
        );

        //  IStargatePool(stargatePoolUSDC).send{value: fee.nativeFee}(
        //     sendParam,
        //     fee,
        //     vm.addr(privateKey)
        // );

        address[] memory targets = new address[](opsAmt);
        targets[0] = address(getAddress(sourceChain, "USDC"));
        targets[1] = address(stargatePoolUSDC);

        bytes[] memory targetData = new bytes[](opsAmt);
        targetData[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(stargatePoolUSDC),
            sharesToBridge
        );
        targetData[1] = abi.encodeWithSignature(
            "send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)",
            sendParam,
            fee,
            address(vault)  
        );       

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiLayerZeroDecoderAndSanitizerName);
        decodersAndSanitizers[1] = deployer.getAddress(UsdaiLayerZeroDecoderAndSanitizerName);

        uint256[] memory values = new uint256[](opsAmt);  
        values[0] = 0;    
        values[1] = fee.nativeFee;    

        console.log("fee.nativeFee", fee.nativeFee);

        (bool sent, ) = address(vault).call{value: fee.nativeFee}("");
        require(sent, "Failed to fund vault");

        // extra
        // string memory filePath = "./leafs/LayerZeroLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];
       
        _generateLeafs("./leafs/LayerZeroSoneiumToPlumeLeafs.json", leafs, merkleRoot, manageTree);

        manager.setManageRoot(vm.addr(vm.envUint("SONEIUM_STRATEGIST_LAYERZERO")), merkleRoot);
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("SONEIUM_STRATEGIST_LAYERZERO"));
        
        // 5. Execute the actions through the manager
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