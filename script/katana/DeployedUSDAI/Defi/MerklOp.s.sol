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
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {console} from "forge-std/console.sol";

/*
notice possible issues:
1. sepolia operation is totally diff from mainnet, need to rewrite all logic for mainnet
example tx: https://sepolia.etherscan.io/tx/0x563c1e3daaeb60ac16d203040f2aeb9c15b25dc96f8c2be071b36af9625e6a87
*/

contract MerklOp is Script, KatanaAddresses, MerkleTreeHelper, ContractNames {
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
        // address auth = vm.addr(privateKey);

        // uint256 strategist = vm.envUint("PLUME_STRATEGIST_MERKL");
        
        vm.startBroadcast(privateKey);
        
        setAddress(true, katana, "boringVault", previoussuperUSD);
        setAddress(true, katana, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, katana, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, katana, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMerklDecoderAndSanitizerName));

        /*
        claim params:
        https://api.merkl.xyz/v4/users/0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB/rewards?chainId=747474
        amount and proofs should be exactly same, otherwise it will revert
        */
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 70444065355932;

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        address[] memory tokens = new address[](1);
        tokens[0] = address(KAT);

        _addMerklLeafs(leafs, merklDistributor, tokens);

        // 2. Generate the merkle tree and get the root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        uint256 opsAmt = 1;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[0];

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // 4. Prepare the action data
        address[] memory targets = new address[](opsAmt);
        targets[0] = merklDistributor;

        bytes[] memory targetData = new bytes[](opsAmt);

        address[] memory users = new address[](1);
        users[0] = address(vault);

        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](16);
        proofs[0][0]  = 0x2a881e0370db5df7443f263e91aaa75507d9b8c21618d8b12309aa8d38f69647;
        proofs[0][1]  = 0xbe2e65b6be6eb1b47d495a8799d71bd4408b3edbbc390f64ca76f95e4fb64149;
        proofs[0][2]  = 0x697837abfcef0a8c5983b409fe80c2ce3bc813814ecfee32566c66060259c3d1;
        proofs[0][3]  = 0x067a877e03b56efef56ef39aab6817ddb5c446c09c518dbd2aeb36cc8b25fd29;
        proofs[0][4]  = 0x8e05ee8ad4bb4cf058de094aa022197488ba92ddaf1800b59ee6dda101f6e616;
        proofs[0][5]  = 0x7ba4b131bd550219ca90e8d1732209d7002057d8b3f356c535d2f17c96b069b1;
        proofs[0][6]  = 0x8d483a7da30671473c21c93cf5201338378e59e81669b0203d5ab2970a208a62;
        proofs[0][7]  = 0x392f18d43a9761257375b964f5f465f4b11c64ddf73a08595923ab694ced1b1c;
        proofs[0][8]  = 0x789f00aa0544137155f546aae94ba0a8bdd68b9f146dba77d34fb77375078942;
        proofs[0][9]  = 0x514888cba6fdfa2382ec68dd0bb14218f402eb6c498819219c41196d4a63813d;
        proofs[0][10] = 0x94235122141bf10ac5a683c3afbb59e002b4e8842cced32e2ec3fd995ce4a24c;
        proofs[0][11] = 0x7c076303cc6652440ea15580773801b16f697ce3fb74d6bf1613d51dcda912af;
        proofs[0][12] = 0x0717f1dc7f680aa3490f70f6102ce8b19db2d4628272cfb41af13606fd96cd22;
        proofs[0][13] = 0x0ee593141420d3c57b23a75393203945673843c373b8ef32fbc26c5282944180;
        proofs[0][14] = 0x1d84732e1ef602b3cd3d8da6ea46e8b666574630e57a04f77e18cb3436d9ab3c;
        proofs[0][15] = 0xdbd6229c29daeaef44d28f98f17f1db8a29bc6c09def6683ffcd5a2c8f8a64c2;

        targetData[0] = abi.encodeWithSignature(
            "claim(address[],address[],uint256[],bytes32[][])",
            users,
            tokens,
            amounts,
            proofs
        );

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiMerklDecoderAndSanitizerName);

        uint256[] memory values = new uint256[](opsAmt);

        // extra
        string memory filePath = "./leafs/MerklKatanaLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs(filePath, leafs, merkleRoot, manageTree);

        // try to less the var number to prevent "Stack too deep" error
        manager.setManageRoot(vm.addr(vm.envUint("KATANA_STRATEGIST")), merkleRoot);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("KATANA_STRATEGIST"));

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
