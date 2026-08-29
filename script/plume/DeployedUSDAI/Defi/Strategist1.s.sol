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

contract Strategist1 is Script, PlumeAddresses, MerkleTreeHelper, ContractNames {
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
        // uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // address auth = vm.addr(privateKey);

        // uint256 strategist = vm.envUint("PLUME_STRATEGIST_MERKL");
        
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        
        setAddress(true, plume, "boringVault", previoussuperUSD);
        setAddress(true, plume, "managerAddress", deployer.getAddress(UsdaiVaultManagerName));
        setAddress(true, plume, "accountantAddress", deployer.getAddress(UsdaiVaultAccountantName));
        setAddress(true, plume, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMerklDecoderAndSanitizerName));

        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        address[] memory tokens = new address[](1);
        tokens[0] = WPLUME;

        _addMerklLeafs(leafs, merklDistributor, tokens);
        setAddress(true, plume, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiRoosterDecoderAndSanitizerName));
        _addRoosterLeafs(leafs);
        setAddress(true, plume, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName));
        _addMorphoLeafs(leafs, address(vault), morphoVaults);

        setAddress(true, plume, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiBaseDecoderAndSanitizerName));
        _addApprovalLeafs(leafs, PUSD, 0x28d2e2759dCB5CFda1c868Fee714B194c25a8dCB);
        _addTransferLeafs(leafs, PUSD, 0x62d9113BFf4414e7D3600FfB4d6255D29e5CFc42);

// Merkl operation
        // // // /*
        // // // claim params:
        // // // https://api.merkl.xyz/v4/users/0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB/rewards?chainId=98866
        // // // amount and proofs should be exactly same, otherwise it will revert
        // // // EvmError: NotActivated : should wait until endOfDisputePeriod, or required --evm-version cancun
        // // // */

        // setAddress(true, plume, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiMerklDecoderAndSanitizerName));
        // uint256[] memory amounts = new uint256[](1);
        // amounts[0] = 38199498687414147237216;
        // // 1. Create merkle tree leaves for allowed actions

        // // 2. Generate the merkle tree and get the root
        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        // uint256 opsAmt = 1;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[0];

        // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data
        // address[] memory targets = new address[](opsAmt);
        // targets[0] = merklDistributor;

        // bytes[] memory targetData = new bytes[](opsAmt);

        // address[] memory users = new address[](1);
        // users[0] = address(vault);

        // bytes32[][] memory proofs = new bytes32[][](1);
        // proofs[0] = new bytes32[](16);
        // proofs[0][0] = 0x2e83b358331686d2efe041c4e56b54cb244aff1d114a560ac36df280a1154638;
        // proofs[0][1] = 0x4a0dadca58c6fc0755d2853ba96485e938f82fbabc198b2593cd87f7e26f1ca3;
        // proofs[0][2] = 0x00df38554bf74d3a5d9ffeae3ed1d2a57653463e6a79be59766c87db3eab347f;
        // proofs[0][3] = 0xf63b0da016015d4e2166b7f0fae435aefda5118616e76a81cab77dd58fca8873;
        // proofs[0][4] = 0xe2e1affee77bb5246cd11b1b6554de3ceea4e5c7d9567db1e7d55d039c4a873b;
        // proofs[0][5] = 0xdfc3adbd9b5ac11f52c239b2879c8b2d4c49ff81ef7f21d37af173455b4b69dd;
        // proofs[0][6] = 0x741f6acc2d3aa54a63382a80cff375a770d68b1437d6241f36f7070beebad392;
        // proofs[0][7] = 0x4eefe8ddf44337b40de603f6dc6518dfc3cb97f45eec43663158855719f06b0a;
        // proofs[0][8] = 0x8efdf8c89cd73aa079a1ae61dd399e6d5f03e6f1237b509e52f0fd76fe8cdbf8;
        // proofs[0][9] = 0x36e2f12d87a1561113c130c3fd772e639adb99e235858bcc467d6b7fbe982370;
        // proofs[0][10] = 0xd605228001906cae7f53515e8746b1161f60f830bb311b76ceb7760acf18454a;
        // proofs[0][11] = 0x247b12cf605a07aa54cb7d7c86da7632ce56e37128eb804f411092e063531ee1;
        // proofs[0][12] = 0xa493f62349db45aba4c0f6d8bdf52a310f30559e072aabf1e2d718123f26a9e2;
        // proofs[0][13] = 0xc42910add21b103665c6001396c59f0cdd1ad7d6f4fa6994d52930f8a61d7660;
        // proofs[0][14] = 0xb8aaf8d4c7ac2cf259e2c4a60f1f1e127f5f8739373260e8d75bf565fba1be09;
        // proofs[0][15] = 0x7f848621a555a30401c6cd5ef00ce5eea91d0c828a04d008d0193fbc00069ae4;

        // targetData[0] = abi.encodeWithSignature(
        //     "claim(address[],address[],uint256[],bytes32[][])",
        //     users,
        //     tokens,
        //     amounts,
        //     proofs
        // );

        // address[] memory decodersAndSanitizers = new address[](opsAmt);  
        // decodersAndSanitizers[0] = deployer.getAddress(UsdaiMerklDecoderAndSanitizerName);

// Rooster operation
    //     uint256 amountInput = 1 * 1e15;

    //     setAddress(true, plume, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiRoosterDecoderAndSanitizerName));

    //     // 1. Create merkle tree leaves for allowed actions

    //     // 2. Generate the merkle tree and get the root
    //     bytes32[][] memory manageTree = _generateMerkleTree(leafs);

    //     // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
    //     // Approve PUSD
    //     // Swap WPLUME for PUSD using Rooster exactInputSingle
    //     uint256 opsAmt = 2;
    //     ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
    //     manageLeafs[0] = leafs[1];
    //     manageLeafs[1] = leafs[2];

    //     bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

    //     // 4. Prepare the action data
    //    address[] memory targets = new address[](opsAmt);
    //     targets[0] = WPLUME;
    //     targets[1] = roosterRouter;

    //     bytes[] memory targetData = new bytes[](opsAmt);

    //     // console.log(IAlgebraPool(roosterPool).globalState().price);

    //     targetData[0] = abi.encodeWithSignature("approve(address,uint256)", roosterRouter, type(uint256).max);
    //     targetData[1] = abi.encodeWithSignature("exactInputSingle((address,address,address,address,uint256,uint256,uint256,uint160))",
    //         getAddress(sourceChain, "WPLUME"),        // tokenIn
    //         getAddress(sourceChain, "PUSD"),         // tokenOut
    //         address(0),                              // deployer (default is 0) https://docs.algebra.finance/algebra-integral-documentation/algebra-integral-technical-reference/integration-process/technical-guides/swaps/single-swaps
    //         deployer.getAddress(UsdaiVaultName),    // recipient
    //         block.timestamp + 1 hours,              // deadline
    //         amountInput,                       // amountIn
    //         0,                                      // amountOutMinimum
    //         0);  
    //     address[] memory decodersAndSanitizers = new address[](opsAmt);  
    //     decodersAndSanitizers[0] = deployer.getAddress(UsdaiRoosterDecoderAndSanitizerName);
    //     decodersAndSanitizers[1] = deployer.getAddress(UsdaiRoosterDecoderAndSanitizerName);

// Morpho operation
        // // 1. Create merkle tree leaves for allowed actions

        // // 2. Generate the merkle tree and get the root
        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // // 3. Generate proofs for the actions you want to execute. Check USDAILeafs.json for the leafs operation order
        // // Approve PUSD
        // // Deposit PUSD
        // uint256 opsAmt = 2;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[6];
        // manageLeafs[1] = leafs[7];

        // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data
        // address[] memory targets = new address[](opsAmt);
        // targets[0] = getAddress(sourceChain, "PUSD");
        // targets[1] = 0x0b14D0bdAf647c541d3887c5b1A4bd64068fCDA7;

        // bytes[] memory targetData = new bytes[](opsAmt);

        // targetData[0] = abi.encodeWithSignature(
        //     "approve(address,uint256)",
        //     0x0b14D0bdAf647c541d3887c5b1A4bd64068fCDA7,
        //     type(uint256).max
        // );

        // targetData[1] = abi.encodeWithSignature(
        //     "deposit(uint256,address)",
        //     1e3,
        //     address(vault)
        // );

        // address[] memory decodersAndSanitizers = new address[](opsAmt);  
        // decodersAndSanitizers[0] = deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName);
        // decodersAndSanitizers[1] = deployer.getAddress(UsdaiMorphoDecoderAndSanitizerName);

// Base operation
        // setAddress(true, plume, "rawDataDecoderAndSanitizer", deployer.getAddress(UsdaiBaseDecoderAndSanitizerName));

        // // 2. Generate the merkle tree and get the root
        // bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // // 3. Generate proofs for the actions you want to execute
        // uint256 opsAmt = 2;
        // ManageLeaf[] memory manageLeafs = new ManageLeaf[](opsAmt);
        // manageLeafs[0] = leafs[9];
        // manageLeafs[1] = leafs[10];
        // // bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        // // 4. Prepare the action data - both operations target USDC token
        // address[] memory targets = new address[](opsAmt);
        // targets[0] = getAddress(sourceChain, "PUSD"); // approve
        // targets[1] = getAddress(sourceChain, "PUSD"); // transfer

        // bytes[] memory targetData = new bytes[](opsAmt);
        // targetData[0] = abi.encodeWithSignature("approve(address,uint256)", 0x28d2e2759dCB5CFda1c868Fee714B194c25a8dCB, type(uint256).max);
        // targetData[1] = abi.encodeWithSignature("transfer(address,uint256)", 0x62d9113BFf4414e7D3600FfB4d6255D29e5CFc42, 1e6);

        // address[] memory decodersAndSanitizers = new address[](opsAmt);  
        // decodersAndSanitizers[0] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);
        // decodersAndSanitizers[1] = deployer.getAddress(UsdaiBaseDecoderAndSanitizerName);





        // uint256[] memory values = new uint256[](opsAmt);
        // extra
        // string memory filePath = "./leafs/Strategist1Leafs.json";
        // bytes32 merkleRoot = manageTree[manageTree.length - 1][0];

        // _generateLeafs("./leafs/Strategist1Leafs.json", leafs, merkleRoot, manageTree);

        // // try to less the var number to prevent "Stack too deep" error
        // manager.setManageRoot(0x28d2e2759dCB5CFda1c868Fee714B194c25a8dCB, merkleRoot);

        // vm.stopBroadcast();
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
