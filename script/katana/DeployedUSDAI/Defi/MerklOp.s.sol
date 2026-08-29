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
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 163470273191730351118;
        amounts[1] = 285391386286908839;
        amounts[2] = 2848733;

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        address[] memory tokens = new address[](3);
        tokens[0] = address(KAT);
        tokens[1] = address(0x1e5eFCA3D0dB2c6d5C67a4491845c43253eB9e4e); // MORPHO
        tokens[2] = address(0x203A662b0BD271A6ed5a60EdFbd04bFce608FD36); // vbUSDC

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

        address[] memory users = new address[](3);
        users[0] = address(vault);
        users[1] = address(vault);
        users[2] = address(vault);

        bytes32[][] memory proofs = new bytes32[][](3);
        proofs[0] = new bytes32[](17);
        proofs[0][0]  = 0x36667a3ff2010fa79e4bffed596b77cdd1f3c6a5a467f9a0c91d54939c5461e0;
        proofs[0][1]  = 0x9b5d278cd8265c7385b8bf6bff8f6014922705ec5ec3554be6c2785f7ea6c6c5;
        proofs[0][2]  = 0xfa067a7bf622f4b04d0c77323f3ab9ee5537b94268f548b5ba6cf4698f34d7fb;
        proofs[0][3]  = 0x1b74d96010d4f97f893004cd74b5284a2534479b003c2db7375936aa12ff0b2a;
        proofs[0][4]  = 0x57d08bf7def28e2f25721e5657cffc7bc3333c043a3ff0c7f2b466266609fcf6;
        proofs[0][5]  = 0x5aa0e6122966c6174d575938c58dc92f0d669489b513dd1b1ee698ed460efeee;
        proofs[0][6]  = 0xda9d47a8dea1161bdb86bb911bda0e7b6b5b53335ff243be5ecff5d37be815fe;
        proofs[0][7]  = 0x33afd40d824f43fc3eda40d5f427da8665f5c8da6e980394d94ed9e99d22c140;
        proofs[0][8]  = 0x6e6cbf3c4f39adcc8c8c785bb4df19034a9f68299bd97f1b3b1cbdbbeeb83485;
        proofs[0][9]  = 0xfc2f70a8d9b7b29b906942893ac09cc21c517ad64f9ae5f553a38d4163e9761c;
        proofs[0][10] = 0x642675c9543937c5a22be64645f17ac20b652df47e4a6e1e723141aa4c1fff14;
        proofs[0][11] = 0xe8a84b42018e963bbd1ea1401891ccbd500c09b0416e53cd83ed801e450763eb;
        proofs[0][12] = 0x7362803fa0f78e9a6194e0ab0f06759750c737893a84557b481a1b3752d3856b;
        proofs[0][13] = 0x10bcd04ee1d8ad562dad37b28231abaa567b30dcd3c1f38fb608ccb991339f7c;
        proofs[0][14] = 0x8d519090fee313f160a9fe349b8f4a16be5e960b1eaf645b518edbe2ea8dcec4;
        proofs[0][15] = 0xed17994b6ac24de72bfe5fd50e5f2edc18bd2e5aa6dbae5c27b3420bfecd615f;
        proofs[0][16] = 0x6c19b274b3ce16eaaf5292d6779f93b7f81ed48018d86057b4199d3570b73f2f;

        proofs[1] = new bytes32[](17);
        proofs[1][0]  = 0x9597cd68ac38ce6812b926fb9072407f01aed6ebd3a5b696a055118118781937;
        proofs[1][1]  = 0x433a0b22ae391fafc7d09ef9728e08ccb0d57e32eea5a75a0881538d711a4be0;
        proofs[1][2]  = 0xa9b17279a1cfdefdbfc8f915a0d0a95f43fc63adbe3660324d45c1d6a83bd29f;
        proofs[1][3]  = 0xffe49c27f3894e0c82bc0b5a2a533d3e50b70485cb7e93626ba0d3dde2daaab0;
        proofs[1][4]  = 0x82d36a2116935415aeaa8b732a80438350fdd2316a589c01ce7084380827494c;
        proofs[1][5]  = 0x0f8559cf183905ce84726672b7ae72d53dc148ded14bbb136bf36d2256121dc9;
        proofs[1][6]  = 0xd0bf72863f7a76b62f2f982598ee7fe6680ba9395e6e5da3258d14f10531095b;
        proofs[1][7]  = 0x620f202d40bb6060e02bfc524e5120f6faca3874b59b57489ff00255e50541cc;
        proofs[1][8]  = 0xe1573ca15383acde6c413294de22ba383781b789c22d2e010f9135a51c22e312;
        proofs[1][9]  = 0xddb3f33263c97e2bbc4ae8d0b8de26707fe1bd2f632816b310381bea5c0e87f4;
        proofs[1][10] = 0xe784321b7c804e27a4bc5dd0474a7846a599f2d53875a4415ae42d2667a49515;
        proofs[1][11] = 0x5893267de6e3db43d339c37432f78c49706ba709936c3271877e9c27735f56c6;
        proofs[1][12] = 0xde802e41811ef91c022225a088dad6e33fad17e48753bbe54b5a3e9821c47680;
        proofs[1][13] = 0xb87ccaab5554fff29001ce6799d29916e0dfb6938157ca6a9fa5fc72940ad952;
        proofs[1][14] = 0xe61dbbdd91128ed5a88d796d6744120d0583458248195b99383c2c50421cd82d;
        proofs[1][15] = 0x9ac3d6070a6825550ad1bf7e0f6bdf4dfcb78d8d014d6ac6612e52bee1fe2f43;
        proofs[1][16] = 0x6c19b274b3ce16eaaf5292d6779f93b7f81ed48018d86057b4199d3570b73f2f;

        proofs[2] = new bytes32[](17);
        proofs[2][0]  = 0x6e1602b6e57f1452eb988e2d308ba23135fc2aae8738b6e07297b90703bc9bc5;
        proofs[2][1]  = 0x73289be6eb9c3c3d4f076b6784a7cd8045ddd231c082ef80f90e13b905d1d2eb;
        proofs[2][2]  = 0x5aad32d7f3b1e5268837e7e87ea1913c53a2cc8bfcd4b579f38095b070f5d9bd;
        proofs[2][3]  = 0xc58e3c6feba0763c2b25da01ee508198ea89faaa01dd783dd51355ef350846e3;
        proofs[2][4]  = 0x416ea374090cf1541c4ebc37560ff572f33c801221af6e47700b5d6e9dfd4818;
        proofs[2][5]  = 0xb6d9ce106d06c25f01d179c1d1574e00f009ce5439ad7753ea8cd73a5489aa57;
        proofs[2][6]  = 0x9fa74901502591549dabf3d738f936c15ec333c76040c79f847a8d486acf2ccf;
        proofs[2][7]  = 0xc2cec3ff7d27c6a1cc348f44c1aa55baa64532aa3e693a5787c5c2c6f4516540;
        proofs[2][8]  = 0x2295c0819ea0e199179e51937d2896029c06552664c80bf11dae106b841116d3;
        proofs[2][9]  = 0xd16292d9a4d3692452ca204435b045cac84ec13a440c9002ff551a1cf7b5f4cb;
        proofs[2][10] = 0xab2f8b93de47d75fd0704265825e2addd397e81ae5e51cab6d890bde2a4bb225;
        proofs[2][11] = 0xec80c0e1dbdc04c166125ec3a9eb94381061eb93f84e53542012eb013073b99c;
        proofs[2][12] = 0xe40f5b7ceb7176f5ad3cd88243e0611483d46aaf48c36958975933b710a69043;
        proofs[2][13] = 0x00273c5a93a02084aaf73686413d92946a7998c334d123b181dcd66a7f725b58;
        proofs[2][14] = 0xe61dbbdd91128ed5a88d796d6744120d0583458248195b99383c2c50421cd82d;
        proofs[2][15] = 0x9ac3d6070a6825550ad1bf7e0f6bdf4dfcb78d8d014d6ac6612e52bee1fe2f43;
        proofs[2][16] = 0x6c19b274b3ce16eaaf5292d6779f93b7f81ed48018d86057b4199d3570b73f2f;

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
        // string memory filePath = "./leafs/MerklKatanaLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs("./leafs/MerklKatanaLeafs.json", leafs, merkleRoot, manageTree);

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
