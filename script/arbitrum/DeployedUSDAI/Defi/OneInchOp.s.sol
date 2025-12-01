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

/*
notice possible issues:
1. arbitrum operation is totally diff from mainnet, need to rewrite all logic for mainnet
example tx: https://arbitrum.etherscan.io/tx/0x563c1e3daaeb60ac16d203040f2aeb9c15b25dc96f8c2be071b36af9625e6a87
*/
contract OneInchOp is Script, ArbitrumAddresses, MerkleTreeHelper, ContractNames {
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
        setAddress(true, arbitrum, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiOneInchDecoderAndSanitizerName));

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);
        
        // only support instant mint with USDC for now
        _addLeafsFor1InchArbitrum(leafs, getAddress(sourceChain, "ARB"), getAddress(sourceChain, "USDC"));

        // 2. Generate the merkle tree and get the root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        uint256 opsAmt = 2;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[0];
        manageLeafs[1] = leafs[1];

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // 4. Prepare the action data
        address[] memory targets = new address[](opsAmt);
        targets[0] = getAddress(sourceChain, "ARB");
        targets[1] = getAddress(sourceChain, "AggregationRouterV6");

        bytes[] memory targetData = new bytes[](opsAmt);

        targetData[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            getAddress(sourceChain, "AggregationRouterV6"),
            type(uint256).max
        );

        DecoderCustomTypes.SwapDescription memory swapDescription = DecoderCustomTypes.SwapDescription(
            getAddress(sourceChain, "ARB"),
            getAddress(sourceChain, "USDC"),
            payable(getAddress(sourceChain, "oneInchExecutor")),
            payable(address(vault)),
            1e15,
            300,
            0
        );
        targetData[1] = abi.encodeWithSignature(
            "swap(address,(address,address,address,address,uint256,uint256,uint256),bytes)",
            getAddress(sourceChain, "oneInchExecutor"),
            swapDescription,
            // remove 0x
            // get data from https://portal.1inch.dev/documentation/apis/swap/classic-swap/swagger?method=get&path=%2Fv6.1%2F42161%2Fswap
            // and use the decoder in explorer: https://arbiscan.io/inputdatadecoder
            hex"0000000000000000000000000000000000000000000000000000dd00004e00a0744c8c09912ce59144191c1204e64559fe8253a0e49e654890cbe4bdd538d6e9b379bff5fe72c3d67a521de5000000000000000000000000000000000000000000000000000002ba7def30000c20912ce59144191c1204e64559fe8253a0e49e6548ab4fb502ba6efc777723fe8e1ed0addc45a0b24a6ae40711b8002dc6c0ab4fb502ba6efc777723fe8e1ed0addc45a0b24a111111125421ca6dc452d289314280a0f8842a650000000000000000000000000000000000000000000000000000000000000134912ce59144191c1204e64559fe8253a0e49e6548"
        );

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiOneInchDecoderAndSanitizerName);
        decodersAndSanitizers[1] = deployer.getAddress(UsdaiOneInchDecoderAndSanitizerName);

        uint256[] memory values = new uint256[](opsAmt);

        // extra
        string memory filePath = "./leafs/OneInchArbitrumLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs(filePath, leafs, merkleRoot, manageTree);

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
