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
import {EthereumAddresses} from "test/resources/EthereumAddresses.sol";

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
contract RedeployTest is Test, ContractNames, EthereumAddresses{
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    BoringVault public boringVault;
    Deployer public deployer;
    ERC20 public baseAsset;

    address public user;
    address public admin;

// superUSD

    // address public constant superusd                    = address(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);

    // // SuperUSD Vault RolesAuthority v0.0
    // address public constant oldSuperusdRolesAuthority   = address(0x4FA024546d245f617dAAe796470721bC5D95E856);
    // // Deployer (Already deployed)
    // address public constant oldSuperusdDeployer         = address(0x1f082348a1f3C9eDfc31374913E0817055BA5F88);
    // // Accountant (fixed rate)
    // address public constant oldSuperusdAccountant       = address(0xF4a5555C5716bb61DC9C9124257e92683f98415B);
    // // BoringVault
    // address public constant oldSuperusdBoringVault      = address(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);
    // // Lens
    // address public constant oldSuperusdLens             = address(0x4a05CbB107E9964fa61D04cBF60c049F96eBBf56);
    // // ManagerWithMerkleVerification
    // address public constant oldSuperusdManager          = address(0x65EA811bA829dC166B7FCF25369bBF6BC33DA14d);
    // // TellerWithMultiAssetSupport
    // address public constant oldSuperusdTeller           = address(0xB08efd111caf0b45a038Eb07c370D068E55cc233);
    // // Solver
    // address public constant oldSuperusdSolver           = address(0x630f595A5aA09ff1b5c11FAd8Cf78a8109776ABc);
    // // Queue
    // address public constant oldSuperusdQueue            = address(0xDB6C5dC3e4802243f0c40e1883eA833Aa7a93588);
    // // SuperUSD Boring OnChain Queues Roles Authority V0.0
    // address public constant oldSuperusdQueueAuthority   = address(0xAE35B87121B2Ae2e8013DF2B6D35CEB76E110D33);
    // // LZ teller
    // address public constant oldSuperusdLZteller         = address(0x91c6Ea9Cdb919523Fd4B3027db90EeB0A9f9D66C);

    // // SuperUSD Vault RolesAuthority v1.0
    // address public constant newSuperusdRolesAuthority   = address(0x0953c2E6c82633CdA982E90A6287f66493c5cF0B);
    // // Deployer (Already deployed)
    // address public constant newSuperusdDeployer         = address(0xb654e5d7F1dbFCe3945551a72764e7b06DB25994);
    // // Accountant (fixed rate)
    // address public constant newSuperusdAccountant       = address(0x0427645BceA78A84A84eFBc26d51f87176581cd9);
    // // BoringVault
    // address public constant newSuperusdBoringVault      = address(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);
    // // BoringVault implementation
    // address public constant newSuperusdImpl             = address(0xe9460F59824a047cCCd794af254c8A467c6D05fa);
    // // Lens
    // address public constant newSuperusdLens             = address(0x1E0f8Cad571643e52C1FAcDBB2C005141c2f4b66);
    // // ManagerWithMerkleVerification
    // address public constant newSuperusdManager          = address(0xA78e8Ae84BEc9E66486fbC0e87E720Fd6342ef39);
    // // TellerWithMultiAssetSupport
    // address public constant newSuperusdTeller           = address(0xF62D61F304C9c65C96a94c2b0b93c8f93C96e91D);
    // // Solver
    // address public constant newSuperusdSolver           = address(0x1DB629316B3fB6B026f9ebD5c379a72235a4d5E9);
    // // Queue
    // address public constant newSuperusdQueue            = address(0xf3aA6324Aa5C9Ded16Eb7ED651152aC30588BAc1);
    // // SuperUSD Boring OnChain Queues Roles Authority V1.0
    // address public constant newSuperusdQueueAuthority   = address(0x58A6481706E4260ef50D362401C7F0357b13AB53);

// sSuperUSD

    address public constant superusd                    = address(0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd);
    
    // sSuperUSD Vault RolesAuthority v0.0
    address public constant oldSuperusdRolesAuthority   = address(0x31e311b75E753A961eB090dc29AfC1A23c57FF34);
    // Deployer (Already deployed)
    address public constant oldSuperusdDeployer         = address(0x1f082348a1f3C9eDfc31374913E0817055BA5F88);
    // Accountant
    address public constant oldSuperusdAccountant       = address(0xFec60259f315287252c495C5921A30209Dd1FA4e);
    // Lens
    address public constant oldSuperusdLens             = address(0xc43827a38AC3C495547bF466a90f4ec36f13AB66);
    // ManagerWithMerkleVerification
    address public constant oldSuperusdManager          = address(0x8E3c0Be2847999D63Ce8FeCd3368aaaC33572Ecd);
    // TellerWithMultiAssetSupport
    address public constant oldSuperusdTeller           = address(0xefCAEA1163cc9F328f303E3B49BCB9a54108938a);
    // Solver
    address public constant oldSuperusdSolver           = address(0xD755943d933526913F8dDa807f38650038856f1f);
    // Queue
    address public constant oldSuperusdQueue            = address(0x37a25d6B8118434b7513FEd84cbfde106D196107);
    // sSuperUSD Boring OnChain Queues Roles Authority v0.0
    address public constant oldSuperusdQueueAuthority   = address(0x0087C7545A9dc0761cC05BC835Ee6F7776F76924);

    // sSuperUSD Vault RolesAuthority v1.0
    address public constant newSuperusdRolesAuthority   = address(0xAa718B03071601b02bEe0Ab672Fb9F5997B250E7);
    // Deployer (Already deployed)
    address public constant newSuperusdDeployer         = address(0xb654e5d7F1dbFCe3945551a72764e7b06DB25994);
    // Accountant
    address public constant newSuperusdAccountant       = address(0x2B570475489e55b63bC5121EEe75f5D22C9C17C0);
    // Lens
    address public constant newSuperusdLens             = address(0xdcd147536a94260D27246dc1C82173a03a2f2582);
    // ManagerWithMerkleVerification
    address public constant newSuperusdManager          = address(0x95947f12D76Cb74Ca3F406dd0f7C1fb65e651Fd5);
    // TellerWithMultiAssetSupport
    address public constant newSuperusdTeller           = address(0xa8aA5c00d6c3f7A77FC5769770f6bC7b9244699b);
    // Solver
    address public constant newSuperusdSolver           = address(0x25019DAA4faa538996bA454D8c329f032011f104);
    // Queue
    address public constant newSuperusdQueue            = address(0xd484d2991D168b33cC61e25f80af0145883Bc465);
    // sSuperUSD Boring OnChain Queues Roles Authority v1.0
    address public constant newSuperusdQueueAuthority   = address(0xC5dD0cF14C3F0C5539ebEd0C067c3E3A9846a0b7);

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
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 23882936;
        // baseAsset = ERC20(USDC);
        baseAsset = ERC20(USDAI);

        _startFork(rpcKey, blockNumber);

        boringVault = BoringVault(payable(superusd));

        admin = dev0Address;
        user = vm.addr(100);

        vm.startPrank(admin);
        
        boringVault.setAuthority(Authority(newSuperusdRolesAuthority));
    }

    function testUpdateBoringVaultRoleAuthority() external {
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
        deal(address(baseAsset), params.boringVault, 10e6);
        ERC20(params.boringVault).safeApprove(address(params.queue), type(uint256).max);
        bytes32 requestId = IBoringOnChainQueue(params.queue).requestOnChainWithdraw(
            address(baseAsset),
            1 * 1e5,
            3,
            10 minutes
        );
        OnChainWithdraw memory onChainWithdraw = IBoringOnChainQueue(params.queue).getOnChainWithdraw(requestId);

        vm.warp(block.timestamp + 180 + 1);
        // 0x78b2b007: BoringOnChainQueue__DeadlinePassed()
        // 0x32924a49: BoringOnChainQueue__NotMatured()
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