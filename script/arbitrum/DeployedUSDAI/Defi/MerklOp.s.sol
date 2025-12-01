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
        amounts[0] = 35886834331621;
        amounts[1] = 16952808529821;

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
        proofs[0][0] = 0xa748287a4087600a0c0e90c49980c9c2753cf8880feb7add91eef64c83491b3b;
        proofs[0][1] = 0xb332e41499dda0d0c00cddacd7baa1eb95832456feab534138c5af7848412319;
        proofs[0][2] = 0x5860a04652d12f0897393ba622cf830d8c858df8f084540030be3e64b5d2f682;
        proofs[0][3] = 0x93ebe92c3dcf10bb958a8121c00989737279f39105b722c686f1b78dd9461569;
        proofs[0][4] = 0xdc808fd241cf257d8882655c7610b542b8619cd4df97f8ee4ce5e928cca2c813;
        proofs[0][5] = 0xa4d94fd8feacfdb0027e6957b5d72fc1553cda0031256778525c1d8a23f26dc5;
        proofs[0][6] = 0x6445376d23a7cc6f4d718db199ce170abd4eefb5d7a3bc991bc5442feb761cdd;
        proofs[0][7] = 0x9be1bb76148132afba8b9ab4dc8db58a8bfe51510f163b926f896601364bbc9b;
        proofs[0][8] = 0x2bace6ab0f360457340dd2ae217571588c2d982b7633223fd6dd302bd4918ea9;
        proofs[0][9] = 0x028451b5aecb79a0d6d1bae67009b2eeb4a0e6dd28e7c83c6f93faa1fad0cea6;
        proofs[0][10] = 0xb77ceacb8d3a178eb9e6e932ed2b261f69df3b4045d0169b92b3cda420d5c38c;
        proofs[0][11] = 0xb1cd25d573d1ba0e08932612a1a7fb642113a974a0b72a4b3dd5b94b0fa22eae;
        proofs[0][12] = 0x493e74643cc241f7a74c335df6938ea11c98e5ce1f62ea20e7a109bbfcde7762;
        proofs[0][13] = 0x474f003cf1c0de95f075ecf35e64ab514a5c77ac7361ba4699c644b903d3c032;
        proofs[0][14] = 0x9ee03f60f95d2d60763608b322fd997be2598a59070daabe7d9c97c7bc9ba2fa;
        proofs[0][15] = 0xfee25c0791fee24f90a984c89d864aeb4f3874815d4684920b62ff8e6a1185bf;
        proofs[0][16] = 0x9ac52a8be9eb5f323339fb66b063a2ca6c24eeebe8c3e552ec6dcd057544dc21;
        proofs[0][17] = 0x75d6df4217d4999d72d61e323c980fb7e2b5c2155df550d84c20c6beec03fbe1;
        proofs[0][18] = 0x8ebc1b01cd9b50e0761fee5db767054187f0b9c9d24a7c206fa14e5d39279db7;

        proofs[1] = new bytes32[](19);
        proofs[1][0] = 0xb61daaae85721cfad4797575a6b658927036fe9567b443b77f8a35abfd5d644c;
        proofs[1][1] = 0xf27c6df6817e1b39958bf20e49abc8aacde7e39880815c2d4506a520017124e0;
        proofs[1][2] = 0x092e89848910a5f2e1c2ffbaee9f4fdeb030423d34fe42eaa3fba9922e59d860;
        proofs[1][3] = 0xf258d3eecdfcb08b38dbe35a2f93528277db91b2ef9990abf31a2c811e5b1191;
        proofs[1][4] = 0x8ebdef0c3dbdb8eeda5151ed796e8254098cdcc514bb16be680ffbf88779151b;
        proofs[1][5] = 0xc88b992b7367e79b330e9becf8348177f0a9a0ccc095562efbeeb110b1943593;
        proofs[1][6] = 0x8692ad4855e112cf1b79b0156828629984888330310892c2e5c2f1344b1256f3;
        proofs[1][7] = 0x5e22eff1b33bdc9df3c8e21764379ab95a871df4c2834cb688655266bf1b558f;
        proofs[1][8] = 0xf2f02d2dfa31494d49f67809a7fc0cbfed8429e2ebd3b285b08c707c4992fc69;
        proofs[1][9] = 0x4d227d2083f782457e8637ae7b8d98253aa09316c5fbd59c3e53817f3eaad4b0;
        proofs[1][10] = 0xf6d673eb518380d8f179e40f12ae78d02a6814d792fcf6e0dd21e2e96d2cbdf6;
        proofs[1][11] = 0x0889d1a446123e03cf85ef86e599b64cd2a28f0e97232d2775e7238c1984364a;
        proofs[1][12] = 0xaf48ab5848f698879ae1debef993f9ae733c51b9e2e321a184e84e8c19d6569b;
        proofs[1][13] = 0x1eb3ecbd85dff6e7977f4d841b62d1b6101d00a7ad5f4122245d072e54d06510;
        proofs[1][14] = 0x25ff707e275fea9c6fc4b8823002c5b02b66810571d6c087be3187e2107de26d;
        proofs[1][15] = 0x308145be8ab8ff79c53b63669546ed08524478e26c4ea66f915c292b0ba89287;
        proofs[1][16] = 0x9ac52a8be9eb5f323339fb66b063a2ca6c24eeebe8c3e552ec6dcd057544dc21;
        proofs[1][17] = 0x75d6df4217d4999d72d61e323c980fb7e2b5c2155df550d84c20c6beec03fbe1;
        proofs[1][18] = 0x8ebc1b01cd9b50e0761fee5db767054187f0b9c9d24a7c206fa14e5d39279db7;

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
