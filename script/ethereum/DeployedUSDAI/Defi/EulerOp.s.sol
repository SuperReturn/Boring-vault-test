// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;
import "forge-std/Script.sol";
import {EthereumAddresses} from "test/resources/EthereumAddresses.sol";
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

// struct BatchItem {
//     /// @notice The target contract to be called.
//     address targetContract;
//     /// @notice The account on behalf of which the operation is to be performed. msg.sender must be authorized to
//     /// act on behalf of this account. Must be address(0) if the target contract is the EVC itself.
//     address onBehalfOfAccount;
//     /// @notice The amount of value to be forwarded with the call. If the value is type(uint256).max, the whole
//     /// balance of the EVC contract will be forwarded. Must be 0 if the target contract is the EVC itself.
//     uint256 value;
//     /// @notice The encoded data which is called on the target contract.
//     bytes data;
// }

contract EulerOp is Script, EthereumAddresses, MerkleTreeHelper, ContractNames {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using Address for address;

    Deployer public deployer;
    BoringVault vault;
    ManagerWithMerkleVerification manager;

    // address euler = 0x53AfE3343f322c4189Ab69E0D048efd154259419; // Frontier strata
    address euler = 0x98281466aBcF48eAAD8c6E22dEdD18A3426A93b4; // Frontier mMEV
    // address euler = 0xe0a80d35bB6618CBA260120b279d357978c42BCE; // Euler Yield

    uint256 USDCSupplyAmount = 94247561158;

    function setUp() external {
        vm.createSelectFork("mainnet");
        setSourceChainName("mainnet");
        
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        vault = BoringVault(payable(deployer.getAddress(UsdaiVaultName)));
        manager = ManagerWithMerkleVerification(deployer.getAddress(UsdaiVaultManagerName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // address auth = vm.addr(privateKey);

        uint256 strategist = vm.envUint("MAINNET_STRATEGIST_EULER");
        
        vm.startBroadcast(privateKey);
        
        setAddress(true, mainnet, "boringVault", deployer.getAddress(UsdaiVaultName));
        setAddress(true, mainnet, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, mainnet, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiEulerDecoderAndSanitizerName));

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);
        
        _addEulerLeafs(leafs);

        // 2. Generate the merkle tree and get the root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        // Approve USDC
        // Deposit
        uint256 opsAmt = 2;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[0];
        manageLeafs[1] = leafs[1];
        // manageLeafs[1] = leafs[2];

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // 4. Prepare the action data
        address[] memory targets = new address[](opsAmt);
        targets[0] = getAddress(sourceChain, "USDC");
        targets[1] = euler;

        bytes[] memory targetData = new bytes[](opsAmt);

        targetData[0] = abi.encodeWithSignature("approve(address,uint256)", euler, type(uint256).max);
        targetData[1] = abi.encodeWithSignature("deposit(uint256,address)", USDCSupplyAmount, address(vault));
        // targetData[1] = abi.encodeWithSignature("withdraw(uint256,address,address)", USDCSupplyAmount, address(vault), address(vault));

        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiEulerDecoderAndSanitizerName);
        decodersAndSanitizers[1] = deployer.getAddress(UsdaiEulerDecoderAndSanitizerName);

        uint256[] memory values = new uint256[](opsAmt);
        values[0] = 0;
        values[1] = 0;

        // extra
        string memory filePath = "./leafs/EulerLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs(filePath, leafs, merkleRoot, manageTree);

        manager.setManageRoot(vm.addr(strategist), merkleRoot);

        vm.stopBroadcast();
        vm.startBroadcast(strategist);

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
