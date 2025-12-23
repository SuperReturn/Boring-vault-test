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
        _addApprovalLeafs(leafs, ERC20(getAddress(sourceChain, "USDC")), 0x28d2e2759dCB5CFda1c868Fee714B194c25a8dCB);
        _addTransferLeafs(leafs, ERC20(getAddress(sourceChain, "USDC")), 0x62d9113BFf4414e7D3600FfB4d6255D29e5CFc42);


// Morpho operation
        // setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName));
        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        // uint256 opsAmt = 2;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[36];
        // manageLeafs[1] = leafs[37];

        // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data
        // address[] memory targets = new address[](opsAmt);
        // targets[0] = getAddress(sourceChain, "USDC");
        // targets[1] = morphoVaults[12];

        // bytes[] memory targetData = new bytes[](opsAmt);

        // targetData[0] = abi.encodeWithSignature(
        //     "approve(address,uint256)",
        //     morphoVaults[12],
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
        setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMerklDecoderAndSanitizerName));
        /*
        claim params:
        https://api.merkl.xyz/v4/users/0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB/rewards?chainId=42161
        amount and proofs should be exactly same, otherwise it will revert
        */
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10959490022562288368560;
        amounts[1] = 1362570265618372135400;

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        uint256 opsAmt = 1;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[3 * 13]; // morpho leafs number

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // 4. Prepare the action data
        address[] memory targets = new address[](opsAmt);
        targets[0] = merklDistributor;

        bytes[] memory targetData = new bytes[](opsAmt);

        address[] memory users = new address[](2);
        users[0] = address(vault);
        users[1] = address(vault);

        bytes32[][] memory proofs = new bytes32[][](2);

        proofs[0] = new bytes32[](20);
        proofs[0][0] = 0x05f7cfd47755d996612cb9078a7896237237d3e3c60b0756112a533d6fc8ea2a;
        proofs[0][1] = 0x78f92f90e05d6e367eec342ab274e7974485ca953334e00d1d8822d335939b97;
        proofs[0][2] = 0xda373c52e4792b426104b67e41d344352c1cb6f2a61d169ffc05184ee58b4481;
        proofs[0][3] = 0xb440fdfa8d3bc5eb860b459868f903a8a3e687684bb0423d812a8d7a4b57418c;
        proofs[0][4] = 0xfecd055f13b08942641f0857fce321028eab0aa1ca105ec8a27b49ef0398ac04;
        proofs[0][5] = 0xf23c01e93aa430a3ea3fd019118bd62bfa7cdd9004333f7ecfdab54502348b6a;
        proofs[0][6] = 0xa5d7b963f4dc12ef96b08ef3eba6ee58856ff00a7f099fd3071bdd1ceedaebe8;
        proofs[0][7] = 0x4a8d9593b237ef45f8a7e5d6059043a7be401a99c97dfb49b5213a03a124466a;
        proofs[0][8] = 0xb7b06a01cba010d26238150e4bb5e976448f5ae2aacfe4098c9fae8092fbc1ef;
        proofs[0][9] = 0x7cc4b86043bbb41200019c3b1d82dd2f6d63f51b3ce164daef99544cd2173727;
        proofs[0][10] = 0x1d3c2da5e28934560fd698f081fcf792a5af8b6643283a6ee24633b294fbfc64;
        proofs[0][11] = 0x5b5e6f24b180e15545d6269aa9cfd078cd5c5cb41d00f1f2ba01e273396eba7b;
        proofs[0][12] = 0x5b585a9ab5afde4854b9d75c8bd9197f926b43d758b652eddda97d295a2dcb5d;
        proofs[0][13] = 0x04aea4353e2ee9378d9e13d76548fa4388551774ab30830de2ee920692137eac;
        proofs[0][14] = 0xfb84c651d62539af15825b7d4cdbe9c03259cab401d7cdaa00ddfbd0312b58bc;
        proofs[0][15] = 0x3d22b67ed6afa91e31f72a752e710a9232504a5c681e04f23861e0be1f64876f;
        proofs[0][16] = 0xecf08862977dcbaea8675b23758a42004c5577197b1408ec539f5f78cdd55d23;
        proofs[0][17] = 0xc4c14b90d71b641a856a675d7676cc04f11eb41c7bf82d9cee5e6e99b7e72e88;
        proofs[0][18] = 0xd95bd460add9bda946da0fe9b7bc01ab2fde06c375d2c8086b52c1b7f17f9d1e;
        proofs[0][19] = 0xfa03c3f66ee0fe282c11b6a9f72c283ed093946bbaf802132220df2c6e3dd8f0;

        proofs[1] = new bytes32[](20);
        proofs[1][0] = 0x8def68e3149229019f0fa1304c1e53c18ee50b7ec44f553d474ae48fa3df9259;
        proofs[1][1] = 0x7eb0d78187050f30342dba46f7f501f38a3f4eea50ba1c6ac6b5c6d0104faf1b;
        proofs[1][2] = 0x38487e3dc7ca891afc2105eb65f24f4c6da2cc56e6bff61aee1d0959f1e34bc2;
        proofs[1][3] = 0x1e191a36e0b5dad20f33a81e66e0c745e5e1f6bc1cc9cddb82e0c379e251c48d;
        proofs[1][4] = 0xc9d539a02bd668dbb708b122701d62eddec0ef7a83335309f42c1ed90b7b1625;
        proofs[1][5] = 0xeb746c684db88834abf0b4dddeb61fd3a1b6fd8eef9b2946f7ef351c141a8680;
        proofs[1][6] = 0x8712febe969414bab02ca60625d8aa133ec3c91905f4a59d4e33bcd69439cc72;
        proofs[1][7] = 0x0f383ad1b5d2604c1d1aa34c179e63546a137fb34e181dcf4314b02b44126970;
        proofs[1][8] = 0x9f44274c7aef266f371ec79f5a8878d114b0b243e6c1187389596a41b43adc7c;
        proofs[1][9] = 0x9bad01975612b36e3d17a4e671fec9587bf2ff9c2f20fc6cf23117fae9f312c6;
        proofs[1][10] = 0xea26647104b5684e5c2403d2d8f05bde7db25099ef377db6d4027b528251cc10;
        proofs[1][11] = 0xfe3500dde2bed00296463b6d13ebd12f344d8faacc36c174cd41534b12514fc9;
        proofs[1][12] = 0x65cad962aa0a887a90e602f03e6762c1e64fb993ece0f41ac50e120d11ad822b;
        proofs[1][13] = 0x3ec4669cb79b597ccb2281375c438276fe30ce254e15b896fc842292769091a4;
        proofs[1][14] = 0x77e3bd837da9f0428f248a69c550970c47ae97270fb2742789e6b6c389c23814;
        proofs[1][15] = 0xe90336b6923bd7a8831b54071bb6e78cbccc5bf08ae8e787f51a5eeb48117cb9;
        proofs[1][16] = 0x64757d55d0504f7009041bfd6489ff067370f079995a34d41f9bbde8e1dd585f;
        proofs[1][17] = 0xbc31cce579e57d1ff23e47ab6fb16bcdc906264f1af379022127878e0625dd29;
        proofs[1][18] = 0x112c8fef136df58820b25561114a16b0d1ad0f916d7afb09052eac92c2b0b18a;
        proofs[1][19] = 0xfa03c3f66ee0fe282c11b6a9f72c283ed093946bbaf802132220df2c6e3dd8f0;

        targetData[0] = abi.encodeWithSignature(
            "claim(address[],address[],uint256[],bytes32[][])",
            users,
            tokens,
            amounts,
            proofs
        );

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiMerklDecoderAndSanitizerName);



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
        // setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiBaseDecoderAndSanitizerName));

        // // 2. Generate the merkle tree and get the root
        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // // 3. Generate proofs for the actions you want to execute
        // uint256 opsAmt = 2;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[3 * 12 + 2 + 2 + 1];
        // manageLeafs[1] = leafs[3 * 12 + 2 + 2 + 2];
        // // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data - both operations target USDC token
        // address[] memory targets = new address[](opsAmt);
        // targets[0] = getAddress(sourceChain, "USDC"); // approve
        // targets[1] = getAddress(sourceChain, "USDC"); // transfer

        // bytes[] memory targetData = new bytes[](opsAmt);
        // targetData[0] = abi.encodeWithSignature("approve(address,uint256)", 0x28d2e2759dCB5CFda1c868Fee714B194c25a8dCB, type(uint256).max);
        // targetData[1] = abi.encodeWithSignature("transfer(address,uint256)", 0x62d9113BFf4414e7D3600FfB4d6255D29e5CFc42, 1e6);

        // address[] memory decodersAndSanitizers = new address[](opsAmt);  
        // decodersAndSanitizers[0] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);
        // decodersAndSanitizers[1] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);



        uint256[] memory values = new uint256[](opsAmt);

        // extra
        // string memory filePath = "./leafs/Strategist1ArbitrumLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs("./leafs/Strategist1ArbitrumLeafs.json", leafs, merkleRoot, manageTree);

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
