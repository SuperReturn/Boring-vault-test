// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;
import "forge-std/Script.sol";
import {KatanaAddresses} from "test/resources/KatanaAddresses.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {MerkleProofLib} from "@solmate/utils/MerkleProofLib.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BaseDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {console} from "forge-std/console.sol";

contract BaseOp is Script, KatanaAddresses, MerkleTreeHelper, ContractNames {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using Address for address;

    Deployer public deployer;
    BoringVault vault;
    ManagerWithMerkleVerification manager;

    function setUp() external {
        vm.createSelectFork("katana");
        setSourceChainName("katana");
        
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        vault = BoringVault(payable(previoussuperUSD));
        manager = ManagerWithMerkleVerification(deployer.getAddress(UsdaiVaultManagerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        uint256 strategist = vm.envUint("PRIVATE_KEY");
        // address auth = vm.addr(privateKey);
        
        vm.startBroadcast(privateKey);
        
        setAddress(true, katana, "boringVault", previoussSuperUSD);
        setAddress(true, katana, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, katana, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, katana, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiBaseDecoderAndSanitizerName));

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        _addApprovalLeafs(leafs, ERC20(0x7F1f4b4b29f5058fA32CC7a97141b8D7e5ABDC2d), vm.addr(strategist));
        _addTransferLeafs(leafs, ERC20(0x7F1f4b4b29f5058fA32CC7a97141b8D7e5ABDC2d), 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4);

        // 2. Generate the merkle tree and get the root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute
        uint256 opsAmt = 2;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[0]; // USDC approval
        manageLeafs[1] = leafs[1]; // USDC transfer

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // 4. Prepare the action data - both operations target USDC token
        address[] memory targets = new address[](opsAmt);
        targets[0] = 0x7F1f4b4b29f5058fA32CC7a97141b8D7e5ABDC2d; // approve
        targets[1] = 0x7F1f4b4b29f5058fA32CC7a97141b8D7e5ABDC2d; // transfer

        bytes[] memory targetData = new bytes[](opsAmt);
        targetData[0] = abi.encodeWithSignature("approve(address,uint256)", vm.addr(strategist), type(uint256).max);
        targetData[1] = abi.encodeWithSignature("transfer(address,uint256)", 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4, 161677289380562578783);

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);
        decodersAndSanitizers[1] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);

        uint256[] memory values = new uint256[](opsAmt);

        // extra
        // string memory filePath = "./leafs/EthereumBaseLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];
       
        _generateLeafs("./leafs/KatanaBaseLeafs.json", leafs, merkleRoot, manageTree);

        manager.setManageRoot(vm.addr(strategist), merkleRoot);

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
