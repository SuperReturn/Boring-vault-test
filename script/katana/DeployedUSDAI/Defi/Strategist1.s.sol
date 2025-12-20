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

        address[] memory tokens = new address[](1);
        tokens[0] = address(KAT);

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
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 70444065355932;

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

        address[] memory users = new address[](1);
        users[0] = address(vault);

        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](16);
        proofs[0][0]  = 0x2a8702e207507e546556505f44f24cf182bb97d92be5447193817b8bf25ddc7e;
        proofs[0][1]  = 0x273dd7055b3b37c3362c2553fc000ade329524e2de27a0390ceb0f75dcb56a40;
        proofs[0][2]  = 0xdaf4f4b53240c6ad43de95021154564a36f9e126c76133a114a4b145fb2ec6f0;
        proofs[0][3]  = 0xafad3dded35558e78ae159d2773e7a2502139e8e242a3baf78189739cef26a24;
        proofs[0][4]  = 0xbc3873f71f9f26c68ba3dcd21338a18a515b3b88dee143e2fe0f1490f7b51070;
        proofs[0][5]  = 0x9fa451ed61ca70de026cdbfa7c0ecc2ba16847d4698d4462fc420c8eb3b10c1b;
        proofs[0][6]  = 0x5d6424271d504a09db4ac19fd76173ebba86089588ac8aed45394563ec055a52;
        proofs[0][7]  = 0x941273cd1f0277de35d85876b8187683998c8af3a3021af65e6b7424ff756690;
        proofs[0][8]  = 0x18fa0ef7121c2ddeeb8fe3f123eeafe6d28a25cdb063a084a020de139559dbe3;
        proofs[0][9]  = 0x94458df5ac8e01907df6bb6ce6ac0f38b783009d77f49fa4b6d0f4980228460b;
        proofs[0][10] = 0xf89087ea4f897dd43d799c9381e7e882c04dfc9021be76cff1896c137473aeb7;
        proofs[0][11] = 0x006be4a42205b8557a50119290a229bad0ad51f5301648835be591034a6dccd1;
        proofs[0][12] = 0xfa4259d497183ed352ee54c1ac6f00efb6f7847c1faca6e9da62c01ab565fef3;
        proofs[0][13] = 0x7cad49fc0d106ec312210422bbe3bd430faba068e032e754353149b75c910b2b;
        proofs[0][14] = 0x329ec10edd1227671995267396925a63f050c1effbaed8483a63c94d4e72aa42;
        proofs[0][15] = 0x5ee20be85836634dc6dcee57e8185b3c9e5b2cde878f86fc76b9ccef2a7456f9;

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
