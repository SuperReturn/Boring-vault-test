// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;
import "forge-std/Script.sol";
import {PlumeAddresses} from "test/resources/PlumeAddresses.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {MerkleProofLib} from "@solmate/utils/MerkleProofLib.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {console} from "forge-std/console.sol";

/*
notice possible issues:
1. sepolia operation is totally diff from mainnet, need to rewrite all logic for mainnet
example tx: https://sepolia.etherscan.io/tx/0x563c1e3daaeb60ac16d203040f2aeb9c15b25dc96f8c2be071b36af9625e6a87
*/

contract MorphoOp is Script, PlumeAddresses, MerkleTreeHelper, ContractNames {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using Address for address;

    Deployer public deployer;
    BoringVault vault;
    ManagerWithMerkleVerification manager;
    // address re7pUSD = 0xc0Df5784f28046D11813356919B869dDA5815B16;
    // uint256 PUSDSupplyAmount =1e3;

    function setUp() external {
        vm.createSelectFork("plume");
        setSourceChainName("plume");
        
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        vault = BoringVault(payable(previoussuperUSD));
        manager = ManagerWithMerkleVerification(deployer.getAddress(UsdaiVaultManagerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // address auth = vm.addr(privateKey);
        // uint256 strategist = vm.envUint("PLUME_STRATEGIST_MORPHO");
        
        vm.startBroadcast(privateKey);
        
        setAddress(true, plume, "boringVault", previoussuperUSD);
        setAddress(true, plume, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, plume, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, plume, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName));

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        _addMorphoLeafs(leafs, address(vault), morphoVaults);

        // 2. Generate the merkle tree and get the root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        // Approve PUSD
        // Deposit PUSD
        uint256 opsAmt = 2;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[0];
        manageLeafs[1] = leafs[1];

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // 4. Prepare the action data
        address[] memory targets = new address[](opsAmt);
        targets[0] = getAddress(sourceChain, "PUSD");
        targets[1] = 0xc0Df5784f28046D11813356919B869dDA5815B16;

        bytes[] memory targetData = new bytes[](opsAmt);

        targetData[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            0xc0Df5784f28046D11813356919B869dDA5815B16,
            type(uint256).max
        );

        targetData[1] = abi.encodeWithSignature(
            "deposit(uint256,address)",
            501000e6,
            address(vault)
        );

        // targetData[1] = abi.encodeWithSignature(
        //     "withdraw(uint256,address,address)",
        //     1e6, // assets
        //     address(vault), // receiver
        //     address(vault)  // owner
        // );

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName);
        decodersAndSanitizers[1] = deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName);

        uint256[] memory values = new uint256[](opsAmt);

        // extra
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs("./leafs/MorphoLeafs.json", leafs, merkleRoot, manageTree);

        manager.setManageRoot(vm.addr(vm.envUint("PLUME_STRATEGIST_MORPHO")), merkleRoot);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("PLUME_STRATEGIST_MORPHO"));

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
