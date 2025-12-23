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

contract Strategist1 is Script, KatanaAddresses, MerkleTreeHelper, ContractNames {
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
        // uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // address auth = vm.addr(privateKey);
        
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        
        setAddress(true, katana, "boringVault", previoussuperUSD);
        setAddress(true, katana, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, katana, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, katana, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMerklDecoderAndSanitizerName));

        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(KAT);

        _addMerklLeafs(leafs, merklDistributor, tokens);
        setAddress(true, katana, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName));
        _addKatanaMorphoLeafs(leafs, address(vault), morphoVaults);

// Merkl operation
        setAddress(true, katana, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMerklDecoderAndSanitizerName));
        /*
        claim params:
        https://api.merkl.xyz/v4/users/0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB/rewards?chainId=747474
        amount and proofs should be exactly same, otherwise it will revert
        */
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 6782;
        amounts[1] = 248441523619179489;

        // 1. Create merkle tree leaves for allowed actions

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
        proofs[0] = new bytes32[](16);
        proofs[0][0]  = 0x15f9654b81b0e12c869988ee3eaae4200fd5467329e1fa7b842e9c3594c69c11;
        proofs[0][1]  = 0x672c52feb62138b086d73c060c83c52c53370be289acd777ec0bfbe8f04ae5a2;
        proofs[0][2]  = 0x6aa737fd618cdfe486f905f177b7ec63604575b099e25b6c4f70267ccb84f48e;
        proofs[0][3]  = 0x443100ecddaf0e735350e476bfe3b25eb61bd0943d545b0ee3c9f331ac8b654b;
        proofs[0][4]  = 0x9419966c7561d1d5c663a471c81adbc05d14ed5584bcbfc9bd4955d71e6e2bf3;
        proofs[0][5]  = 0x672c36c97f3c048b28d2d9a539deb832ce74969a681e1f1d1f1dab04d3cefd57;
        proofs[0][6]  = 0xf81fe3598acadef30d79111cb70d2ac94067dbce43cbd5ecc4afdd937d90bccb;
        proofs[0][7]  = 0xcafcb00e5dbe7feab2edf62e8e66112a6698a5c279d3bb5ac6f2603f9a528f7a;
        proofs[0][8]  = 0x1c3a2acca33bf16636de20ec6929395df6af07334234c9f6d9dc3980c7b79105;
        proofs[0][9]  = 0x6ac9be6f0135921345e57f2f8ed92d84cc4819012f094d56cd1ff522b2153e8a;
        proofs[0][10] = 0xa7973b99c44d6b9bb7de264c9ccb590b39c877a0a71d976ce612124342e9dad1;
        proofs[0][11] = 0x2b7d3b78c8f6f9f4e4c33ec70a806b6287bc4816ef3472ba5e0147e7a87a5670;
        proofs[0][12] = 0xeca9b08151b0c1649fff575d2bd94c503a2e39c189cbb312d037175b4fc19e37;
        proofs[0][13] = 0xe0122b1a34e066bdeeea4e2894bedff4d982ef6c772a462e15ce2daf584f085e;
        proofs[0][14] = 0x457f6125464bfc42dbad128c5adb536a9f47c567cb54593900ced4856924b741;
        proofs[0][15] = 0x43ef9426487fee83ba692d9a6cd7ea89edc43799a5778734fe1fb2bd2394fc68;

        proofs[1] = new bytes32[](16);
        proofs[1][0]  = 0x08ccdfafe83c7c28b78198dd7a1ed86912d2b46af38c855af356733ca630b1c2;
        proofs[1][1]  = 0xfc481649b30c35ea7035b227dc461abaedbe3a9e1abf915547099b2c70e26a2a;
        proofs[1][2]  = 0xb1fac2cb99e723b6fc474c3ff0edc857e27f8e80e98d2d84dcfb806c5050b8bd;
        proofs[1][3]  = 0x09b4b9991e4dfa2564822daab6d664b583815ffaf57789dd17d12d9532c511c6;
        proofs[1][4]  = 0x084ae9d5eda5c80ea5d4fe73bb8711dfa1077a83a11a5add1b0004155ea1b5e6;
        proofs[1][5]  = 0xb16a9530cac1665588a25ce4f1c4a9bd6205d856784b4f68e5f29f7cdc0e0b7e;
        proofs[1][6]  = 0x004adb594cf7a9057316431472e6b1b15d0b5a97285a614924074d1683f01a72;
        proofs[1][7]  = 0xec60e57137a489399449bc0c69ce53b2babc63eec88efebedcb95756ebb7ff0b;
        proofs[1][8]  = 0x33fcd6cce09c57c924244e08aca0404da61f50124deb0de34b30bb1b1d8c8eaf;
        proofs[1][9]  = 0x4185a4ead7305e157fd1d769c90e5060b6411efd6b8dca8d5a9f5601df6114c1;
        proofs[1][10] = 0x604cf35c73e375717b14bab4fcbd02d5877549f1e70abda2584515f952f760e1;
        proofs[1][11] = 0x818fe82099a729c3e92801fcdcbf12da18fb3d0b17a256f14faa7cfba40603de;
        proofs[1][12] = 0xa1e038feb188b2fd67a2675d1bdba3f30ad18db546ad559b64204706aa52c2be;
        proofs[1][13] = 0xe0122b1a34e066bdeeea4e2894bedff4d982ef6c772a462e15ce2daf584f085e;
        proofs[1][14] = 0x457f6125464bfc42dbad128c5adb536a9f47c567cb54593900ced4856924b741;
        proofs[1][15] = 0x43ef9426487fee83ba692d9a6cd7ea89edc43799a5778734fe1fb2bd2394fc68;

        targetData[0] = abi.encodeWithSignature(
            "claim(address[],address[],uint256[],bytes32[][])",
            users,
            tokens,
            amounts,
            proofs
        );

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiMerklDecoderAndSanitizerName);


// Morpho operation
        // setAddress(true, katana, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName));
        // // 1. Create merkle tree leaves for allowed actions
        // ManageLeaf[] memory leafs = new ManageLeaf[](128);

        // _addKatanaMorphoLeafs(leafs, address(vault), morphoVaults);

        // // 2. Generate the merkle tree and get the root
        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        // // Approve USDC
        // // Deposit USDC
        // uint256 opsAmt = 2;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[0];
        // manageLeafs[1] = leafs[1];

        // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data
        // address[] memory targets = new address[](opsAmt);
        // targets[0] = getAddress(sourceChain, "USDC");
        // targets[1] = morphoVaults[0];

        // bytes[] memory targetData = new bytes[](opsAmt);

        // targetData[0] = abi.encodeWithSignature(
        //     "approve(address,uint256)",
        //     morphoVaults[0],
        //     type(uint256).max
        // );

        // targetData[1] = abi.encodeWithSignature(
        //     "deposit(uint256,address)",
        //     1e5,
        //     address(vault)
        // );

        // // targetData[1] = abi.encodeWithSignature(
        // //     "withdraw(uint256,address,address)",
        // //     1e6, // assets
        // //     address(vault), // receiver
        // //     address(vault)  // owner
        // // );

        // address[] memory decodersAndSanitizers = new address[](opsAmt);  
        // decodersAndSanitizers[0] = deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName);
        // decodersAndSanitizers[1] = deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName);


        uint256[] memory values = new uint256[](opsAmt);
        // extra
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs("./leafs/Strategist1KatanaLeafs.json", leafs, merkleRoot, manageTree);

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
