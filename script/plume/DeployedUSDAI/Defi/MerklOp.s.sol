// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;
import "forge-std/Script.sol";
import {PlumeAddresses} from "test/resources/PlumeAddresses.sol";
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

contract MerklOp is Script, PlumeAddresses, MerkleTreeHelper, ContractNames {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using Address for address;

    Deployer public deployer;
    BoringVault vault;
    ManagerWithMerkleVerification manager;

    function setUp() external {
        vm.createSelectFork("plume");
        setSourceChainName("plume");
        
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        vault = BoringVault(payable(previoussuperUSD));
        manager = ManagerWithMerkleVerification(deployer.getAddress(UsdaiVaultManagerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // address auth = vm.addr(privateKey);

        // uint256 strategist = vm.envUint("PLUME_STRATEGIST_MERKL");
        
        vm.startBroadcast(privateKey);
        
        setAddress(true, plume, "boringVault", previoussuperUSD);
        setAddress(true, plume, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, plume, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, plume, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMerklDecoderAndSanitizerName));

        /*
        claim params:
        https://api.merkl.xyz/v4/users/0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB/rewards?chainId=98866
        amount and proofs should be exactly same, otherwise it will revert
        */
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 186880523690118177509342;

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        address[] memory tokens = new address[](1);
        tokens[0] = WPLUME;

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
        proofs[0] = new bytes32[](17);
        proofs[0][0] = 0xc1c05ab67ead10580b5d807d32a87ba37b6df561ef281da8efd5247f6e17f798;
        proofs[0][1] = 0xd0a3a7eb4ccebc3e4ceccf20e4b6301cb3bc2e9bfaea73f61df71561c2f101ec;
        proofs[0][2] = 0x57b0ecef46cb936b684a9ad5bee02eb5648eb33a19473023ab4586d08cf13de8;
        proofs[0][3] = 0x1f46ed7581f2491c3ab17e1bb044217a94cc030c5efad9784e252e27a1de7b76;
        proofs[0][4] = 0x936f787ab66fc4e292f8e29990e2d32e5708a076be466db1def9927ba34ed21c;
        proofs[0][5] = 0xd0cf685b568b392282cefddef8cc6fc7975f1e9eda8cb88ab8fa6fc9a8b3da54;
        proofs[0][6] = 0xda2e5a80f8ef9cc69ad297daff13dc5af4db79dea0f2eddfec4ce03ed670ee80;
        proofs[0][7] = 0x9b574ae12db7d43be99a90acee3ced984e26c80e5526e1ec42e05c433cbd41f4;
        proofs[0][8] = 0x4dc21c433ff84a8d2a6e051ead82023d1c6f1a1f0e59f8446a845bb446295863;
        proofs[0][9] = 0xd4a6a683864a7b3881a2c6f6989a8f60b4d9f7cb9a4940e1040fddf85979a618;
        proofs[0][10] = 0x4c9c2a3da46a1d08d28044e9d0753486b89f01861709bba4f928249e449262e9;
        proofs[0][11] = 0x26f563d28f91064d365f18562b9f91da1d71cdba103bcadad49702a29f06ebb2;
        proofs[0][12] = 0xc81c1ff86f2390d3a91f27f9753aa371c37ac85cd7e7267468b3e3b3dc7b8083;
        proofs[0][13] = 0x853551e3893d9e635a9fee91b435a29173760dd1642181e674acdeaae3150ffb;
        proofs[0][14] = 0x88c4b65a740ba1b08b6165b3038187c0e3a0d75c6eac2d382712577542a2962d;
        proofs[0][15] = 0x7495bc97da6416fcf5d1e85c7244ce244965a2b2f01c79a317934e73b61341cb;
        proofs[0][16] = 0x02d7d74673492889a3000864f77fa40ce0ab99926b810a9a3f6887a58659fc0a;

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
        string memory filePath = "./leafs/MerklLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs(filePath, leafs, merkleRoot, manageTree);

        // try to less the var number to prevent "Stack too deep" error
        manager.setManageRoot(vm.addr(vm.envUint("PLUME_STRATEGIST_MERKL")), merkleRoot);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("PLUME_STRATEGIST_MERKL"));

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
