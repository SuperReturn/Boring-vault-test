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

/*
notice possible issues:
1. sepolia operation is totally diff from mainnet, need to rewrite all logic for mainnet
example tx: https://sepolia.etherscan.io/tx/0x563c1e3daaeb60ac16d203040f2aeb9c15b25dc96f8c2be071b36af9625e6a87
*/

contract MerklOp is Script, EthereumAddresses, MerkleTreeHelper, ContractNames {
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
        vault = BoringVault(payable(deployer.getAddress(UsdaiVaultName)));
        manager = ManagerWithMerkleVerification(deployer.getAddress(UsdaiVaultManagerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // address auth = vm.addr(privateKey);

        // uint256 strategist = vm.envUint("MAINNET_STRATEGIST_EULER");
        
        vm.startBroadcast(privateKey);
        
        setAddress(true, mainnet, "boringVault", deployer.getAddress(UsdaiVaultName));
        setAddress(true, mainnet, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, mainnet, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMerklDecoderAndSanitizerName));

        /*
        claim params:
        https://api.merkl.xyz/v4/users/0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB/rewards?chainId=1
        amount and proofs should be exactly same, otherwise it will revert
        */
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1405721645663333097;

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        address[] memory tokens = new address[](1);
        tokens[0] = 0xf3e621395fc714B90dA337AA9108771597b4E696; // rEUL

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
        proofs[0] = new bytes32[](18);
        proofs[0][0] = 0x4ac39a29efcc198bcf0c25d344edb776a526fcf1cb17fdfab88c2f8a6620ac02;
        proofs[0][1] = 0xa853f56c80c6edce2ab636a77eaee9fa989dfa0ab147d068c6c4fe0ef89be39b;
        proofs[0][2] = 0xd98bbdc070b84e96b938f988d28a752008cdff648a1b7b327781803b6c4448ab;
        proofs[0][3] = 0x63206af473e7a241e07d607fd22166e77dac0a194b17b192e03fe55f3fe50b6c;
        proofs[0][4] = 0xeb0d3a7e631e9f7e821de7a91114a63321995a97d08388b644430c3fecee6b57;
        proofs[0][5] = 0x4da333d3b01f1841593d9e08ea3eadb7e9c1d6174b91e3608ec8f7eeaeb63371;
        proofs[0][6] = 0x6306f6d16a86c1622030c27e8d05b891e0957aefdd39b5749e6ad289d72afb94;
        proofs[0][7] = 0x207bdf1230eef75c07aa48dcbca7effb1145ceee024fe4706fd48a529c78cd23;
        proofs[0][8] = 0x48c551a3953feceab82d0126df72ce8a042d81c60d1ea0b45ff8188fd146df7e;
        proofs[0][9] = 0x6c21722a945cae2fd66797d974a1d7273100a23a731432bffe36a9f138ed23c1;
        proofs[0][10] = 0x640025c544f2850cb41bd89de72c17f25eb0a8f7151e482eac89bf11857c6c93;
        proofs[0][11] = 0xca104200052a94f049d8c1277cd8c8661959315d34d0dae775f1ec72ee797fcb;
        proofs[0][12] = 0x9e1fc1da1c0fece11c3a075fa61e8857cd71d104edfdcd328b8c2e89bc6230af;
        proofs[0][13] = 0x82d8aceba40861087e7f62601a6f75949cab696ad9a5c87a06882c8fa6c624e6;
        proofs[0][14] = 0x5dde9a88407fedfe53884c895f2119902143bce0e950502392905ff064e894a3;
        proofs[0][15] = 0xa5607241f37a753f8166dd58d0303d349bc561a15fc49b8724b9387571f29125;
        proofs[0][16] = 0xe36c38c7ac3d39e7176f600afc0d29365165992f252b70c0510b35f7f1b37d16;
        proofs[0][17] = 0xd1c1a14f14f053c6fe76616a76a578d41f14a58d182ed1753257bfbd4aefe85e;

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
        string memory filePath = "./leafs/EthereumMerklLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs(filePath, leafs, merkleRoot, manageTree);

        // try to less the var number to prevent "Stack too deep" error
        manager.setManageRoot(vm.addr(vm.envUint("MAINNET_STRATEGIST_EULER")), merkleRoot);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("MAINNET_STRATEGIST_EULER"));

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
