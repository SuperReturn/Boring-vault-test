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

interface IAlgebraPool {
  /// @notice The struct with important state values of pool
  /// @dev fits into one storage slot
  /// @param price The square root of the current price in Q64.96 format
  /// @param tick The current tick (price(tick) <= current price). May not always be equal to SqrtTickMath.getTickAtSqrtRatio(price) if the price is on a tick boundary
  /// @param lastFee The current (last known) fee in hundredths of a bip, i.e. 1e-6 (so 100 is 0.01%). May be obsolete if using dynamic fee plugin
  /// @param pluginConfig The current plugin config as bitmap. Each bit is responsible for enabling/disabling the hooks, the last bit turns on/off dynamic fees logic
  /// @param communityFee The community fee represented as a percent of all collected fee in thousandths, i.e. 1e-3 (so 100 is 10%)
  /// @param unlocked  Reentrancy lock flag, true if the pool currently is unlocked, otherwise - false
  struct GlobalState {
    uint160 price;
    int24 tick;
    uint16 lastFee;
    uint8 pluginConfig;
    uint16 communityFee;
    bool unlocked;
  }

  function globalState() external view returns (GlobalState memory);
}


contract RoosterOp is Script, PlumeAddresses, MerkleTreeHelper, ContractNames {
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

        uint256 strategist = vm.envUint("PLUME_STRATEGIST_ROOSTER");
        address strategistAddress = vm.addr(strategist);

        uint256 amountInput = 1 * 1e16;
        
        vm.startBroadcast(privateKey);
        
        setAddress(true, plume, "boringVault", previoussuperUSD);
        setAddress(true, plume, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, plume, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, plume, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiRoosterDecoderAndSanitizerName));

        // ERC20(tokenIn).approve(routerAddress, amountInput);
        // router.exactInputSingle(auth, pool, true, amountInput, amountOutMinimum);

        // 1. Create merkle tree leaves for allowed actions
        ManageLeaf[] memory leafs = new ManageLeaf[](128);
        
        // only support instant mint with USDC for now
        _addRoosterLeafs(leafs);

        // 2. Generate the merkle tree and get the root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        // Approve PUSD
        // Swap WPLUME for PUSD using Rooster exactInputSingle
        uint256 opsAmt = 2;
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        manageLeafs[0] = leafs[0];
        manageLeafs[1] = leafs[1];

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // 4. Prepare the action data
        address[] memory targets = new address[](opsAmt);
        targets[0] = WPLUME;
        targets[1] = roosterRouter;

        bytes[] memory targetData = new bytes[](opsAmt);

        // console.log(IAlgebraPool(roosterPool).globalState().price);

        targetData[0] = abi.encodeWithSignature("approve(address,uint256)", roosterRouter, type(uint256).max);
        targetData[1] = abi.encodeWithSignature("exactInputSingle((address,address,address,address,uint256,uint256,uint256,uint160))",
            getAddress(sourceChain, "WPLUME"),        // tokenIn
            getAddress(sourceChain, "PUSD"),         // tokenOut
            address(0),                              // deployer (default is 0) https://docs.algebra.finance/algebra-integral-documentation/algebra-integral-technical-reference/integration-process/technical-guides/swaps/single-swaps
            address(vault),    // recipient
            block.timestamp + 1 hours,              // deadline
            amountInput,                       // amountIn
            0,                                      // amountOutMinimum
            0);  
        address[] memory decodersAndSanitizers = new address[](opsAmt);  
        decodersAndSanitizers[0] = deployer.getAddress(UsdaiRoosterDecoderAndSanitizerName);
        decodersAndSanitizers[1] = deployer.getAddress(UsdaiRoosterDecoderAndSanitizerName);

        uint256[] memory values = new uint256[](opsAmt);

        // extra
        string memory filePath = "./leafs/RoosterLeafs.json";
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs(filePath, leafs, merkleRoot, manageTree);

        manager.setManageRoot(strategistAddress, merkleRoot);
        
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
