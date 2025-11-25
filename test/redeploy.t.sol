// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {BoringVault} from "src/base/BoringVault.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {ILiquidityPool} from "src/interfaces/IStaking.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {AtomicSolverV4} from "src/atomic-queue/AtomicSolverV4.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {PlumeTestnetAddresses} from "test/resources/PlumeTestnetAddresses.sol";

// Add this struct before the interface IBoringOnChainQueue
struct OnChainWithdraw {
    uint96 nonce; 
    address user; 
    address assetOut; 
    uint128 amountOfShares;
    uint128 amountOfAssets;
    uint40 creationTime;
    uint24 secondsToMaturity;
    uint24 secondsToDeadline;
}

interface IBoringOnChainQueue {
    function requestOnChainWithdraw(
        address assetOut,
        uint128 amountOfShares,
        uint16 discount,
        uint24 secondsToDeadline
    ) external returns (bytes32 requestId);

    function getOnChainWithdraw(bytes32 requestId) external view returns (OnChainWithdraw memory);
}

interface IBoringSolver {
    function boringRedeemSelfSolve(OnChainWithdraw calldata request, address teller) external;
}

/*
 * This test primarily validates the redeployment process, which consists of two main parts:
 * 1. Testing the basic operation with the old and new Boring Vault role authority
 * 2. Upgrading the Boring Vault implementation
 *
 * The test ensures that:
 * a. Previous contracts become unavailable and new contracts become available after updating the Boring Vault role authority
 * b. New contracts continue to function properly after upgrading the Boring Vault implementation
 *
 * Note: All tests are based on actual deployed contracts (not mocks), so deployment scripts must be run first.
 * The test must be executed before setting the new role authority and performing upgrades.
 * Remember to update the RPC endpoint, block number, baseAsset, and contract addresses (inherit and hardcode) for each chain before running the test.
 */
contract RedeployTest is Test, ContractNames, PlumeTestnetAddresses{
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    BoringVault public boringVault;
    Deployer public deployer;
    ERC20 public baseAsset;

    address public user;
    address public admin;

    address public constant superusd                    = address(0x1C6DfA6C99d83aE8b872C32119575ce24407767C);
    
    address public constant oldSuperusdDeployer         = address(0x62165b41138c5841c0a54137E6470FBfEdd18a2e);
    address public constant oldSuperusdImpl             = address(0xD71A61A52d37DD5B740DA9e19aE5bA6eC1dDD13B);
    address public constant oldSuperusdRolesAuthority   = address(0x482ff8226a3f213d5fDC053E40ebD14AA213A43b);
    address public constant oldSuperusdAccountant       = address(0x05e118c77F6DFF4d26f9549A8A479C2049b81e50);
    address public constant oldSuperusdLens             = address(0xd8b0c6ca82d912a5BcaC8cA299D2c0bc6E2527c1);
    address public constant oldSuperusdManager          = address(0x26bd7bD8cD42e4B6a6B0805c0526833D2acd5Ec9);
    address public constant oldSuperusdTeller           = address(0x4252B2aA01C3948562546feFf1c1Ac809645CfD3);
    address public constant oldSuperusdSolver           = address(0x0ec3599353e592b4Ef69CC3A550d0923b077CAB5);
    address public constant oldSuperusdQueue            = address(0x2f16484e1760Fa5A3266Ce3A9831ed1B63835753);
    address public constant oldSuperusdQueueAuthority   = address(0xa566a8Ca5F93cdC1427b28420d4044A97BBd80Bd);

    address public constant newSuperusdDeployer         = address(0x6A0FE0ab71583F23Ea62904cd2C98DD18E0F9096);
    address public constant newSuperusdRolesAuthority   = address(0x9EcC12a700F4C971d69202b244fEbF30B947ecA5);
    address public constant newSuperusdAccountant       = address(0x67Bc6036c34d244F0C4dDEDf697FD550C96147Cc);
    address public constant newSuperusdLens             = address(0x7a935be5Aa25aE8A6961C500A14A078f7101A4E6);
    address public constant newSuperusdManager          = address(0x9B7063A1a07Fec4e776ea139000239f5fC7Eab80);
    address public constant newSuperusdTeller           = address(0x7CCd743d49f80dcA1c04667C2D7d0524f1244901);
    address public constant newSuperusdSolver           = address(0x753684080CdA249f2238016c8DffA30809bb8d4A);
    address public constant newSuperusdQueue            = address(0x044F86c77c872feA76C5b3D303541967ca976C4A);
    address public constant newSuperusdQueueAuthority   = address(0x2185Fdd5cE287e4B4F40Cd1deEf3719A4284042a);

    struct basicOperationParams {
        address teller;
        address manager;
        address accountant;
        address boringVault;
        address rolesAuthority;
        address queue;
        address solver;
    }

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "PLUME_RPC_URL";
        uint256 blockNumber = 22148000;
        baseAsset = ERC20(PUSD);

        _startFork(rpcKey, blockNumber);

        boringVault = BoringVault(payable(superusd));

        admin = dev0Address;
        user = vm.addr(100);

        vm.startPrank(admin);
    }

    function testUpdateBoringVaultRoleAuthority() external {
        // Set new role authority here
        boringVault.setAuthority(Authority(newSuperusdRolesAuthority));
        
        // After switching authority, basic operations work with new contracts
        vm.stopPrank();
        vm.startPrank(user);
        basicOperationAndViewWithNewDeployment(
            basicOperationParams(
                newSuperusdTeller,
                newSuperusdManager,
                newSuperusdAccountant,
                superusd,
                newSuperusdRolesAuthority,
                newSuperusdQueue,
                newSuperusdSolver
            )
        );

        // should fail since the authority in boring vault is updated
        basicOperationAndViewWithOldDeployment(
            basicOperationParams(
                oldSuperusdTeller,
                oldSuperusdManager,
                oldSuperusdAccountant,
                superusd,
                oldSuperusdRolesAuthority,
                oldSuperusdQueue,
                oldSuperusdSolver
            )
        );
        vm.stopPrank();
    }

    function testUpgradeImplementation() external {
        // deploy the new implementation
        address newImplementation = Deployer(newSuperusdDeployer).deployContract(
            "Implementation",
            type(BoringVault).creationCode,
            hex"",
            0
        );

        RolesAuthority(newSuperusdRolesAuthority).setRoleCapability(
            1,
            address(boringVault),
            bytes4(abi.encodeWithSignature("upgradeToAndCall(address,bytes)")),
            true
        );

        // upgrade the implementation
        boringVault.upgradeToAndCall(newImplementation, "");

        // Check that the implementation has been upgraded
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address currentImplementation = address(uint160(uint256(vm.load(address(boringVault), IMPLEMENTATION_SLOT))));
        assertEq(currentImplementation, newImplementation, "Implementation should be upgraded to newImplementation");

        vm.stopPrank();
        
        // the basic operation should work
        vm.startPrank(user);
        basicOperationAndViewWithNewDeployment(
            basicOperationParams(
                newSuperusdTeller,
                newSuperusdManager,
                newSuperusdAccountant,
                superusd,
                newSuperusdRolesAuthority,
                newSuperusdQueue,
                newSuperusdSolver
            )
        );
        vm.stopPrank();
    }

    function basicOperationAndViewWithNewDeployment(basicOperationParams memory params) internal{
        // view
        // after redeploy and upgrade, the old and new accountant should still work
        AccountantWithRateProviders accountant = AccountantWithRateProviders(params.accountant);
        assertNotEq(accountant.getRateSafe(), 0, "Exchange rate should not be 0");

        // 1. deposit
        TellerWithMultiAssetSupport teller = TellerWithMultiAssetSupport(params.teller);
        AtomicQueue atomicQueue = AtomicQueue(params.queue);
        AtomicSolverV4 atomicSolverV4 = AtomicSolverV4(params.solver);

        deal(address(baseAsset), user, 1e6);
        // assertEq(ERC20(params.boringVault).balanceOf(user), 0);
        baseAsset.safeApprove(params.boringVault, type(uint256).max);

        teller.deposit(baseAsset, 1e6, 0);
        assertGt(ERC20(params.boringVault).balanceOf(user), 0);

        // 2. send withdraw queue and solve
        ERC20(params.boringVault).safeApprove(address(atomicQueue), type(uint256).max);
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp * 2),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(ERC20(params.boringVault).balanceOf(user)),
            user: user,
            offer: address(params.boringVault),
            want: address(baseAsset)
        });

        atomicQueue.updateAtomicRequest(req);

        vm.warp(block.timestamp * 2 - 1);

        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req
        );
    }

    function basicOperationAndViewWithOldDeployment(basicOperationParams memory params) internal{
        // view
        // after redeploy and upgrade, the old and new accountant should still work
        AccountantWithRateProviders accountant = AccountantWithRateProviders(params.accountant);
        assertNotEq(accountant.getRateSafe(), 0, "Exchange rate should not be 0");

        // 1. deposit
        TellerWithMultiAssetSupport teller = TellerWithMultiAssetSupport(params.teller);

        deal(address(baseAsset), user, 1e6);
        baseAsset.safeApprove(params.boringVault, type(uint256).max);

        // After entering the vault, it will check the authorization using the authority set on the BoringVault,
        // so the previous teller will revert when executing.
        vm.expectRevert("UNAUTHORIZED");
        teller.deposit(baseAsset, 1e6, 0);

        // 2. send withdraw queue and solve
        deal(address(params.boringVault), user, 1e6);
        ERC20(params.boringVault).safeApprove(address(params.queue), type(uint256).max);
        bytes32 requestId = IBoringOnChainQueue(params.queue).requestOnChainWithdraw(
            address(baseAsset),
            1 * 1e5,
            3,
            10 minutes
        );
        OnChainWithdraw memory onChainWithdraw = IBoringOnChainQueue(params.queue).getOnChainWithdraw(requestId);

        vm.warp(block.timestamp + 10 minutes - 1);
        // After entering the vault, it will check the authorization using the authority set on the BoringVault,
        // so the previous teller will revert when executing.
        vm.expectRevert("UNAUTHORIZED");
        IBoringSolver(params.solver).boringRedeemSelfSolve(onChainWithdraw, params.teller);
    }

    // ========================================= HELPER FUNCTIONS =========================================
    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}