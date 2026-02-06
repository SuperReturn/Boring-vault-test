// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {BoringVault} from "src/base/BoringVault.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {AccountantWithRateProviders2, IRateProvider} from "src/base/Roles/AccountantWithRateProviders2.sol";
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
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {DelayedWithdraw} from "src/base/Roles/DelayedWithdraw.sol";
import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {Investor} from "src/atomic-queue/Investor.sol";
import {ISakePool} from "src/interfaces/external/sake/ISakePool.sol";

/// @title AtomicQueueTest_arb
/// @notice Test contract_arb for AtomicQueue functionality on an Arbitrum fork
contract AtomicQueueTest is Test, MerkleTreeHelper {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant MINTER_ROLE = 2;
    uint8 public constant BURNER_ROLE = 3;
    uint8 public constant MANAGER_INTERNAL_ROLE = 4;
    uint8 public constant SOLVER_ROLE = 12;
    uint8 public constant OWNER_ROLE = 8;
    uint8 public constant MULTISIG_ROLE = 9;
    uint8 public constant STRATEGIST_MULTISIG_ROLE = 10;
    uint8 public constant STRATEGIST_ROLE = 7;
    uint8 public constant UPDATE_EXCHANGE_RATE_ROLE = 11;
    
    uint8 public constant WITHDRAW_ROLE = 13;
    uint8 public constant INVESTOR_ROLE = 14;
    uint8 public constant QUEUE_INVESTOR_ROLE = 15;

    address public payoutAddress = vm.addr(7777777);
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ERC20 internal constant NATIVE_ERC20 = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    ERC20 public USDC = ERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    Deployer public deployer = Deployer(0xb654e5d7F1dbFCe3945551a72764e7b06DB25994);

    // existing superusd contracts
    ArcticArchitectureLens public superusdLens = ArcticArchitectureLens(0x1E0f8Cad571643e52C1FAcDBB2C005141c2f4b66);
    ManagerWithMerkleVerification public superusdManager = ManagerWithMerkleVerification(0xA78e8Ae84BEc9E66486fbC0e87E720Fd6342ef39);
    BoringVault public superusdBoringVault = BoringVault(payable(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB));
    RolesAuthority public superusdRolesAuthority = RolesAuthority(0x0953c2E6c82633CdA982E90A6287f66493c5cF0B);
    address public superusdRawDataDecoderAndSanitizer = address(0x55b2ED3B463aA505C1b0905C1Bf533Afd2d63186);
    TellerWithMultiAssetSupport public superusdTeller = TellerWithMultiAssetSupport(0xF62D61F304C9c65C96a94c2b0b93c8f93C96e91D);
    AccountantWithRateProviders2 public superusdAccountant = AccountantWithRateProviders2(0x0427645BceA78A84A84eFBc26d51f87176581cd9);
    DelayedWithdraw public superusdDelayedWithdrawer = DelayedWithdraw(0x0B4E3F4f1De589B78eD5D39f30FeBd8B898a5e7b);
    AtomicSolverV4 public superusdAtomicSolver = AtomicSolverV4(0x1DB629316B3fB6B026f9ebD5c379a72235a4d5E9);
    RolesAuthority public superusdQueueRolesAuthority = RolesAuthority(0x58A6481706E4260ef50D362401C7F0357b13AB53);

    // V2 deployed contracts
    AtomicQueue public atomicQueue;
    Investor public investor;

    // Aave addresses
    address public ausdcAddress = address(0x724dc807b04555b71ed48a6896b6F41593b8C637);
    address public aavePoolAddress = address(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    // Morpho addresses
    address public ydgusdcAddress = address(0x36b69949d60d06ECcC14DE0Ae63f4E00cc2cd8B9);

    address internal user = vm.addr(1);

    event AtomicRequestUpdated(
        bytes32 indexed requestId,
        address indexed user,
        address offerToken,
        address indexed wantToken,
        uint256 amount,
        uint256 deadline,
        uint256 timestamp
    );

    event AtomicRequestCancelled(
        bytes32 indexed requestId,
        address indexed user,
        address offerToken,
        address indexed wantToken,
        uint256 amount,
        uint256 deadline,
        uint256 timestamp
    );

    event AtomicRequestFulfilled(
        bytes32 indexed requestId,
        address indexed user,
        address offerToken,
        address indexed wantToken,
        uint256 offerAmountSpent,
        uint256 wantAmountReceived,
        uint256 timestamp
    );

    event MaturityTimeUpdated(uint256 oldMaturityTime, uint256 newMaturityTime);
    event InvestorUpdated(address newInvestor);
    event InstantWithdraw(
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 offerAmount,
        uint256 wantAmount,
        uint256 timestamp
    );

    event Transfer(address indexed from, address indexed to, uint256 value);

    uint256 constant DEFAULT_MATURITY_TIME = 1 hours;

    uint256 public userUSDCInitialBalance = 1_000_000_000e6;

    function _contains(bytes32[] memory arr, bytes32 target) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == target) return true;
        }
        return false;
    }

    function _containsRequest(AtomicRequest[] memory arr, AtomicRequest memory target) internal pure returns (bool) {
        bytes memory tgt = abi.encode(target);
        for (uint256 i = 0; i < arr.length; i++) {
            if (keccak256(abi.encode(arr[i])) == keccak256(tgt)) return true;
        }
        return false;
    }

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "ARBITRUM_RPC_URL";
        uint256 blockNumber = 429204300;
        _startFork(rpcKey, blockNumber);

        vm.startPrank(user);
        deal(address(USDC), user, 10_000e6);
        USDC.approve(aavePoolAddress, type(uint256).max);
        ISakePool(aavePoolAddress).supply(address(USDC), 1_000e6, address(superusdBoringVault), 0);
        if (ERC20(ausdcAddress).balanceOf(address(superusdBoringVault)) == 0) {
            revert("ausdc.balanceOf(superusdBoringVault) == 0");
        }
        vm.stopPrank();
        if (ERC20(ydgusdcAddress).balanceOf(address(superusdBoringVault)) == 0) {
            revert("ydgusdcAddress.balanceOf(superusdBoringVault) == 0");
        }
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

    /// @notice Deploy AtomicQueue and Investor via Deployer, reuse existing AtomicSolverV4, configure all auth
    function _deployAndConfigureV2()
        internal
        returns (AtomicQueue _atomicQueue, AtomicSolverV4 _atomicSolver, Investor _investor)
    {
        _atomicSolver = superusdAtomicSolver; // reuse existing solver

        // 1. Deploy AtomicQueue and Investor via Deployer
        address deployerOwner = deployer.owner();
        vm.startPrank(deployerOwner);

        _atomicQueue = AtomicQueue(
            deployer.deployContract(
                "SuperUSD Vault Queue V2.0",
                type(AtomicQueue).creationCode,
                abi.encode(address(this), superusdRolesAuthority, address(superusdAccountant), address(_atomicSolver)),
                0
            )
        );

        _investor = Investor(
            deployer.deployContract(
                "SuperUSD Vault Investor V1.0",
                type(Investor).creationCode,
                abi.encode(address(this), superusdRolesAuthority, address(superusdBoringVault)),
                0
            )
        );

        vm.stopPrank();

        // 3. Configure RolesAuthority — prank as the authority owner
        address authOwner = superusdRolesAuthority.owner();
        vm.startPrank(authOwner);

        bytes4 manageSelector = bytes4(keccak256("manage(address,bytes,uint256)"));

        // AtomicQueue capabilities
        superusdRolesAuthority.setRoleCapability(
            MULTISIG_ROLE, address(_atomicQueue), AtomicQueue.setMaturityTime.selector, true
        );
        superusdRolesAuthority.setRoleCapability(
            MULTISIG_ROLE, address(_atomicQueue), AtomicQueue.setDiscount.selector, true
        );
        superusdRolesAuthority.setRoleCapability(
            MULTISIG_ROLE, address(_atomicQueue), AtomicQueue.addToWhitelist.selector, true
        );
        superusdRolesAuthority.setRoleCapability(
            MULTISIG_ROLE, address(_atomicQueue), AtomicQueue.removeFromWhitelist.selector, true
        );
        superusdRolesAuthority.setRoleCapability(
            MULTISIG_ROLE, address(_atomicQueue), AtomicQueue.updateWhitelistMaturityDivisor.selector, true
        );
        superusdRolesAuthority.setRoleCapability(
            MULTISIG_ROLE, address(_atomicQueue), AtomicQueue.setSolver.selector, true
        );
        superusdRolesAuthority.setRoleCapability(
            MULTISIG_ROLE, address(_atomicQueue), AtomicQueue.setInvestor.selector, true
        );
        superusdRolesAuthority.setRoleCapability(
            MULTISIG_ROLE, address(_atomicQueue), AtomicQueue.cancelAtomicRequestByAdmin.selector, true
        );
        superusdRolesAuthority.setRoleCapability(
            WITHDRAW_ROLE, address(_atomicQueue), AtomicQueue.instantWithdraw.selector, true
        );

        // AtomicSolverV4 capabilities are on the queue's own RolesAuthority (set below)

        // Investor capabilities
        superusdRolesAuthority.setRoleCapability(
            INVESTOR_ROLE, address(superusdBoringVault), manageSelector, true
        );
        superusdRolesAuthority.setRoleCapability(
            QUEUE_INVESTOR_ROLE, address(_investor), Investor.autoWithdrawal.selector, true
        );

        // Public capabilities
        superusdRolesAuthority.setPublicCapability(
            address(_atomicQueue), AtomicQueue.updateAtomicRequest.selector, true
        );
        superusdRolesAuthority.setPublicCapability(
            address(_atomicQueue), AtomicQueue.cancelAtomicRequest.selector, true
        );
        superusdRolesAuthority.setPublicCapability(
            address(_atomicSolver), AtomicSolverV4.redeemSolve.selector, true
        );

        // User roles
        superusdRolesAuthority.setUserRole(address(_atomicSolver), SOLVER_ROLE, true);
        superusdRolesAuthority.setUserRole(address(_atomicQueue), SOLVER_ROLE, true);
        superusdRolesAuthority.setUserRole(address(_investor), INVESTOR_ROLE, true);
        superusdRolesAuthority.setUserRole(address(_atomicQueue), QUEUE_INVESTOR_ROLE, true);
        superusdRolesAuthority.setUserRole(user, WITHDRAW_ROLE, true);
        superusdRolesAuthority.setUserRole(user, MULTISIG_ROLE, true);

        vm.stopPrank();

        // 4. Grant new queue ONLY_QUEUE_ROLE (32) on the solver's own RolesAuthority
        //    so the new queue can call finishSolve and approveOfferForQueue on the existing solver
        address queueAuthOwner = superusdQueueRolesAuthority.owner();
        vm.startPrank(queueAuthOwner);
        superusdQueueRolesAuthority.setUserRole(address(_atomicQueue), 32, true); // ONLY_QUEUE_ROLE
        vm.stopPrank();

        // 6. Configure Investor vaults
        Investor.VaultInfo[] memory vaults = new Investor.VaultInfo[](2);
        vaults[0] = Investor.VaultInfo({vaultType: Investor.VaultType.AaveV3, vault: ausdcAddress});
        vaults[1] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: ydgusdcAddress});
        _investor.setVaults(vaults);

        // 7. Link investor to queue and set discount to 0
        _atomicQueue.setInvestor(address(_investor));
        _atomicQueue.setDiscount(0);

        // Store to contract state
        atomicQueue = _atomicQueue;
        investor = _investor;
    }

    /// @notice Deal vault shares to user and approve the queue to spend them
    function _giveUserShares(uint256 amount) internal {
        deal(address(superusdBoringVault), user, amount);
        vm.prank(user);
        ERC20(address(superusdBoringVault)).approve(address(atomicQueue), type(uint256).max);
    }

    // ========================================= GROUP 1: DEPLOYMENT & STATE VERIFICATION =========================================

    function testUpgradeDeployment() external {
        (AtomicQueue q, AtomicSolverV4 s, Investor inv) = _deployAndConfigureV2();

        // Non-zero addresses
        assertTrue(address(q) != address(0), "queue zero");
        assertTrue(address(s) != address(0), "solver zero");
        assertTrue(address(inv) != address(0), "investor zero");

        // Solver is the existing one
        assertEq(address(s), address(superusdAtomicSolver), "solver is existing");

        // Constructor immutables
        assertEq(inv.boringVault(), address(superusdBoringVault), "investor.boringVault");
        assertEq(address(q.accountant()), address(superusdAccountant), "queue.accountant");
        assertEq(address(q.solver()), address(s), "queue.solver");
        assertEq(address(q.investor()), address(inv), "queue.investor");

        // Investor has 2 vaults configured
        assertEq(inv.numVaults(), 2, "numVaults");
        (address v0, uint8 t0) = inv.getVaultInfo(0);
        assertEq(v0, ausdcAddress, "vault0 address");
        assertEq(t0, uint8(Investor.VaultType.AaveV3), "vault0 type");
        (address v1, uint8 t1) = inv.getVaultInfo(1);
        assertEq(v1, ydgusdcAddress, "vault1 address");
        assertEq(t1, uint8(Investor.VaultType.ERC4626), "vault1 type");

        // Discount is 0
        assertEq(q.discount(), 0, "discount");
    }

    // ========================================= GROUP 2: AUTH VERIFICATION =========================================

    function testInstantWithdrawRequiresAuth() external {
        _deployAndConfigureV2();
        address randomUser = vm.addr(999);
        _giveUserShares(100e6);

        vm.prank(randomUser);
        vm.expectRevert("UNAUTHORIZED");
        atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, 100e6, 0, superusdTeller
        );
    }

    function testSetInvestorRequiresAuth() external {
        _deployAndConfigureV2();
        address randomUser = vm.addr(999);

        vm.prank(randomUser);
        vm.expectRevert("UNAUTHORIZED");
        atomicQueue.setInvestor(address(0));
    }

    function testInvestorAutoWithdrawalRequiresAuth() external {
        _deployAndConfigureV2();
        address randomUser = vm.addr(999);

        vm.prank(randomUser);
        vm.expectRevert("UNAUTHORIZED");
        investor.autoWithdrawal(0, 100e6, USDC);
    }

    function testSetVaultsRequiresAuth() external {
        _deployAndConfigureV2();
        address randomUser = vm.addr(999);

        Investor.VaultInfo[] memory vaults = new Investor.VaultInfo[](0);
        vm.prank(randomUser);
        vm.expectRevert("UNAUTHORIZED");
        investor.setVaults(vaults);
    }

    // ========================================= GROUP 3: INSTANT WITHDRAW FROM PRODUCTION VAULTS =========================================

    function testInstantWithdrawNoInvestorNeeded() external {
        _deployAndConfigureV2();
        uint256 withdrawShares = 100e6;
        _giveUserShares(withdrawShares);

        // Ensure vault has enough USDC
        uint256 vaultUSDCBefore = USDC.balanceOf(address(superusdBoringVault));
        uint256 rate = superusdAccountant.getRateInQuoteSafe(USDC);
        uint256 ONE_SHARE = 10 ** ERC20(address(superusdBoringVault)).decimals();
        uint256 expectedAssetsOut = withdrawShares * rate / ONE_SHARE;
        assertTrue(vaultUSDCBefore >= expectedAssetsOut, "vault needs enough USDC");

        uint256 ausdcBefore = ERC20(ausdcAddress).balanceOf(address(superusdBoringVault));
        uint256 ydgusdcBefore = ERC20(ydgusdcAddress).balanceOf(address(superusdBoringVault));
        uint256 userSharesBefore = ERC20(address(superusdBoringVault)).balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);

        // Expect Transfer events: shares user→queue, share burn, USDC vault→queue, USDC queue→user
        vm.expectEmit(true, true, true, true, address(superusdBoringVault));
        emit Transfer(user, address(atomicQueue), withdrawShares);
        vm.expectEmit(true, true, true, true, address(superusdBoringVault));
        emit Transfer(address(atomicQueue), address(0), withdrawShares);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(superusdBoringVault), address(atomicQueue), expectedAssetsOut);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(atomicQueue), user, expectedAssetsOut);

        // Expect InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(
            user, address(superusdBoringVault), address(USDC), withdrawShares, expectedAssetsOut, block.timestamp
        );

        vm.prank(user);
        uint256 assetsOut = atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, withdrawShares, 0, superusdTeller
        );

        // User receives exact expected USDC
        assertEq(assetsOut, expectedAssetsOut, "assetsOut matches expected");
        assertEq(USDC.balanceOf(user), userUSDCBefore + expectedAssetsOut, "user received USDC");

        // Vault USDC decreased by assetsOut
        assertEq(
            USDC.balanceOf(address(superusdBoringVault)),
            vaultUSDCBefore - expectedAssetsOut,
            "vault USDC decreased"
        );

        // aUSDC and ydgusdc unchanged
        assertEq(ERC20(ausdcAddress).balanceOf(address(superusdBoringVault)), ausdcBefore, "aUSDC unchanged");
        assertEq(ERC20(ydgusdcAddress).balanceOf(address(superusdBoringVault)), ydgusdcBefore, "ydgusdc unchanged");

        // User shares decreased
        assertEq(
            ERC20(address(superusdBoringVault)).balanceOf(user),
            userSharesBefore - withdrawShares,
            "user shares decreased"
        );
    }

    function testInstantWithdrawFromAave() external {
        _deployAndConfigureV2();
        uint256 withdrawShares = 100e6;
        _giveUserShares(withdrawShares);

        // Drain vault USDC so investor must redeem from Aave
        deal(address(USDC), address(superusdBoringVault), 0);

        uint256 rate = superusdAccountant.getRateInQuoteSafe(USDC);
        uint256 ONE_SHARE = 10 ** ERC20(address(superusdBoringVault)).decimals();
        uint256 expectedAssetsOut = withdrawShares * rate / ONE_SHARE;

        uint256 ausdcBefore = ERC20(ausdcAddress).balanceOf(address(superusdBoringVault));
        assertTrue(ausdcBefore > 0, "vault has aUSDC");
        uint256 userSharesBefore = ERC20(address(superusdBoringVault)).balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);

        // Expect share Transfer and InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(superusdBoringVault));
        emit Transfer(user, address(atomicQueue), withdrawShares);
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(
            user, address(superusdBoringVault), address(USDC), withdrawShares, expectedAssetsOut, block.timestamp
        );

        vm.prank(user);
        uint256 assetsOut = atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, withdrawShares, 0, superusdTeller
        );

        // User receives exact expected USDC
        assertEq(assetsOut, expectedAssetsOut, "assetsOut matches expected");
        assertEq(USDC.balanceOf(user), userUSDCBefore + expectedAssetsOut, "user received USDC");

        // User shares decreased
        assertEq(
            ERC20(address(superusdBoringVault)).balanceOf(user),
            userSharesBefore - withdrawShares,
            "user shares decreased"
        );

        // aUSDC balance decreased (Aave withdrawal happened)
        uint256 ausdcAfter = ERC20(ausdcAddress).balanceOf(address(superusdBoringVault));
        assertTrue(ausdcAfter < ausdcBefore, "aUSDC decreased");
    }

    function testInstantWithdrawFromMorpho() external {
        _deployAndConfigureV2();
        uint256 withdrawShares = 100e6;
        _giveUserShares(withdrawShares);

        // Drain vault USDC so investor is triggered
        deal(address(USDC), address(superusdBoringVault), 0);

        // Mock aUSDC balance to 0 so investor skips Aave and goes to Morpho
        // (can't use deal() on Aave aTokens — they use scaled balances internally)
        vm.mockCall(
            ausdcAddress,
            abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)")), address(superusdBoringVault)),
            abi.encode(uint256(0))
        );

        uint256 rate = superusdAccountant.getRateInQuoteSafe(USDC);
        uint256 ONE_SHARE = 10 ** ERC20(address(superusdBoringVault)).decimals();
        uint256 expectedAssetsOut = withdrawShares * rate / ONE_SHARE;

        uint256 ydgusdcBefore = ERC20(ydgusdcAddress).balanceOf(address(superusdBoringVault));
        assertTrue(ydgusdcBefore > 0, "vault has ydgusdc");
        uint256 userSharesBefore = ERC20(address(superusdBoringVault)).balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);

        // Expect share Transfer and InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(superusdBoringVault));
        emit Transfer(user, address(atomicQueue), withdrawShares);
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(
            user, address(superusdBoringVault), address(USDC), withdrawShares, expectedAssetsOut, block.timestamp
        );

        vm.prank(user);
        uint256 assetsOut = atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, withdrawShares, 0, superusdTeller
        );

        // Clear the mock
        vm.clearMockedCalls();

        // User receives exact expected USDC
        assertEq(assetsOut, expectedAssetsOut, "assetsOut matches expected");
        assertEq(USDC.balanceOf(user), userUSDCBefore + expectedAssetsOut, "user received USDC");

        // User shares decreased
        assertEq(
            ERC20(address(superusdBoringVault)).balanceOf(user),
            userSharesBefore - withdrawShares,
            "user shares decreased"
        );

        // ydgusdc balance decreased (Morpho withdrawal happened)
        uint256 ydgusdcAfter = ERC20(ydgusdcAddress).balanceOf(address(superusdBoringVault));
        assertTrue(ydgusdcAfter < ydgusdcBefore, "ydgusdc decreased");
    }

    function testInstantWithdrawFromBothVaults() external {
        _deployAndConfigureV2();

        // We need aUSDC to be insufficient alone. Calculate how much USDC we need.
        uint256 rate = superusdAccountant.getRateInQuoteSafe(USDC);
        uint256 ONE_SHARE = 10 ** ERC20(address(superusdBoringVault)).decimals();
        uint256 ausdcBalance = ERC20(ausdcAddress).balanceOf(address(superusdBoringVault));

        // Pick shares that require more USDC than aUSDC can provide
        // assetsNeeded = withdrawShares * rate / ONE_SHARE
        // We want assetsNeeded > ausdcBalance so both vaults get hit
        uint256 withdrawShares = (ausdcBalance * ONE_SHARE / rate) * 2; // 2x what aUSDC can cover
        _giveUserShares(withdrawShares);

        // Drain vault USDC
        deal(address(USDC), address(superusdBoringVault), 0);

        uint256 expectedAssetsOut = withdrawShares * rate / ONE_SHARE;

        uint256 ausdcBefore = ERC20(ausdcAddress).balanceOf(address(superusdBoringVault));
        uint256 ydgusdcBefore = ERC20(ydgusdcAddress).balanceOf(address(superusdBoringVault));
        uint256 userSharesBefore = ERC20(address(superusdBoringVault)).balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);

        // Expect share Transfer and InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(superusdBoringVault));
        emit Transfer(user, address(atomicQueue), withdrawShares);
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(
            user, address(superusdBoringVault), address(USDC), withdrawShares, expectedAssetsOut, block.timestamp
        );

        vm.prank(user);
        uint256 assetsOut = atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, withdrawShares, 0, superusdTeller
        );

        // User receives exact expected USDC
        assertEq(assetsOut, expectedAssetsOut, "assetsOut matches expected");
        assertEq(USDC.balanceOf(user), userUSDCBefore + expectedAssetsOut, "user received USDC");

        // User shares decreased
        assertEq(
            ERC20(address(superusdBoringVault)).balanceOf(user),
            userSharesBefore - withdrawShares,
            "user shares decreased"
        );

        // Both vault token balances decreased
        assertTrue(
            ERC20(ausdcAddress).balanceOf(address(superusdBoringVault)) < ausdcBefore, "aUSDC decreased"
        );
        assertTrue(
            ERC20(ydgusdcAddress).balanceOf(address(superusdBoringVault)) < ydgusdcBefore, "ydgusdc decreased"
        );
    }

    // ========================================= GROUP 4: ERROR CASES =========================================

    function testInstantWithdrawInsufficientLiquidity() external {
        _deployAndConfigureV2();
        // Request a very large withdrawal that exceeds all vault liquidity
        uint256 hugeShares = 1_000_000_000e6;
        _giveUserShares(hugeShares);

        // Drain USDC from vault
        deal(address(USDC), address(superusdBoringVault), 0);

        vm.prank(user);
        vm.expectRevert(); // AtomicQueue__InsufficientVaultLiquidity
        atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, hugeShares, 0, superusdTeller
        );
    }

    function testInstantWithdrawZeroAmount() external {
        _deployAndConfigureV2();
        _giveUserShares(100e6);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__ZeroOfferAmount.selector, user));
        atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, 0, 0, superusdTeller
        );
    }

    function testInstantWithdrawOfferMismatch() external {
        _deployAndConfigureV2();

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AtomicQueue.AtomicQueue__RequestAccountantOfferMismatch.selector,
                address(USDC),
                address(superusdBoringVault)
            )
        );
        atomicQueue.instantWithdraw(USDC, USDC, 100e6, 0, superusdTeller);
    }

    // ========================================= GROUP 5: QUEUE SOLVE FLOW =========================================

    function testSolveRequestAfterUpgrade() external {
        _deployAndConfigureV2();
        uint256 offerAmount = 100e6;
        _giveUserShares(offerAmount);

        // Submit request
        vm.prank(user);
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 2 days),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(offerAmount),
            user: user,
            offer: address(superusdBoringVault),
            want: address(USDC)
        });
        bytes32 requestId = atomicQueue.updateAtomicRequest(req);

        // Verify request is in queue
        bytes32[] memory ids = atomicQueue.getExistingWithdrawRequestIds();
        assertTrue(_contains(ids, requestId), "request in queue");

        // Warp past maturity
        vm.warp(block.timestamp + atomicQueue.maturityTime() + 1);

        // Solver calls redeemSolve — NOTE: requires correct solver address
        uint256 rate = superusdAccountant.getRateInQuoteSafe(USDC);
        uint256 ONE_SHARE = 10 ** ERC20(address(superusdBoringVault)).decimals();
        uint256 expectedUSDCOut = offerAmount * rate / ONE_SHARE;

        uint256 userSharesBefore = ERC20(address(superusdBoringVault)).balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);
        uint256 vaultUSDCBefore = USDC.balanceOf(address(superusdBoringVault));
        AtomicRequest memory storedReq = atomicQueue.getAtomicRequestById(requestId);

        superusdAtomicSolver.redeemSolve(atomicQueue, 0, type(uint256).max, superusdTeller, storedReq);

        // User received exact USDC amount
        assertEq(USDC.balanceOf(user), userUSDCBefore + expectedUSDCOut, "user received exact USDC");
        assertEq(USDC.balanceOf(user) - userUSDCBefore, expectedUSDCOut, "USDC diff matches expected");

        // Vault USDC decreased
        assertEq(
            USDC.balanceOf(address(superusdBoringVault)),
            vaultUSDCBefore - expectedUSDCOut,
            "vault USDC decreased"
        );

        // User shares unchanged (shares were already with solver from updateAtomicRequest)
        assertEq(ERC20(address(superusdBoringVault)).balanceOf(user), userSharesBefore, "user shares unchanged");

        // Request removed from queue
        bytes32[] memory remainingIds = atomicQueue.getExistingWithdrawRequestIds();
        assertFalse(_contains(remainingIds, requestId), "request removed");
    }

    // ========================================= GROUP 6: DISCOUNT + INVESTOR =========================================

    function testInstantWithdrawWithDiscount() external {
        _deployAndConfigureV2();

        // Set discount to 500 ppm (0.05%)
        vm.prank(user);
        atomicQueue.setDiscount(500);

        uint256 withdrawShares = 100e6;
        _giveUserShares(withdrawShares);

        // Vault has enough USDC (no investor needed)
        uint256 rate = superusdAccountant.getRateInQuoteSafe(USDC);
        uint256 ONE_SHARE = 10 ** ERC20(address(superusdBoringVault)).decimals();
        uint256 fullAssetsOut = withdrawShares * rate / ONE_SHARE;
        uint256 discountedAmount = fullAssetsOut * (1e6 - 500) / 1e6;

        uint256 excess = fullAssetsOut - discountedAmount;

        uint256 vaultUSDCBefore = USDC.balanceOf(address(superusdBoringVault));
        assertTrue(vaultUSDCBefore >= fullAssetsOut, "vault has enough USDC");
        uint256 userSharesBefore = ERC20(address(superusdBoringVault)).balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);

        // Expect Transfer events: shares user→queue, share burn, USDC vault→queue(full), excess→vault, discounted→user
        vm.expectEmit(true, true, true, true, address(superusdBoringVault));
        emit Transfer(user, address(atomicQueue), withdrawShares);
        vm.expectEmit(true, true, true, true, address(superusdBoringVault));
        emit Transfer(address(atomicQueue), address(0), withdrawShares);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(superusdBoringVault), address(atomicQueue), fullAssetsOut);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(atomicQueue), address(superusdBoringVault), excess);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(atomicQueue), user, discountedAmount);

        // Expect InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(
            user, address(superusdBoringVault), address(USDC), withdrawShares, discountedAmount, block.timestamp
        );

        vm.prank(user);
        uint256 assetsOut = atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, withdrawShares, 0, superusdTeller
        );

        // User receives discounted amount
        assertEq(assetsOut, discountedAmount, "user gets discounted amount");
        assertEq(USDC.balanceOf(user), userUSDCBefore + discountedAmount, "user USDC balance");

        // User shares decreased
        assertEq(
            ERC20(address(superusdBoringVault)).balanceOf(user),
            userSharesBefore - withdrawShares,
            "user shares decreased"
        );

        // Excess returned to vault (vault lost fullAssetsOut via exit, got back excess)
        uint256 vaultUSDCAfter = USDC.balanceOf(address(superusdBoringVault));
        // vault balance = before - fullAssetsOut (exit) + excess (returned)
        assertEq(vaultUSDCAfter, vaultUSDCBefore - fullAssetsOut + excess, "excess returned to vault");
    }

    function testInstantWithdrawWithDiscountAndInvestor() external {
        _deployAndConfigureV2();

        // Set discount to 500 ppm (0.05%)
        vm.prank(user);
        atomicQueue.setDiscount(500);

        uint256 withdrawShares = 100e6;
        _giveUserShares(withdrawShares);

        uint256 rate = superusdAccountant.getRateInQuoteSafe(USDC);
        uint256 ONE_SHARE = 10 ** ERC20(address(superusdBoringVault)).decimals();
        uint256 fullAssetsOut = withdrawShares * rate / ONE_SHARE;
        uint256 discountedAmount = fullAssetsOut * (1e6 - 500) / 1e6;

        // The liquidity check uses totalRequired = discountedAmount + pendingWithdrawAssets,
        // but bulkWithdraw needs fullAssetsOut of USDC in the vault.
        // To make investor work with discount, we need pending withdrawals to inflate totalRequired >= fullAssetsOut.
        // Create a pending queue request to inflate totalRequired.
        address pendingUser = vm.addr(42);
        uint256 pendingShares = fullAssetsOut; // enough to inflate totalRequired above fullAssetsOut
        deal(address(superusdBoringVault), pendingUser, pendingShares);
        vm.startPrank(pendingUser);
        ERC20(address(superusdBoringVault)).approve(address(atomicQueue), type(uint256).max);
        AtomicRequest memory pendingReq = AtomicRequest({
            deadline: uint64(block.timestamp + 2 days),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(pendingShares),
            user: pendingUser,
            offer: address(superusdBoringVault),
            want: address(USDC)
        });
        atomicQueue.updateAtomicRequest(pendingReq);
        vm.stopPrank();

        // Drain vault USDC so investor is needed
        deal(address(USDC), address(superusdBoringVault), 0);
        uint256 userSharesBefore = ERC20(address(superusdBoringVault)).balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);

        // Expect share Transfer and InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(superusdBoringVault));
        emit Transfer(user, address(atomicQueue), withdrawShares);
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(
            user, address(superusdBoringVault), address(USDC), withdrawShares, discountedAmount, block.timestamp
        );

        vm.prank(user);
        uint256 assetsOut = atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, withdrawShares, 0, superusdTeller
        );

        // User receives discounted amount
        assertEq(assetsOut, discountedAmount, "user gets discounted amount");
        assertEq(USDC.balanceOf(user), userUSDCBefore + discountedAmount, "user USDC balance");

        // User shares decreased
        assertEq(
            ERC20(address(superusdBoringVault)).balanceOf(user),
            userSharesBefore - withdrawShares,
            "user shares decreased"
        );
    }

    // ========= GROUP 7: GAP TESTS — ERROR PATHS, CANCEL FLOW, EVENTS =========

    function testInstantWithdrawMinimumNotMet() external {
        _deployAndConfigureV2();

        // Set discount to 500 ppm (0.05%)
        vm.prank(user);
        atomicQueue.setDiscount(500);

        uint256 withdrawShares = 100e6;
        _giveUserShares(withdrawShares);

        // Compute the full (undiscounted) assetsOut
        uint256 rate = superusdAccountant.getRateInQuoteSafe(USDC);
        uint256 ONE_SHARE = 10 ** ERC20(address(superusdBoringVault)).decimals();
        uint256 fullAssetsOut = withdrawShares * rate / ONE_SHARE;

        // Set minimumAssetsOut to the full undiscounted amount.
        // With discount active, assetOutWithDiscount < fullAssetsOut, so the check fails.
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__MinimumAssetsNotMet.selector));
        atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, withdrawShares, fullAssetsOut, superusdTeller
        );
    }

    function testInstantWithdrawNoInvestorRevert() external {
        _deployAndConfigureV2();

        // Remove investor
        vm.prank(user);
        atomicQueue.setInvestor(address(0));

        // Drain vault USDC so liquidity check fails
        deal(address(USDC), address(superusdBoringVault), 0);

        uint256 withdrawShares = 100e6;
        _giveUserShares(withdrawShares);

        // Compute expected revert parameters (discount=0, no pending requests)
        uint256 rate = superusdAccountant.getRateInQuoteSafe(USDC);
        uint256 ONE_SHARE = 10 ** ERC20(address(superusdBoringVault)).decimals();
        uint256 expectedAssetsOut = withdrawShares * rate / ONE_SHARE;

        // totalRequired = expectedAssetsOut + 0 (no pending), vaultBalance = 0
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AtomicQueue.AtomicQueue__InsufficientVaultLiquidity.selector, expectedAssetsOut, 0
            )
        );
        atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, withdrawShares, 0, superusdTeller
        );
    }

    function testCancelRequestAfterUpgrade() external {
        _deployAndConfigureV2();
        uint256 offerAmount = 100e6;
        _giveUserShares(offerAmount);

        // Submit request — shares move from user to solver
        vm.prank(user);
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 2 days),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(offerAmount),
            user: user,
            offer: address(superusdBoringVault),
            want: address(USDC)
        });
        bytes32 requestId = atomicQueue.updateAtomicRequest(req);

        // Verify request is in queue and shares moved to solver
        bytes32[] memory ids = atomicQueue.getExistingWithdrawRequestIds();
        assertTrue(_contains(ids, requestId), "request in queue");
        assertEq(ERC20(address(superusdBoringVault)).balanceOf(user), 0, "user shares transferred");

        uint256 solverSharesBefore = ERC20(address(superusdBoringVault)).balanceOf(address(superusdAtomicSolver));

        // Retrieve stored request (creationTime is normalized to block.timestamp)
        AtomicRequest memory storedReq = atomicQueue.getAtomicRequestById(requestId);

        // Cancel — expect Transfer (shares solver→user) and AtomicRequestCancelled event
        vm.expectEmit(true, true, true, true, address(superusdBoringVault));
        emit Transfer(address(superusdAtomicSolver), user, offerAmount);
        vm.expectEmit(true, true, true, true);
        emit AtomicRequestCancelled(
            requestId, user, address(superusdBoringVault), address(USDC), offerAmount, storedReq.deadline, block.timestamp
        );

        vm.prank(user);
        atomicQueue.cancelAtomicRequest(storedReq);

        // Verify: user shares restored, solver shares decreased, request removed
        assertEq(ERC20(address(superusdBoringVault)).balanceOf(user), offerAmount, "user shares restored");
        assertEq(
            ERC20(address(superusdBoringVault)).balanceOf(address(superusdAtomicSolver)),
            solverSharesBefore - offerAmount,
            "solver shares decreased"
        );

        bytes32[] memory remainingIds = atomicQueue.getExistingWithdrawRequestIds();
        assertFalse(_contains(remainingIds, requestId), "request removed");
        assertEq(
            atomicQueue.withdrawInProgressAmount(address(superusdBoringVault), address(USDC)),
            0,
            "withdrawInProgress decremented"
        );
    }

    function testBoringVaultTellerMismatch() external {
        _deployAndConfigureV2();
        uint256 withdrawShares = 100e6;
        _giveUserShares(withdrawShares);

        // Create a fake teller that returns a different vault
        address fakeTeller = vm.addr(12345);
        vm.mockCall(
            fakeTeller,
            abi.encodeWithSelector(bytes4(keccak256("vault()"))),
            abi.encode(address(0xdead))
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AtomicQueue.AtomicQueue__BoringVaultTellerMismatch.selector,
                address(superusdBoringVault),
                fakeTeller
            )
        );
        atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, withdrawShares, 0, TellerWithMultiAssetSupport(fakeTeller)
        );

        vm.clearMockedCalls();
    }

    function testInstantWithdrawEmitsEvent() external {
        _deployAndConfigureV2();
        uint256 withdrawShares = 100e6;
        _giveUserShares(withdrawShares);

        // Pre-compute expected assetsOut (discount=0, so assetOutWithDiscount == assetsOut)
        uint256 rate = superusdAccountant.getRateInQuoteSafe(USDC);
        uint256 ONE_SHARE = 10 ** ERC20(address(superusdBoringVault)).decimals();
        uint256 expectedAssetsOut = withdrawShares * rate / ONE_SHARE;

        uint256 userSharesBefore = ERC20(address(superusdBoringVault)).balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);
        uint256 vaultUSDCBefore = USDC.balanceOf(address(superusdBoringVault));

        // Expect Transfer events: shares user→queue, share burn, USDC vault→queue, USDC queue→user
        vm.expectEmit(true, true, true, true, address(superusdBoringVault));
        emit Transfer(user, address(atomicQueue), withdrawShares);
        vm.expectEmit(true, true, true, true, address(superusdBoringVault));
        emit Transfer(address(atomicQueue), address(0), withdrawShares);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(superusdBoringVault), address(atomicQueue), expectedAssetsOut);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(atomicQueue), user, expectedAssetsOut);

        // Expect InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(
            user, address(superusdBoringVault), address(USDC), withdrawShares, expectedAssetsOut, block.timestamp
        );

        vm.prank(user);
        uint256 assetsOut = atomicQueue.instantWithdraw(
            ERC20(address(superusdBoringVault)), USDC, withdrawShares, 0, superusdTeller
        );

        // Verify balance diffs
        assertEq(assetsOut, expectedAssetsOut, "assetsOut matches expected");
        assertEq(USDC.balanceOf(user), userUSDCBefore + expectedAssetsOut, "user received USDC");
        assertEq(
            USDC.balanceOf(address(superusdBoringVault)),
            vaultUSDCBefore - expectedAssetsOut,
            "vault USDC decreased"
        );
        assertEq(
            ERC20(address(superusdBoringVault)).balanceOf(user),
            userSharesBefore - withdrawShares,
            "user shares decreased"
        );
    }

}
