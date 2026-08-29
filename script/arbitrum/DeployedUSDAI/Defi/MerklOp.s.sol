// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;
import "forge-std/Script.sol";
import {ArbitrumAddresses} from "test/resources/ArbitrumAddresses.sol";
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

contract MerklOp is Script, ArbitrumAddresses, MerkleTreeHelper, ContractNames {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using Address for address;

    Deployer public deployer;
    BoringVault vault;
    ManagerWithMerkleVerification manager;

    function setUp() external {
        vm.createSelectFork("arbitrum");
        setSourceChainName("arbitrum");
        
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        vault = BoringVault(payable(previoussuperUSD));
        manager = ManagerWithMerkleVerification(deployer.getAddress(UsdaiVaultManagerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // address auth = vm.addr(privateKey);
        
        vm.startBroadcast(privateKey);
        
        setAddress(true, arbitrum, "boringVault", previoussuperUSD);
        setAddress(true, arbitrum, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, arbitrum, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMerklDecoderAndSanitizerName));

        /*
        claim params:
        https://api.merkl.xyz/v4/users/0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB/rewards?chainId=42161
        amount and proofs should be exactly same, otherwise it will revert
        */
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1154145691507787167518;
        amounts[1] = 7105708913849695604091;

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        address[] memory tokens = new address[](2);
        tokens[0] = MORPHO;
        tokens[1] = ARB;

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

        address[] memory users = new address[](2);
        users[0] = address(vault);
        users[1] = address(vault);

        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](19);
        proofs[0][0] = 0x751b7dd2863f733ad231456dd666f15982226cf039974b2253944a6132cf7944;
        proofs[0][1] = 0xee71acea51875c23ce072dc47839171633bc9217bb7fb6fc730e5cf7f879c973;
        proofs[0][2] = 0x21c34dcb5028893848d539d700c66308e3fc1114a6d9c93bc99c165237eb5f85;
        proofs[0][3] = 0xad32799e63476fc462be4b03168247efc282208ee67b08c27ee642d0641c6b1c;
        proofs[0][4] = 0x0118af8469390ee88bdb38ad0a09a5ab98c50797733fabf86aa029c2bbf49606;
        proofs[0][5] = 0x92315e36f465b203423671fb1317a56e98a45d26e1681d32b14654deb622d246;
        proofs[0][6] = 0x9462d468665f4c9764e0286062f58fea373c03889bd5be1ace288e1dea37d631;
        proofs[0][7] = 0xecd75ce09f0d1ba4819f09124c69377bc6a0db40cac8c3900cc5528d38650df5;
        proofs[0][8] = 0x33d0fca218a29109d154db98cb233500541643744561e84f7b25ae04a6cddbda;
        proofs[0][9] = 0xa0ac0116922dde474aa29664a71a12e4f9c1adfd187f383ed526a5a8c8376805;
        proofs[0][10] = 0xe42782c212eaf240f23cbd5c41ec229e9d3d9c9c1d9d2c65220b7643ebb6e151;
        proofs[0][11] = 0x94a73bc7d6b9846d90573a732ad06261c774aceba281e2ea3fb4614357f93f8f;
        proofs[0][12] = 0x9fae9b372f716b7bad075de042d82c1df072ac7b7de986d3aea494e289e41082;
        proofs[0][13] = 0xdc4e3a8ed901f4f95b93db17b1a4f303540e978174216e478c87f1ebdaa983e2;
        proofs[0][14] = 0x249cd1367dbd9417555d4f2371dd4c38aa583fe542344373b918abde5f15a4ce;
        proofs[0][15] = 0xd27a5da6a866c68be6341ce89f798be8a1c5cbff4b940eecbec9a076b73f3c3b;
        proofs[0][16] = 0x422d99752b801fe8eddaed07f34d3cf9cb999d507d170e04bc25266554122632;
        proofs[0][17] = 0x1c5ac85bfedee668449018b394a49321d29f6a9f610a3a2c12d692c959b2a3e5;
        proofs[0][18] = 0x71907809e8e742a9e93b9520d4a842a5be7b49c5dbcd125e1cb07044a28d67ee;

        proofs[1] = new bytes32[](19);
        proofs[1][0] = 0xbb34d614c5d03e16c154d6a23ce3e07418f6177e3d2acbaab5095546e7cc07a7;
        proofs[1][1] = 0x34d5abd8bb1d692ffa3b7aabd6e306f9b8cc04f92b489e3427e95c5bfe40d197;
        proofs[1][2] = 0xfc843f4c814f03e9b1b4d9d9ce07f11ff32303851389d364998d0ec62ab7287e;
        proofs[1][3] = 0xf59cc758716907938200d8998fc713eec206469c34bd2618373704a9fa061368;
        proofs[1][4] = 0xdcb8b8070598b79ad5416247fce84f617fdf9151fe000e9a68c0dd0c1502106c;
        proofs[1][5] = 0xa1d9faae041d4eeb48160218ed2721ddb11032c9db89e80a44c396c6791d8a8b;
        proofs[1][6] = 0x1447d66e069b3ace5124cb0935f03ac7d0d23fba073a0d168c98f19bcb8cf6d3;
        proofs[1][7] = 0x3479889913e98296d990aec41abbcce647515817a343fa536c4a66aa1a26885f;
        proofs[1][8] = 0x81dfb9303ebf6df3f68ad16d349df0ee3e391c30cc32bf38235e64294acb6b1d;
        proofs[1][9] = 0xfccbc8a19aeabd10d013251120ed94ca4c6964c18c530a40546a341e12c277c0;
        proofs[1][10] = 0x7ec33aa466f564d3664a9ee4cd6b8eceb8155e1270a6fdf1acf85a251cf03696;
        proofs[1][11] = 0x5266e93c1849fb1c7f569c025f42c26923e75d0891496bda88bc679f70abb013;
        proofs[1][12] = 0x4e002929b6e07661c42e9a27d69cf19bc340aa3c20f67074bceba968669cb55d;
        proofs[1][13] = 0x28ad61d4b24fad7366fae8f9720c0a82dc901bb42c282224944946b0dfecffe7;
        proofs[1][14] = 0xb72b89bffe53fc853586532469ab03ff10476e1d756e40255e00f26c496d2c5f;
        proofs[1][15] = 0x996b5a06ab60e9ff31e0594011ceec20e6c8783662790a7c3e2a5d220618a119;
        proofs[1][16] = 0x5490f46f1b454e0842c9a81b772d3b8e5d2e362533712e6bd9d1e809f080bcfd;
        proofs[1][17] = 0xb9d17ad0441b6b5b2b075a2ad83819cfb62bd5831dd2387455c942e3019f0d76;
        proofs[1][18] = 0x1793dcae0c1b73dfa6209d07c85da2bc6daa8fe921a63705b6744372467caa99;

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
        string memory filePath = "./leafs/MerklArbitrumLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs(filePath, leafs, merkleRoot, manageTree);

        // try to less the var number to prevent "Stack too deep" error
        manager.setManageRoot(vm.addr(vm.envUint("ARBITRUM_STRATEGIST")), merkleRoot);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("ARBITRUM_STRATEGIST"));

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
