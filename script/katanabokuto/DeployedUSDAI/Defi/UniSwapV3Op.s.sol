// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;
import "forge-std/Script.sol";
import {KatanaBokutoAddresses} from "test/resources/KatanaBokutoAddresses.sol";
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
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";
import {console} from "forge-std/console.sol";

/*
notice possible issues:
1. sepolia operation is totally diff from mainnet, need to rewrite all logic for mainnet
example tx: https://sepolia.etherscan.io/tx/0x563c1e3daaeb60ac16d203040f2aeb9c15b25dc96f8c2be071b36af9625e6a87
*/

contract UniSwapV3Op is Script, KatanaBokutoAddresses, MerkleTreeHelper, ContractNames {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using Address for address;

    Deployer public deployer;
    BoringVault vault;
    ManagerWithMerkleVerification manager;

    function setUp() external {
        vm.createSelectFork("katanabokuto");
        setSourceChainName("katanabokuto");
        
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        vault = BoringVault(payable(previoussuperUSD));
        manager = ManagerWithMerkleVerification(deployer.getAddress(UsdaiVaultManagerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(privateKey);
        
        setAddress(true, optimism, "boringVault", address(vault));
        setAddress(true, optimism, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, optimism, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, optimism, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiUniswapV3DecoderAndSanitizerName));


        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        address[] memory token0 = new address[](1);
        token0[0] = getAddress(sourceChain, "USDC");
        address[] memory token1 = new address[](1);
        token1[0] = getAddress(sourceChain, "OP");

        _addUniswapV3Leafs(leafs, token0, token1);

        // 2. Generate the merkle tree and get the root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        uint256 opsAmt = 2;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[3];
        manageLeafs[1] = leafs[7];

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // 4. Prepare the action data
        address[] memory targets = new address[](opsAmt);
        targets[0] = getAddress(sourceChain, "OP");
        targets[1] = getAddress(sourceChain, "uniV3Router");

        bytes[] memory targetData = new bytes[](opsAmt);

        targetData[0] = abi.encodeWithSignature(
            "approve(address,uint256)", getAddress(sourceChain, "uniV3Router"), type(uint256).max
        );

        DecoderCustomTypes.ExactInputParams memory exactInputParams = DecoderCustomTypes.ExactInputParams(
            abi.encodePacked(getAddress(sourceChain, "OP"), uint24(3000), getAddress(sourceChain, "USDC")),
            address(vault),
            block.timestamp + 1000000,
            1 * 1e18,
            1 * 300000 // should be updated
        );
        targetData[1] = abi.encodeWithSignature("exactInput((bytes,address,uint256,uint256,uint256))", exactInputParams);

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiUniswapV3DecoderAndSanitizerName);
        decodersAndSanitizers[1] = deployer.getAddress(UsdaiUniswapV3DecoderAndSanitizerName);

        uint256[] memory values = new uint256[](opsAmt);

        // extra
        string memory filePath = "./leafs/UniSwapV3Leafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs(filePath, leafs, merkleRoot, manageTree);

        // try to less the var number to prevent "Stack too deep" error
        manager.setManageRoot(vm.addr(vm.envUint("OP_STRATEGIST")), merkleRoot);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("OP_STRATEGIST"));

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
