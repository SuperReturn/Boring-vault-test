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
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";

contract Strategist1 is Script, ArbitrumAddresses, MerkleTreeHelper, ContractNames {
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
        vault = BoringVault(payable(deployer.getAddress(UsdaiVaultName)));
        manager = ManagerWithMerkleVerification(deployer.getAddress(UsdaiVaultManagerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // address auth = vm.addr(privateKey);
        
        vm.startBroadcast(privateKey);
        
        setAddress(true, arbitrum, "boringVault", deployer.getAddress(UsdaiVaultName));
        setAddress(true, arbitrum, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, arbitrum, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName));

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        _addArbitrumMorphoLeafs(leafs, address(vault), morphoVaults);

        address[] memory tokens = new address[](2);
        tokens[0] = ARB;
        tokens[1] = MORPHO;

        setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMerklDecoderAndSanitizerName));
        _addMerklLeafs(leafs, merklDistributor, tokens);
        
        setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiOneInchDecoderAndSanitizerName));
        // only support instant mint with USDC for now
        _addLeafsFor1InchArbitrum(leafs, getAddress(sourceChain, "ARB"), getAddress(sourceChain, "USDC"));

        setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiBaseDecoderAndSanitizerName));
        _addApprovalLeafs(leafs, ERC20(MORPHO), vm.addr(vm.envUint("ARBITRUM_STRATEGIST")));
        _addTransferLeafs(leafs, ERC20(MORPHO), 0x62d9113BFf4414e7D3600FfB4d6255D29e5CFc42);

        setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiBaseDecoderAndSanitizerName));
        _addApprovalLeafs(leafs, ERC20(getAddress(sourceChain, "USDC")), 0x789AE139dBC4A1fd79981F8A9734DD448CFD3b2c);
        _addTransferLeafs(leafs, ERC20(getAddress(sourceChain, "USDC")), 0x62d9113BFf4414e7D3600FfB4d6255D29e5CFc42);


// Morpho operation
        // setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName));
        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        // uint256 opsAmt = 2;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[30];
        // manageLeafs[1] = leafs[31];

        // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data
        // address[] memory targets = new address[](opsAmt);
        // targets[0] = getAddress(sourceChain, "USDC");
        // targets[1] = morphoVaults[10];

        // bytes[] memory targetData = new bytes[](opsAmt);

        // targetData[0] = abi.encodeWithSignature(
        //     "approve(address,uint256)",
        //     morphoVaults[10],
        //     type(uint256).max
        // );

        // targetData[1] = abi.encodeWithSignature(
        //     "deposit(uint256,address)",
        //     1 * 1e3,
        //     address(vault)
        // );

        // address[] memory decodersAndSanitizers = new address[](opsAmt);  
        // decodersAndSanitizers[0] = deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName);
        // decodersAndSanitizers[1] = deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName);


// Merkl operation
        // setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMerklDecoderAndSanitizerName));
        // /*
        // claim params:
        // https://api.merkl.xyz/v4/users/0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB/rewards?chainId=42161
        // amount and proofs should be exactly same, otherwise it will revert
        // */
        // uint256[] memory amounts = new uint256[](2);
        // amounts[0] = 22454639252841364;
        // amounts[1] = 9502479009029716;

        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        // uint256 opsAmt = 1;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[3 * 12]; // morpho leafs number

        // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data
        // address[] memory targets = new address[](opsAmt);
        // targets[0] = merklDistributor;

        // bytes[] memory targetData = new bytes[](opsAmt);

        // address[] memory users = new address[](2);
        // users[0] = address(vault);
        // users[1] = address(vault);

        // bytes32[][] memory proofs = new bytes32[][](2);

        // proofs[0] = new bytes32[](19);
        // proofs[0][0] = 0xbc6d8e10a9352366ddd02aa2f1c8a4a0edc6152be29d5640edce7e0089b735cb;
        // proofs[0][1] = 0x83ebac81d4eb71e83fae2b1e77b3788a445cb11793fa30a224d70f9d7eef68a4;
        // proofs[0][2] = 0x15afff639982941b67dfe259d05a674a945977a468e76e5cd376db246d0d53fd;
        // proofs[0][3] = 0x6499b8245e0f9443295240c24fd5712d04e76b82aa0ed0c84d6523ed6a5445c6;
        // proofs[0][4] = 0x6631cef8a810bfad97df3a19888cfd660533d5f2303879ca0350ff864008142c;
        // proofs[0][5] = 0xc156d76f3f9920f50c4ce4a2f4af694e660fb77c496b0f3317392ea2ba560118;
        // proofs[0][6] = 0x43edcf0c571fb726fb2029ddf7f37902e25e6a6ef6e909a60802cb4a9103c315;
        // proofs[0][7] = 0xbc2cfebc68cd7751f62894a553b07ca248a74ba0cc184fe1710ce16c2b27b5c3;
        // proofs[0][8] = 0x3e671f42b939287c70fcca35bf3f33c9376472b3e35cb52a086ee9d4188825c8;
        // proofs[0][9] = 0xf3bc4a9b78cd4de909101159c7cd47147ea8e59aecf49bca6a8016d32723b149;
        // proofs[0][10] = 0x3a40593e5b7e514b8b27fd8aafe3eaf4f54f0734aecfb2fe4d15305d1305c48d;
        // proofs[0][11] = 0xa44b4dc24ea15208d69cce8b4ddc8c37d6e7f7b07393f9fa02620d942e44eb78;
        // proofs[0][12] = 0x8f5fe885ef38f88d33431cd95daf8dffb281807c9afc85055491035dddd5133b;
        // proofs[0][13] = 0x91f5d14a36ac00e15615c57d49cbc63aa024a02304d026595f7dbc9f13f1db63;
        // proofs[0][14] = 0xc6d9252a5807d8d0ee7678e44d8db4cbf0ba8a2376488be8fb7e8768fc56197a;
        // proofs[0][15] = 0xa050de81c1cf484b1c72479420592c2d3935e83e9f42356c28689d02cc87e812;
        // proofs[0][16] = 0x6c5efb53f20502a04ab86b92970957c866d5e9216ca7f624f92d71ff9b8b19a4;
        // proofs[0][17] = 0xcee778cdb50ed8c13b5aab37526f95e70f92233e7ead677915f823c28d8bd373;
        // proofs[0][18] = 0x78f2743dea6e19659bb024d686c383f15c3727d1c51658e92130dd0cf671a7af;

        // proofs[1] = new bytes32[](19);
        // proofs[1][0] = 0xcfa4e590f8b41e94148a3ea213797cc00859f138fc4d93671e8d7c7cef111114;
        // proofs[1][1] = 0xd2e32a415f3ac117bc8e9ddb6395ad2ad16af58b07b7f2203d8096f7c1b8691c;
        // proofs[1][2] = 0x9fc13704e08335f17cfc33a47175be82313c0448cba1a54be4bdf5cd6b503af5;
        // proofs[1][3] = 0x9ad49ab84e41c04b4ea63ac3683d8a6f13397f82824dc9931fe27e08e653988c;
        // proofs[1][4] = 0xcdc3dbd4ea96fd90976b4c450c53e173425b7167787050a1e589a3ebb1678678;
        // proofs[1][5] = 0x7144d02af1710ffa3d4da6d8f23663acf8ecdcd95e6eb38fe7bbaffe8600ca0a;
        // proofs[1][6] = 0x0b24ca6026e0d1405d0aeff104f4975c6f11b3813fdb2cce2287d14b6d77053a;
        // proofs[1][7] = 0x01bd77ecce793dcd2ce6bb117365bb7c55172e2d67091a64179252fc581b1a77;
        // proofs[1][8] = 0xe23f90ef3143a5cd9aa3c50761bc16505c6e08ba4b59960c9e6e3213e83c1068;
        // proofs[1][9] = 0xaf22f6ffe79689942f5644c6784b3918e680f822057c07c6191c5c1415e0f48f;
        // proofs[1][10] = 0x78347828389280ea35a855d409ed36196e4fc5450bba921803aa31ace182595f;
        // proofs[1][11] = 0x6371a2d1d9a04092b761c137e2caca24d4cae14f6f5372165013294463bbdf3f;
        // proofs[1][12] = 0x511b0edca94be8a716213f6a2d2321999c92f306b4679d68996e7343cdd49ba1;
        // proofs[1][13] = 0xff33935edf5cc062f010828d5994aeb15b4079928945ba517acd40e0016d5b99;
        // proofs[1][14] = 0x97eedd4b6586fce3f902918b1e11f5f26c2cd14c47f78375f08cc012d07db6c5;
        // proofs[1][15] = 0x2940e3f48624d40809bd24565d50980ddfe78de5f14e9bd17905c562339f8099;
        // proofs[1][16] = 0x0fc01a2673a70916ad5efb78c800b6f371f1f7f91fabad479f67290ae6f143a1;
        // proofs[1][17] = 0xcee778cdb50ed8c13b5aab37526f95e70f92233e7ead677915f823c28d8bd373;
        // proofs[1][18] = 0x78f2743dea6e19659bb024d686c383f15c3727d1c51658e92130dd0cf671a7af;

        // targetData[0] = abi.encodeWithSignature(
        //     "claim(address[],address[],uint256[],bytes32[][])",
        //     users,
        //     tokens,
        //     amounts,
        //     proofs
        // );

        // address[] memory decodersAndSanitizers = new address[](opsAmt);  
        // decodersAndSanitizers[0] = deployer.getAddress(UsdaiMerklDecoderAndSanitizerName);



// 1inch operation
        // setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiOneInchDecoderAndSanitizerName));
        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        // uint256 opsAmt = 2;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[3 * 12 + 1];
        // manageLeafs[1] = leafs[3 * 12 + 2];

        // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data
        // address[] memory targets = new address[](opsAmt);
        // targets[0] = getAddress(sourceChain, "ARB");
        // targets[1] = getAddress(sourceChain, "AggregationRouterV6");

        // bytes[] memory targetData = new bytes[](opsAmt);

        // targetData[0] = abi.encodeWithSignature(
        //     "approve(address,uint256)",
        //     getAddress(sourceChain, "AggregationRouterV6"),
        //     type(uint256).max
        // );

        // DecoderCustomTypes.SwapDescription memory swapDescription = DecoderCustomTypes.SwapDescription(
        //     getAddress(sourceChain, "ARB"),
        //     getAddress(sourceChain, "USDC"),
        //     payable(getAddress(sourceChain, "oneInchExecutor")),
        //     payable(address(vault)),
        //     1e15,
        //     300,
        //     0
        // );
        // targetData[1] = abi.encodeWithSignature(
        //     "swap(address,(address,address,address,address,uint256,uint256,uint256),bytes)",
        //     getAddress(sourceChain, "oneInchExecutor"),
        //     swapDescription,
        //     // remove 0x
        //     // get data from https://portal.1inch.dev/documentation/apis/swap/classic-swap/swagger?method=get&path=%2Fv6.1%2F42161%2Fswap
        //     // and use the decoder in explorer: https://arbiscan.io/inputdatadecoder
        //     hex"0000000000000000000000000000000000000000000000000000dd00004e00a0744c8c09912ce59144191c1204e64559fe8253a0e49e654890cbe4bdd538d6e9b379bff5fe72c3d67a521de5000000000000000000000000000000000000000000000000000002ba7def30000c20912ce59144191c1204e64559fe8253a0e49e6548ab4fb502ba6efc777723fe8e1ed0addc45a0b24a6ae40711b8002dc6c0ab4fb502ba6efc777723fe8e1ed0addc45a0b24a111111125421ca6dc452d289314280a0f8842a650000000000000000000000000000000000000000000000000000000000000134912ce59144191c1204e64559fe8253a0e49e6548"
        // );

        // address[] memory decodersAndSanitizers = new address[](opsAmt);  
        // decodersAndSanitizers[0] = deployer.getAddress(UsdaiOneInchDecoderAndSanitizerName);
        // decodersAndSanitizers[1] = deployer.getAddress(UsdaiOneInchDecoderAndSanitizerName);

// transfer MORPHO
        // setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiBaseDecoderAndSanitizerName));

        // // 2. Generate the merkle tree and get the root
        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // // 3. Generate proofs for the actions you want to execute
        // uint256 opsAmt = 2;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[3 * 12 + 2 + 1];
        // manageLeafs[1] = leafs[3 * 12 + 2 + 2];

        // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data - both operations target USDC token
        // address[] memory targets = new address[](opsAmt);
        // targets[0] = MORPHO; // approve
        // targets[1] = MORPHO; // transfer

        // bytes[] memory targetData = new bytes[](opsAmt);
        // targetData[0] = abi.encodeWithSignature("approve(address,uint256)", vm.addr(vm.envUint("ARBITRUM_STRATEGIST")), type(uint256).max);
        // targetData[1] = abi.encodeWithSignature("transfer(address,uint256)", 0x62d9113BFf4414e7D3600FfB4d6255D29e5CFc42, 145e18);

        // address[] memory decodersAndSanitizers = new address[](opsAmt);  
        // decodersAndSanitizers[0] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);
        // decodersAndSanitizers[1] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);

// transfer USDC
        setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiBaseDecoderAndSanitizerName));

        // 2. Generate the merkle tree and get the root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute
        uint256 opsAmt = 2;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[3 * 12 + 2 + 2 + 1];
        manageLeafs[1] = leafs[3 * 12 + 2 + 2 + 2];
        // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // 4. Prepare the action data - both operations target USDC token
        address[] memory targets = new address[](opsAmt);
        targets[0] = getAddress(sourceChain, "USDC"); // approve
        targets[1] = getAddress(sourceChain, "USDC"); // transfer

        bytes[] memory targetData = new bytes[](opsAmt);
        targetData[0] = abi.encodeWithSignature("approve(address,uint256)", 0x789AE139dBC4A1fd79981F8A9734DD448CFD3b2c, type(uint256).max);
        targetData[1] = abi.encodeWithSignature("transfer(address,uint256)", 0x62d9113BFf4414e7D3600FfB4d6255D29e5CFc42, 1e6);

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);
        decodersAndSanitizers[1] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);



        // uint256[] memory values = new uint256[](opsAmt);

        // extra
        string memory filePath = "./leafs/Strategist1ArbitrumLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs(filePath, leafs, merkleRoot, manageTree);

        manager.setManageRoot(0x789AE139dBC4A1fd79981F8A9734DD448CFD3b2c, merkleRoot);

        vm.stopBroadcast();
        // vm.startBroadcast(vm.envUint("ARBITRUM_STRATEGIST"));

        // // 5. Execute the actions through the manager
        // manager.manageVaultWithMerkleVerification(
        //     manageProofs,
        //     decodersAndSanitizers,
        //     targets,
        //     targetData,
        //     values
        // );

        // vm.stopBroadcast();
    }
}
