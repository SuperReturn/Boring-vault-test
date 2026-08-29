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

        address[] memory tokens = new address[](3);
        tokens[0] = address(KAT);
        tokens[1] = address(0x1e5eFCA3D0dB2c6d5C67a4491845c43253eB9e4e); // MORPHO
        tokens[2] = address(0x203A662b0BD271A6ed5a60EdFbd04bFce608FD36); // vbUSDC

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
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 163494908335337677660;
        amounts[1] = 285391386286908839;
        amounts[2] = 2848733;

        // 1. Create merkle tree leaves for allowed actions

        // 2. Generate the merkle tree and get the root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        uint256 opsAmt = 1;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[0];

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data
        address[] memory targets = new address[](opsAmt);
        targets[0] = merklDistributor;

        bytes[] memory targetData = new bytes[](opsAmt);

        address[] memory users = new address[](3);
        users[0] = address(vault);
        users[1] = address(vault);
        users[2] = address(vault);

        bytes32[][] memory proofs = new bytes32[][](3);

        // Proofs for KAT
        proofs[0] = new bytes32[](17);
        proofs[0][0]  = 0x75a4e34c7d4b61835e77bbc79fc48e71f4133a222305825ca7d9b4b076f51296;
        proofs[0][1]  = 0x9f7e456e93781a9f0a5ef0345532dbbe0bf02fecb44318209c0aad85eb20c583;
        proofs[0][2]  = 0x8f21145866a97639b8a5879cd3bf7a31dece50ada1000626ffdbcb0fb2e3c46b;
        proofs[0][3]  = 0x327ec038ee6f003ca02dd846d8c636bc3f470586ab365c1809d27947eb97adda;
        proofs[0][4]  = 0xc0a0278b6e4a3b9ea98451148c5bcb88d94f5e1fe54174b6af554e960aed4c30;
        proofs[0][5]  = 0x42d94e51e1d8939e528d77c2e4a0ee82ac651523b049750cbead8ce86fcd36cb;
        proofs[0][6]  = 0xef3cc42171bb32ea3d4d14d6060f895c080f18ba25b44aaab4ce74e54696c939;
        proofs[0][7]  = 0xf4658864b75fb80b570069abbcf3da0af3b527d9b20bd391fb5479837f045829;
        proofs[0][8]  = 0x1df33777ff4960abd040d5ac36277843148f87d165b516a24e61c6be6409e931;
        proofs[0][9]  = 0x578abac3b0ba834f365d1ebf704c588ea9414b2418d2d4b9ab1ee38051c95555;
        proofs[0][10] = 0x3a4934d3fefb2b1875e569a5cff9040a1e904e0d0c40f90b12a791482812851f;
        proofs[0][11] = 0x826490675ef811a0b41a8d223ff4080b2ec7c6335b622082667520060c911509;
        proofs[0][12] = 0x1a0b1d276b4c22e76bf15460b671c37571bd9f10805051941b9699e2e1a2dca3;
        proofs[0][13] = 0xf539cd22623e66f8a874fe5f7b42aaf7d27d625d13f655dc3a444ef19abe8410;
        proofs[0][14] = 0x2ebf5f86f351f4dc6936210674bd61ff0eb4a49aec3bf8d3573b55233a6fd32d;
        proofs[0][15] = 0xe774c4fdd0aaa4c6c06887d70d65e4d8c060804486395a55cd2a149af49af715;
        proofs[0][16] = 0x8639384827944c54b5805199464059db8f5f4f732a7d996ae9ea9817e553fbfe;

        // Proofs for MORPHO
        proofs[1] = new bytes32[](17);
        proofs[1][0]  = 0x9596f73ea9f631cd562ba4628b04c300117eb25f30fd0dc1177570f7e33ccb70;
        proofs[1][1]  = 0xef57da698a29a32d7ed0abc58286863436bdb88ac1e3049a8364a542f8245752;
        proofs[1][2]  = 0x872d1632550a270025428fb36f395e3e097ffe987635e8ed7a0dd1d8462441ae;
        proofs[1][3]  = 0x54d04f9776b17a4c02c581c756582c6d050707ce633f0893864e8fa256bc9135;
        proofs[1][4]  = 0x89948b030ac23c5435515ee597741479e2d508798e1013c820e801dd2aa9345b;
        proofs[1][5]  = 0xe1008ca572f231b06456dfc6e8fa168850ecfc3ad7579ac221e35f09f25fef08;
        proofs[1][6]  = 0xeaeb21a75977f9918a877cc254f9b3557dd5746277dfdbf7b198db88915c9f7b;
        proofs[1][7]  = 0x4cab3c2d926df5e3f5b5238714b81a023a835584f5129b7b41bac7e7ef2197ef;
        proofs[1][8]  = 0x4c6a4c3b5c007f4c0313ee4558abb29d8bc16baeab72f1892d9d42eca6223491;
        proofs[1][9]  = 0xd39e1f168c5617e228c7b2fa811474177612d5db06e249afe22479a56797e957;
        proofs[1][10] = 0x62bd14d099dc2997dfad86dbc099c736d4110198bd3c7d680c60d5c412cc09e1;
        proofs[1][11] = 0x80453185d54236257e13af4d87593b310925f97762b9f73c0b60057bb80caa6d;
        proofs[1][12] = 0x9b21fb0ed4ea2f2b6eaf3230748facfbc389e0718877512d72b25429b854428a;
        proofs[1][13] = 0xeef593e68b6230311b3a3173b9b161d68b99d4f91d799650c760294d4d7c8089;
        proofs[1][14] = 0x2ebf5f86f351f4dc6936210674bd61ff0eb4a49aec3bf8d3573b55233a6fd32d;
        proofs[1][15] = 0xe774c4fdd0aaa4c6c06887d70d65e4d8c060804486395a55cd2a149af49af715;
        proofs[1][16] = 0x8639384827944c54b5805199464059db8f5f4f732a7d996ae9ea9817e553fbfe;

        // Proofs for vbUSDC
        proofs[2] = new bytes32[](17);
        proofs[2][0]  = 0x6e157d4c7496e7c33f2e3d40ba8b954acd1e0b01a2373f1b2231551aeda33452;
        proofs[2][1]  = 0x730aa8b8e5e88d06ae4d62814ab16b7144c8256cd45237fe9bf764cecedf9656;
        proofs[2][2]  = 0x3e80e99abca1319431c66ea8dec01c892e33ef78913be92de49def38b38d0853;
        proofs[2][3]  = 0x3b6d5037e0e53e50566ab3a684d756ff4d69751313f6612572644e625461a7cb;
        proofs[2][4]  = 0x08c2aaf7b4ac393f577a83682a0a5ec1f284e00158594b3a72b770fdef0d1093;
        proofs[2][5]  = 0x2ca55faec25e7dec1ec816c482e6295e1951bff8976771d744ef2cd7af52b496;
        proofs[2][6]  = 0xc167f5a3c8663dfe746988dc6f331dcb0e02cbc948dc567193bf3dc76698b9d8;
        proofs[2][7]  = 0x6c1cfc271823eee848ea3c570aba03cef63fb23d9f4c008c2f13f5c54999e9cd;
        proofs[2][8]  = 0xc07809ba243a275fc0313eda2be93238957838a61ce92553547e4e16f82278c2;
        proofs[2][9]  = 0x1b915acffb82e8496ed86a784639aa6398ab28e8be5e90fba9ae9eb58f666307;
        proofs[2][10] = 0x5e5ad3c6099e7161d0756a6b13853ec91965ba3291cc1b3a4358cd97b20306db;
        proofs[2][11] = 0xa84c1be9db2d79929021bec5f4690c230f0fa7aec0e184e92e9fc4464b3afa93;
        proofs[2][12] = 0x27267e02a1cbc9b28faed83e9bc995a92df525aa6c43425086dfc99849a45dda;
        proofs[2][13] = 0xf539cd22623e66f8a874fe5f7b42aaf7d27d625d13f655dc3a444ef19abe8410;
        proofs[2][14] = 0x2ebf5f86f351f4dc6936210674bd61ff0eb4a49aec3bf8d3573b55233a6fd32d;
        proofs[2][15] = 0xe774c4fdd0aaa4c6c06887d70d65e4d8c060804486395a55cd2a149af49af715;
        proofs[2][16] = 0x8639384827944c54b5805199464059db8f5f4f732a7d996ae9ea9817e553fbfe;

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
        // 1. Create merkle tree leaves for allowed actions
        // ManageLeaf[] memory leafs = new ManageLeaf[](128);

        // _addKatanaMorphoLeafs(leafs, address(vault), morphoVaults);

        // 2. Generate the merkle tree and get the root
        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        // Approve USDC
        // Deposit USDC
        // uint256 opsAmt = 2;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[0];
        // manageLeafs[1] = leafs[1];

        // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // 4. Prepare the action data
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

        // targetData[1] = abi.encodeWithSignature(
        //     "withdraw(uint256,address,address)",
        //     1e6, // assets
        //     address(vault), // receiver
        //     address(vault)  // owner
        // );

        // address[] memory decodersAndSanitizers = new address[](opsAmt);  
        // decodersAndSanitizers[0] = deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName);
        // decodersAndSanitizers[1] = deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName);


        uint256[] memory values = new uint256[](opsAmt);
        // extra
        // bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        // _generateLeafs("./leafs/Strategist1KatanaLeafs.json", leafs, merkleRoot, manageTree);

        // // try to less the var number to prevent "Stack too deep" error
        // manager.setManageRoot(vm.addr(vm.envUint("KATANA_STRATEGIST")), merkleRoot);

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
