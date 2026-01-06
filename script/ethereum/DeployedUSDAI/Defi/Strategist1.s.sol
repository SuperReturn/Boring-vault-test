// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;
import "forge-std/Script.sol";
import {EthereumAddresses} from "test/resources/EthereumAddresses.sol";
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
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";

contract Strategist1 is Script, EthereumAddresses, MerkleTreeHelper, ContractNames {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using Address for address;

    Deployer public deployer;
    BoringVault vault;
    ManagerWithMerkleVerification manager;

    function setUp() external {
        vm.createSelectFork("mainnet");
        setSourceChainName("mainnet");
        
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        vault = BoringVault(payable(previoussuperUSD));
        manager = ManagerWithMerkleVerification(deployer.getAddress(UsdaiVaultManagerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // address auth = vm.addr(privateKey);
        
        vm.startBroadcast(privateKey);
        
        setAddress(true, mainnet, "boringVault", previoussuperUSD);
        setAddress(true, mainnet, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, mainnet, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiBaseDecoderAndSanitizerName));
        _addApprovalLeafs(leafs, ERC20(getAddress(sourceChain, "USDC")), 0x789AE139dBC4A1fd79981F8A9734DD448CFD3b2c);
        _addTransferLeafs(leafs, ERC20(getAddress(sourceChain, "USDC")), 0x62d9113BFf4414e7D3600FfB4d6255D29e5CFc42);

        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiEulerDecoderAndSanitizerName));
        _addEulerLeafs(eulerVaults, leafs);


// transfer USDC
        // setAddress(true, mainnet, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiBaseDecoderAndSanitizerName));

        // // 2. Generate the merkle tree and get the root
        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // // 3. Generate proofs for the actions you want to execute
        // uint256 opsAmt = 2;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[0];
        // manageLeafs[1] = leafs[1];
        // // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data - both operations target USDC token
        // address[] memory targets = new address[](opsAmt);
        // targets[0] = getAddress(sourceChain, "USDC"); // approve
        // targets[1] = getAddress(sourceChain, "USDC"); // transfer

        // bytes[] memory targetData = new bytes[](opsAmt);
        // targetData[0] = abi.encodeWithSignature("approve(address,uint256)", 0x789AE139dBC4A1fd79981F8A9734DD448CFD3b2c, type(uint256).max);
        // targetData[1] = abi.encodeWithSignature("transfer(address,uint256)", 0x62d9113BFf4414e7D3600FfB4d6255D29e5CFc42, 1e6);

        // address[] memory decodersAndSanitizers = new address[](opsAmt);  
        // decodersAndSanitizers[0] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);
        // decodersAndSanitizers[1] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);

// Euler Op
        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiEulerDecoderAndSanitizerName));
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        uint256 opsAmt = 2;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[2];
        manageLeafs[1] = leafs[3];
        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);
        // 4. Prepare the action data
        address[] memory targets = new address[](opsAmt);
        targets[0] = getAddress(sourceChain, "USDC");
        targets[1] = eulerVaults[0];

        bytes[] memory targetData = new bytes[](opsAmt);

        targetData[0] = abi.encodeWithSignature("approve(address,uint256)", eulerVaults[0], type(uint256).max);
        targetData[1] = abi.encodeWithSignature("deposit(uint256,address)", 1e3, address(vault));

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiEulerDecoderAndSanitizerName);
        decodersAndSanitizers[1] = deployer.getAddress(UsdaiEulerDecoderAndSanitizerName);



        uint256[] memory values = new uint256[](opsAmt);

        // extra
        string memory filePath = "./leafs/Strategist1EthereumLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs(filePath, leafs, merkleRoot, manageTree);

        manager.setManageRoot(vm.addr(vm.envUint("MAINNET_STRATEGIST")), merkleRoot);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("MAINNET_STRATEGIST"));

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
