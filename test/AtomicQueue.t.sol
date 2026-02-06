// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {BoringVault} from "src/base/BoringVault.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
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
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {Investor} from "src/atomic-queue/Investor.sol";

/// @title MockERC4626VaultAQ
/// @notice Mock ERC4626 vault for AtomicQueue integration tests
contract MockERC4626VaultAQ is ERC4626 {
    constructor(ERC20 _asset) ERC4626(_asset, "Mock ERC4626 Vault", "mVAULT") {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title MockATokenAQ
/// @notice Mock Aave aToken for AtomicQueue integration tests
contract MockATokenAQ is ERC20 {
    address public immutable _pool;
    address public immutable _underlyingAsset;

    constructor(address pool_, address underlyingAsset_) ERC20("Mock aToken", "aUSDC", 6) {
        _pool = pool_;
        _underlyingAsset = underlyingAsset_;
    }

    function POOL() external view returns (address) {
        return _pool;
    }

    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return _underlyingAsset;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title MockSakePoolAQ
/// @notice Mock Sake/Aave pool for AtomicQueue integration tests
contract MockSakePoolAQ {
    constructor() {}

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        SafeTransferLib.safeTransfer(ERC20(asset), to, amount);
        return amount;
    }
}

/// @title MockUSDC
/// @notice Mock USDC token for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC", 6) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC20Decimals is ERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_, decimals_)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ConstantRateProvider is IRateProvider {
    uint256 private immutable rate;

    constructor(uint256 _rate) {
        rate = _rate;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }
}

/// @title AtomicQueueTest
/// @notice Test contract for AtomicQueue functionality
contract AtomicQueueTest is Test, MerkleTreeHelper {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    BoringVault public boringVault;

    uint8 public constant MINTER_ROLE = 1;
    uint8 public constant BURNER_ROLE = 2;
    uint8 public constant SOLVER_ROLE = 3;
    uint8 public constant QUEUE_ROLE = 4;
    uint8 public constant ADMIN_ROLE = 5;
    uint8 public constant WITHDRAW_ROLE = 6;
    uint8 public constant INVESTOR_ROLE = 7;
    uint8 public constant QUEUE_INVESTOR_ROLE = 8;

    TellerWithMultiAssetSupport public teller;
    AccountantWithRateProviders public accountant;
    AtomicQueue public atomicQueue;
    AtomicSolverV4 public atomicSolverV4;
    address public payoutAddress = vm.addr(7777777);
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ERC20 internal constant NATIVE_ERC20 = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    RolesAuthority public rolesAuthority;
    MockUSDC public USDC;

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
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19363419;
        _startFork(rpcKey, blockNumber);

        USDC = new MockUSDC();

        Deployer deployer = new Deployer(address(this), Authority(address(0)));

        // Deploy implementation
        address implementation =
            deployer.deployContract("BoringVault-Implementation", type(BoringVault).creationCode, hex"", 0);

        // Prepare initializer data
        bytes memory initializer = abi.encodeWithSelector(
            BoringVault.initialize.selector,
            address(this), // owner
            Authority(address(0)), // authority
            "Boring Vault", // name
            "BV", // symbol
            6 // decimals
        );

        // Deploy proxy
        bytes memory proxyCreationCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializer));
        address proxy = deployer.deployContract("BoringVault", proxyCreationCode, hex"", 0);

        boringVault = BoringVault(payable(proxy));
        boringVault.setMaxTotalSupply(1000000000000000000000000000000000000000);

        accountant = new AccountantWithRateProviders(
            address(this),
            address(boringVault),
            payoutAddress,
            1e6, // USDC decimals
            address(USDC),
            1.005e4,
            0.995e4,
            1 days / 4,
            0,
            0
        );

        teller =
            new TellerWithMultiAssetSupport(address(this), address(boringVault), address(accountant), address(USDC));

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));

        atomicSolverV4 = new AtomicSolverV4(address(this), rolesAuthority);
        atomicQueue = new AtomicQueue(address(this), rolesAuthority, address(accountant), address(atomicSolverV4));

        boringVault.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        teller.setAuthority(rolesAuthority);
    
        rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(boringVault), BoringVault.exit.selector, true);
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkDeposit.selector, true
        );
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(QUEUE_ROLE, address(atomicSolverV4), AtomicSolverV4.finishSolve.selector, true);
        rolesAuthority.setRoleCapability(QUEUE_ROLE, address(atomicSolverV4), AtomicSolverV4.approveOfferForQueue.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.setMaturityTime.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.setDiscount.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.addToWhitelist.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.removeFromWhitelist.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.updateWhitelistMaturityDivisor.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.setSolver.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.cancelAtomicRequestByAdmin.selector, true);
        rolesAuthority.setRoleCapability(WITHDRAW_ROLE, address(atomicQueue), AtomicQueue.instantWithdraw.selector, true);
        rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(accountant), AccountantWithRateProviders.updateExchangeRate.selector, true);
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.updateAtomicRequest.selector, true);
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.solve.selector, true);
        rolesAuthority.setPublicCapability(address(atomicSolverV4), AtomicSolverV4.redeemSolve.selector, true);
        
        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicSolverV4), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), QUEUE_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(user, ADMIN_ROLE, true);
        rolesAuthority.setUserRole(user, WITHDRAW_ROLE, true);

        atomicQueue.setDiscount(0); // ignore the discount for testing

        teller.addAsset(USDC);

        USDC.mint(address(user), userUSDCInitialBalance);

        vm.startPrank(user);
        USDC.approve(address(boringVault), type(uint256).max);
        boringVault.approve(address(atomicQueue), type(uint256).max);

        teller.deposit(USDC, userUSDCInitialBalance, 0);
        vm.stopPrank();
    }

    //============================== ADMIN FUNCTIONS TESTS ================================
    function testSetMaturityTime() external {
        uint256 newMaturityTime = 2 hours;

        // Should emit event with correct initial value (1 days)
        vm.expectEmit(true, true, true, true);
        emit MaturityTimeUpdated(1 days, newMaturityTime);

        // Set new maturity time
        atomicQueue.setMaturityTime(newMaturityTime);

        // Verify new value
        assertEq(atomicQueue.maturityTime(), newMaturityTime);
    }

    function testAddAndRemoveFromWhitelist() external {
        vm.startPrank(user);
        atomicQueue.addToWhitelist(user);
        assertTrue(atomicQueue.whitelist(user));
        atomicQueue.removeFromWhitelist(user);
        assertFalse(atomicQueue.whitelist(user));
        vm.stopPrank();
    }

    function testWhitelistDivisorZeroReverts() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__BadWhitelistDivisor.selector));
        atomicQueue.updateWhitelistMaturityDivisor(0);
        vm.stopPrank();
    }

    function testSetDiscountBadReverts() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__BadDiscount.selector));
        atomicQueue.setDiscount(1e6);
        vm.stopPrank();
    }

    function testCancelAtomicRequestByAdmin() external {
        vm.startPrank(user);
        AtomicRequest[] memory reqs = new AtomicRequest[](1);
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });
        atomicQueue.updateAtomicRequest(req);
        reqs[0] = req;

        uint256 userSharesBeforeCancel = boringVault.balanceOf(user);
        uint256 solverSharesBeforeCancel = boringVault.balanceOf(address(atomicSolverV4));

        // Expect Transfer: shares solver→user
        vm.expectEmit(true, true, true, true, address(boringVault));
        emit Transfer(address(atomicSolverV4), user, 1_000e6);

        atomicQueue.cancelAtomicRequestByAdmin(reqs);

        // check the asset and share amount (before/after diff)
        assertEq(boringVault.balanceOf(address(atomicSolverV4)), solverSharesBeforeCancel - 1_000e6, "solver shares decreased");
        assertEq(boringVault.balanceOf(user), userSharesBeforeCancel + 1_000e6, "user shares restored");

        // Verify request was removed
        (bytes32[] memory requestIdsAfter,) = atomicQueue.getExistingWithdrawRequests();
        assertEq(requestIdsAfter.length, 0);
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault), address(USDC)), 0);
        // Can still get the request by request id
        assertEq(atomicQueue.getAtomicRequestById(keccak256(abi.encode(req))).user, user);

        // Canceled request can't be solved
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__RemovedRequest.selector));
        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req
        );

        // Can't get the user request
        (bytes32[] memory requestIds, AtomicRequest[] memory requests) = atomicQueue.getExistingWithdrawRequestsByUser(user);
        assertEq(requestIds.length, 0);
        assertEq(requests.length, 0);

        vm.stopPrank();
    }
    //============================== VIEW FUNCTIONS TESTS ================================
    function testGetExistingWithdrawRequests() external {
        vm.startPrank(user);

        // first request
        AtomicRequest memory req1 = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6), // Changed to USDC amount
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        // Create request 1
        atomicQueue.updateAtomicRequest(req1);

        // 10 blocks later
        vm.warp(block.timestamp + 10);

        // second request
        AtomicRequest memory req2 = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(2_000e6), // Changed to USDC amount
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        // Create request 2
        atomicQueue.updateAtomicRequest(req2);

        // 10 blocks later
        vm.warp(block.timestamp + 10);

        // third request
        AtomicRequest memory req3 = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(3_000e6), // Changed to USDC amount
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        // Create request 3
        atomicQueue.updateAtomicRequest(req3);

        // Get both requestIds and requests
        (bytes32[] memory requestIds, AtomicRequest[] memory requests) = atomicQueue.getExistingWithdrawRequests();

        assertEq(requestIds.length, 3);
        assertTrue(_contains(requestIds, keccak256(abi.encode(req1))));
        assertTrue(_contains(requestIds, keccak256(abi.encode(req2))));
        assertTrue(_contains(requestIds, keccak256(abi.encode(req3))));

        // Test actual requests
        assertEq(requests.length, 3);
        assertTrue(_containsRequest(requests, req1));
        assertTrue(_containsRequest(requests, req2));
        assertTrue(_containsRequest(requests, req3));

        vm.stopPrank();
    }

    function testGetTotalWithdrawInProgressAmount() external {
        // Setup initial state
        vm.startPrank(user);

        // Create a request
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() * 2),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        // Verify initial amount is 0
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault), address(USDC)), 0);

        // Update request and verify amount increased
        atomicQueue.updateAtomicRequest(req);
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault), address(USDC)), 1_000e6);

        // cancel request
        atomicQueue.cancelAtomicRequest(req);
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault), address(USDC)), 0);

        // Update request and solve it
        atomicQueue.updateAtomicRequest(req);
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault), address(USDC)), 1_000e6);
        skip(atomicQueue.maturityTime() + 1);


        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req
        );
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault), address(USDC)), 0);

        vm.stopPrank();
    }

    function testGetExistingWithdrawRequestsByUser() external {
        vm.startPrank(user);
        // first request
        AtomicRequest memory req1 = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6), 
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        // Create request 1
        atomicQueue.updateAtomicRequest(req1);
        vm.stopPrank();

        address otherUser = vm.addr(2);
        vm.startPrank(otherUser);
        deal(address(USDC), otherUser, 2_000e6);
        USDC.approve(address(boringVault), type(uint256).max);
        boringVault.approve(address(atomicQueue), type(uint256).max);
        teller.deposit(USDC, 2_000e6, 0);

        // second request
        AtomicRequest memory req2 = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(2_000e6), 
            user: otherUser,
            offer: address(boringVault),
            want: address(USDC)
        });

        // Create request 2
        atomicQueue.updateAtomicRequest(req2);

        // Check the result
        (bytes32[] memory requestIds, AtomicRequest[] memory requests) = atomicQueue.getExistingWithdrawRequestsByUser(user);
        assertEq(requestIds.length, 1);
        assertEq(requests.length, 1);
        assertEq(abi.encode(requests[0]), abi.encode(req1));

        (requestIds, requests) = atomicQueue.getExistingWithdrawRequestsByUser(otherUser);
        assertEq(requestIds.length, 1);
        assertEq(requests.length, 1);
        assertEq(abi.encode(requests[0]), abi.encode(req2));

        vm.stopPrank();
    }

    function testPreviewReceivedAmount() external {
        vm.startPrank(user);
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });
        atomicQueue.updateAtomicRequest(req);
        uint256 wantAmountReceived = atomicQueue.previewReceivedAmount(req);
        assertEq(wantAmountReceived, 1_000e6);
        vm.stopPrank();
    }
    //============================== USER FUNCTIONS TESTS ================================
    function testUpdateAtomicRequest() external {
        vm.startPrank(user);

        uint256 userSharesBefore = boringVault.balanceOf(user);
        uint256 solverSharesBefore = boringVault.balanceOf(address(atomicSolverV4));

        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        // Expect Transfer: shares user→solver
        vm.expectEmit(true, true, true, true, address(boringVault));
        emit Transfer(user, address(atomicSolverV4), 1_000e6);

        atomicQueue.updateAtomicRequest(req);

        // check the asset and share amount (before/after diff)
        assertEq(boringVault.balanceOf(address(atomicSolverV4)), solverSharesBefore + 1_000e6, "solver shares increased");
        assertEq(boringVault.balanceOf(user), userSharesBefore - 1_000e6, "user shares decreased");

        vm.stopPrank();
    }

    function testCancelAtomicRequest() external {
        vm.startPrank(user);

        // First create a request
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        atomicQueue.updateAtomicRequest(req);

        // Verify request exists
        (bytes32[] memory requestIdsBefore,) = atomicQueue.getExistingWithdrawRequests();
        assertEq(requestIdsBefore.length, 1);
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault), address(USDC)), 1_000e6);
        assertEq(atomicQueue.getAtomicRequestById(keccak256(abi.encode(req))).user, user);

        uint256 userSharesBeforeCancel = boringVault.balanceOf(user);
        uint256 solverSharesBeforeCancel = boringVault.balanceOf(address(atomicSolverV4));

        // Cancel request — expect Transfer (shares solver→user) and AtomicRequestCancelled event
        vm.expectEmit(true, true, true, true, address(boringVault));
        emit Transfer(address(atomicSolverV4), user, 1_000e6);
        vm.expectEmit(true, true, true, true);
        emit AtomicRequestCancelled(
            keccak256(abi.encode(req)),
            user, address(boringVault), address(USDC), req.offerAmount, req.deadline, block.timestamp
        );

        atomicQueue.cancelAtomicRequest(req);

        // check the asset and share amount (before/after diff)
        assertEq(boringVault.balanceOf(address(atomicSolverV4)), solverSharesBeforeCancel - 1_000e6, "solver shares decreased");
        assertEq(boringVault.balanceOf(user), userSharesBeforeCancel + 1_000e6, "user shares restored");

        // Verify request was removed
        (bytes32[] memory requestIdsAfter,) = atomicQueue.getExistingWithdrawRequests();
        assertEq(requestIdsAfter.length, 0);
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault), address(USDC)), 0);
        // Can still get the request by request id
        assertEq(atomicQueue.getAtomicRequestById(keccak256(abi.encode(req))).user, user);

        // Canceled request can't be solved
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__RemovedRequest.selector));
        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req
        );

        // Can't get the user request
        (bytes32[] memory requestIds, AtomicRequest[] memory requests) = atomicQueue.getExistingWithdrawRequestsByUser(user);
        assertEq(requestIds.length, 0);
        assertEq(requests.length, 0);

        vm.stopPrank();
    }

    function testDuplicateRequestReverts() external {
        vm.startPrank(user);
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1000),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });
        atomicQueue.updateAtomicRequest(req);
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__DuplicateRequest.selector));
        atomicQueue.updateAtomicRequest(req);
        vm.stopPrank();
    }

    function testOfferMismatchOnUpdateReverts() external {
        vm.startPrank(user);
        AtomicRequest memory bad = AtomicRequest({
            deadline: uint64(block.timestamp + 1000),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(USDC), // not the vault
            want: address(USDC)
        });
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__RequestAccountantOfferMismatch.selector, address(USDC), address(boringVault)));
        atomicQueue.updateAtomicRequest(bad);
        vm.stopPrank();
    }

    function testRequestUnsupportedWantToken() external {
        vm.startPrank(user);

        ERC20 nonSupportedToken = ERC20(address(new MockUSDC()));

        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6), 
            user: user,
            offer: address(boringVault),
            want: address(nonSupportedToken)
        });
        vm.expectRevert();
        atomicQueue.updateAtomicRequest(req);
        vm.stopPrank();
    }

    function testExpiredDeadlineOnUpdateReverts() external {
        vm.startPrank(user);
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp - 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__DeadlineExpired.selector));
        atomicQueue.updateAtomicRequest(req);
        vm.stopPrank();
    }

    function testInsufficientBalanceOnUpdateReverts() external {
        vm.startPrank(user);
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1000),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(userUSDCInitialBalance + 1),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__InsufficientBalance.selector));
        atomicQueue.updateAtomicRequest(req);
        vm.stopPrank();
    }

    function testCancelByNonOwnerReverts() external {
        vm.startPrank(user);
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1000),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });
        atomicQueue.updateAtomicRequest(req);
        vm.stopPrank();

        address other = vm.addr(3);
        vm.startPrank(other);
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__BadUser.selector));
        atomicQueue.cancelAtomicRequest(req);
        vm.stopPrank();
    }

    function testSolveRequest() external {
        vm.startPrank(user);

        // update the exchange rate to 1.001
        skip(1 days);
        accountant.updateExchangeRate(1.001e6);
        uint256 userShareAmountBefore = boringVault.balanceOf(user);

        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() * 2),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        atomicQueue.updateAtomicRequest(req);

        // Verify request was added
        (bytes32[] memory requestIds,) = atomicQueue.getExistingWithdrawRequests();
        assertEq(requestIds.length, 1);

        vm.warp(block.timestamp + atomicQueue.maturityTime() + 1);
        // the request should be updated to the new atomic price, so don't directly use the `req` above
        AtomicRequest memory newReq = atomicQueue.getAtomicRequestById(requestIds[0]);
        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, newReq
        );

        // Verify request was removed
        (requestIds,) = atomicQueue.getExistingWithdrawRequests();
        assertEq(requestIds.length, 0);
        (bytes32[] memory userRequestIds, AtomicRequest[] memory userRequests) = atomicQueue.getExistingWithdrawRequestsByUser(user);
        assertEq(userRequestIds.length, 0);
        assertEq(userRequests.length, 0);

        // check user and vault balance
        // USDC: user offer 1000e6 share, should receive 1000e6 * 1.001 USDC
        assertEq(USDC.balanceOf(user), uint256(1_000e6).mulDivDown(1001, 1000));
        assertEq(USDC.balanceOf(address(boringVault)), userUSDCInitialBalance - uint256(1_000e6).mulDivDown(1001, 1000));
        // share: user burn 1000e6 share
        assertEq(boringVault.balanceOf(user), userShareAmountBefore - 1_000e6);

        vm.stopPrank();
    }

    function testSolveRequestWithDifferentWant() external {
        MockERC20Decimals newAsset = new MockERC20Decimals("Mock Asset", "MOCK", 18);
        ConstantRateProvider doubleUSDCPrice = new ConstantRateProvider(2e18);

        teller.addAsset(newAsset);
        accountant.setRateProviderData(newAsset, false, address(doubleUSDCPrice));

        vm.startPrank(user);
        uint256 userShareAmountBefore = boringVault.balanceOf(user);
        deal(address(newAsset), user, 1_000e18);
        newAsset.approve(address(boringVault), 1_000e18);
        teller.deposit(newAsset, 1_000e18, 0);

        // check user share amount, 1000e6*2 added but not 1000e18*2
        assertEq(boringVault.balanceOf(user), userShareAmountBefore + 1_000e6 * 2);
        assertEq(newAsset.balanceOf(user), 0);

        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() * 2),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6), // offer half
            user: user,
            offer: address(boringVault),
            want: address(newAsset)
        });
        newAsset.approve(address(atomicQueue), 1_000e6);
        atomicQueue.updateAtomicRequest(req);

        // check balance updated
        assertEq(boringVault.balanceOf(address(atomicSolverV4)), 1_000e6);

        vm.warp(block.timestamp + atomicQueue.maturityTime() + 1);
        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req
        );

        // check balance updated
        assertEq(newAsset.balanceOf(user), 1_000e18 / 2);
        assertEq(newAsset.balanceOf(address(atomicSolverV4)), 0);
        assertEq(boringVault.balanceOf(user), userShareAmountBefore + 1_000e6);

        vm.stopPrank();
    }

    function testSolveOtherUserRequest() external {
        vm.startPrank(user);

        // update the exchange rate to 1.001
        skip(1 days);
        accountant.updateExchangeRate(1.001e6);
        uint256 userShareAmountBefore = boringVault.balanceOf(user);

        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() * 2),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        atomicQueue.updateAtomicRequest(req);

        // Verify request was added
        (bytes32[] memory requestIds,) = atomicQueue.getExistingWithdrawRequests();
        assertEq(requestIds.length, 1);

        vm.stopPrank();

        address otherUser = vm.addr(2);

        vm.startPrank(otherUser);
        deal(address(USDC), address(otherUser), 10_000_000e6);

        vm.warp(block.timestamp + atomicQueue.maturityTime() + 1);
        // the request should be updated to the new atomic price, so don't directly use the `req` above
        AtomicRequest memory newReq = atomicQueue.getAtomicRequestById(requestIds[0]);
        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, newReq
        );

        // Verify request was removed
        (requestIds,) = atomicQueue.getExistingWithdrawRequests();
        assertEq(requestIds.length, 0);

        // check user and vault balance
        // USDC: user offer 1000e6 share, should receive 1000e6 * 1.001 USDC
        assertEq(USDC.balanceOf(user), uint256(1_000e6).mulDivDown(1001, 1000));
        assertEq(USDC.balanceOf(address(boringVault)), userUSDCInitialBalance - uint256(1_000e6).mulDivDown(1001, 1000));
        // share: user burn 1000e6 share
        assertEq(boringVault.balanceOf(user), userShareAmountBefore - 1_000e6);

        vm.stopPrank();
    }

    function testSolveWhiteListUser() external {
        vm.startPrank(user);
        atomicQueue.addToWhitelist(user);
        atomicQueue.updateWhitelistMaturityDivisor(10);
        assertTrue(atomicQueue.whitelist(user));

        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() * 2),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });
        atomicQueue.updateAtomicRequest(req);

        // Verify request was added
        (bytes32[] memory requestIds,) = atomicQueue.getExistingWithdrawRequests();
        assertEq(requestIds.length, 1);

        // Warp past maturity time for whitelisted user
        vm.warp(block.timestamp + atomicQueue.maturityTime() / 10 + 1);

        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req
        );

        // Verify request was removed
        (requestIds,) = atomicQueue.getExistingWithdrawRequests();
        assertEq(requestIds.length, 0);

        // check user balance
        assertEq(USDC.balanceOf(user), 1_000e6);
        assertEq(boringVault.balanceOf(user), userUSDCInitialBalance - 1_000e6);

        vm.stopPrank();
    }

    function testSolveRequestExpiredDeadline() external {
        vm.startPrank(user);

        // Create request with short deadline but after maturity time
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        atomicQueue.updateAtomicRequest(req);

        // Move time past maturity time and deadline
        vm.warp(block.timestamp + atomicQueue.maturityTime() + 2);

        // Setup solver
        address[] memory users = new address[](1);
        users[0] = user;

        // Expect revert on solve
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__DeadlineExpired.selector));
        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req
        );
        vm.stopPrank();
    }

    function testRequestZeroAmount() external {
        vm.startPrank(user);

        // Create request with zero amount but valid maturity time
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: 0,
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__OfferAmountIsZero.selector));
        atomicQueue.updateAtomicRequest(req);

        vm.stopPrank();
    }

    function testSolveRequestBeforeMaturity() external {
        vm.startPrank(user);

        // Create request
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() + 1),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        atomicQueue.updateAtomicRequest(req);

        // Try to solve before maturity time
        address[] memory users = new address[](1);
        users[0] = user;

        // Should revert because maturity time hasn't passed
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__RequestNotMature.selector, user));
        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req
        );

        // Warp past maturity time
        vm.warp(block.timestamp + atomicQueue.maturityTime() + 1);

        uint256 userSharesBefore = boringVault.balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);
        uint256 vaultUSDCBefore = USDC.balanceOf(address(boringVault));

        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req
        );

        // User received USDC (rate = 1e6, so 1:1)
        assertEq(USDC.balanceOf(user), userUSDCBefore + 1_000e6, "user received USDC");
        assertEq(USDC.balanceOf(address(boringVault)), vaultUSDCBefore - 1_000e6, "vault USDC decreased");
        // Shares were already with solver, user shares unchanged
        assertEq(boringVault.balanceOf(user), userSharesBefore, "user shares unchanged");

        vm.stopPrank();
    }

    function testDiscount() external {
        vm.startPrank(user);
        uint256 discount = 500; // 0.05%
        atomicQueue.setDiscount(discount);

        uint256 userShareAmountBefore = boringVault.balanceOf(user);

        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() * 2),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });

        atomicQueue.updateAtomicRequest(req);

        (bytes32[] memory requestIds,) = atomicQueue.getExistingWithdrawRequests();

        vm.warp(block.timestamp + atomicQueue.maturityTime() + 1);
        // the request should be updated to the new atomic price, so don't directly use the `req` above
        AtomicRequest memory newReq = atomicQueue.getAtomicRequestById(requestIds[0]);
        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, newReq
        );

        // check user and vault balance
        // USDC: user offer 1000e6 share, should receive 1000e6 (1 - discount)
        assertEq(USDC.balanceOf(user), uint256(1_000e6).mulDivDown(1e6 - discount, 1e6));
        // USDC: Discount goes to boring vault
        assertEq(USDC.balanceOf(address(boringVault)), userUSDCInitialBalance - 1_000e6 + uint256(1_000e6).mulDivDown(discount, 1e6));
        // share: user burn 1000e6 share
        assertEq(boringVault.balanceOf(user), userShareAmountBefore - 1_000e6);

        vm.stopPrank();
    }

    function testInstantWithdraw() external {
        vm.startPrank(user);

        // update several requests and solve one of them
        AtomicRequest memory req1 = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() * 2),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(userUSDCInitialBalance - 1000e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });
        atomicQueue.updateAtomicRequest(req1);

        skip(atomicQueue.maturityTime() + 1);

        uint256 userSharesBefore = boringVault.balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);
        uint256 vaultUSDCBefore = USDC.balanceOf(address(boringVault));

        // Expect Transfer events: shares user→queue, share burn, USDC vault→queue, USDC queue→user
        vm.expectEmit(true, true, true, true, address(boringVault));
        emit Transfer(user, address(atomicQueue), 1e6);
        vm.expectEmit(true, true, true, true, address(boringVault));
        emit Transfer(address(atomicQueue), address(0), 1e6);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(boringVault), address(atomicQueue), 1e6);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(atomicQueue), user, 1e6);

        // Expect InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(user, address(boringVault), address(USDC), 1e6, 1e6, block.timestamp);

        // instant withdraw
        atomicQueue.instantWithdraw(ERC20(address(boringVault)), USDC, 1e6, 0, teller);

        // Check the usdc and vault share amount (before/after diff)
        assertEq(USDC.balanceOf(user), userUSDCBefore + 1e6, "user USDC increased");
        assertEq(USDC.balanceOf(address(boringVault)), vaultUSDCBefore - 1e6, "vault USDC decreased");
        assertEq(boringVault.balanceOf(user), userSharesBefore - 1e6, "user shares decreased");

        // all the remaining requests should can still be solved
        uint256 userUSDCBeforeSolve = USDC.balanceOf(user);
        uint256 vaultUSDCBeforeSolve = USDC.balanceOf(address(boringVault));
        uint256 userSharesBeforeSolve = boringVault.balanceOf(user);

        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req1
        );
        assertEq(USDC.balanceOf(user), userUSDCBeforeSolve + (userUSDCInitialBalance - 1000e6), "user USDC after solve");
        assertEq(USDC.balanceOf(address(boringVault)), vaultUSDCBeforeSolve - (userUSDCInitialBalance - 1000e6), "vault USDC after solve");
        assertEq(boringVault.balanceOf(user), userSharesBeforeSolve, "user shares unchanged by solve");

        vm.stopPrank();
    }

    function testInstantWithdrawWithDiscount() external {
        vm.startPrank(user);
        uint256 discount = 500; // 0.05%
        atomicQueue.setDiscount(discount);

        uint256 offerAmount = 1000e6;
        uint256 fullAssetsOut = offerAmount; // rate = 1e6, so 1:1
        uint256 discountedAmount = fullAssetsOut.mulDivDown(1e6 - discount, 1e6);
        uint256 excess = fullAssetsOut - discountedAmount;

        uint256 userSharesBefore = boringVault.balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);
        uint256 vaultUSDCBefore = USDC.balanceOf(address(boringVault));

        // Expect Transfer events: shares user→queue, share burn, USDC vault→queue(full), excess→vault, discounted→user
        vm.expectEmit(true, true, true, true, address(boringVault));
        emit Transfer(user, address(atomicQueue), offerAmount);
        vm.expectEmit(true, true, true, true, address(boringVault));
        emit Transfer(address(atomicQueue), address(0), offerAmount);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(boringVault), address(atomicQueue), fullAssetsOut);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(atomicQueue), address(boringVault), excess);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(atomicQueue), user, discountedAmount);

        // Expect InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(user, address(boringVault), address(USDC), offerAmount, discountedAmount, block.timestamp);

        // instant withdraw
        atomicQueue.instantWithdraw(ERC20(address(boringVault)), USDC, offerAmount, 0, teller);

        // Check the usdc and vault share amount (before/after diff)
        assertEq(USDC.balanceOf(user), userUSDCBefore + discountedAmount, "user received discounted USDC");
        assertEq(USDC.balanceOf(address(boringVault)), vaultUSDCBefore - fullAssetsOut + excess, "vault USDC decreased minus excess");
        assertEq(boringVault.balanceOf(user), userSharesBefore - offerAmount, "user shares decreased");

        vm.stopPrank();
    }

    function testInstantWithdrawWithDifferentWant() external {
        // Deploy 18-decimal asset with 2x rate (1 quote = 2 USDC)
        MockERC20Decimals newAsset = new MockERC20Decimals("Mock 18 Asset", "M18", 18);
        ConstantRateProvider doublePrice = new ConstantRateProvider(2e18);

        teller.addAsset(newAsset);
        accountant.setRateProviderData(newAsset, false, address(doublePrice));

        // Seed boringVault with the 18-decimal asset
        deal(address(newAsset), address(boringVault), 10_000e18);

        vm.startPrank(user);

        uint256 offerAmount = 100e6; // 100 vault shares (6 decimals)
        // exchangeRate = 1e6 (USDC base decimals)
        // exchangeRateInQuoteDecimals = changeDecimals(1e6, 6, 18) = 1e18
        // rateInQuote = 1e18 * 1e18 / 2e18 = 0.5e18
        // assetsOut = offerAmount * rateInQuote / ONE_SHARE = 100e6 * 0.5e18 / 1e6 = 50e18
        // discount is 0, so user receives 50e18
        uint256 expectedOut = 50e18;

        uint256 userSharesBefore = boringVault.balanceOf(user);
        uint256 userNewAssetBefore = newAsset.balanceOf(user);
        uint256 vaultNewAssetBefore = newAsset.balanceOf(address(boringVault));

        // Expect Transfer events: shares user→queue, share burn, newAsset vault→queue, newAsset queue→user
        vm.expectEmit(true, true, true, true, address(boringVault));
        emit Transfer(user, address(atomicQueue), offerAmount);
        vm.expectEmit(true, true, true, true, address(boringVault));
        emit Transfer(address(atomicQueue), address(0), offerAmount);
        vm.expectEmit(true, true, true, true, address(newAsset));
        emit Transfer(address(boringVault), address(atomicQueue), expectedOut);
        vm.expectEmit(true, true, true, true, address(newAsset));
        emit Transfer(address(atomicQueue), user, expectedOut);

        // Expect InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(user, address(boringVault), address(newAsset), offerAmount, expectedOut, block.timestamp);

        atomicQueue.instantWithdraw(ERC20(address(boringVault)), ERC20(address(newAsset)), offerAmount, 0, teller);

        // Check balance diffs
        assertEq(newAsset.balanceOf(user), userNewAssetBefore + expectedOut, "User should receive 50e18 of 18-decimal asset");
        assertEq(newAsset.balanceOf(address(boringVault)), vaultNewAssetBefore - expectedOut, "vault newAsset decreased");
        assertEq(boringVault.balanceOf(user), userSharesBefore - offerAmount, "Shares should be burned");

        vm.stopPrank();
    }

    function testInstantWithdrawInsufficientLiquidity() external {
        vm.startPrank(user);

        // update several requests and solve one of them
        AtomicRequest memory req1 = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() * 2),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(userUSDCInitialBalance - 1e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });
        atomicQueue.updateAtomicRequest(req1);

        skip(atomicQueue.maturityTime() + 1);

        // instant withdraw
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__InsufficientVaultLiquidity.selector, userUSDCInitialBalance - 1e6 + 1000e6, userUSDCInitialBalance));
        atomicQueue.instantWithdraw(ERC20(address(boringVault)), USDC, 1000e6, 0, teller);

        vm.stopPrank();
    }

    function testInstantWithdrawZeroAmountReverts() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__ZeroOfferAmount.selector, user));
        atomicQueue.instantWithdraw(ERC20(address(boringVault)), USDC, 0, 0, teller);
        vm.stopPrank();
    }

    function testInstantWithdrawMinimumOutNotMet() external {
        vm.startPrank(user);
        // request a minimum greater than discounted output to trigger revert
        uint256 amount = 10e6;
        // compute slightly above discounted
        uint256 rate = AccountantWithRateProviders(address(accountant)).getRateInQuoteSafe(USDC);
        uint256 expectedOut = uint256(amount).mulDivDown(rate, 10 ** ERC20(address(boringVault)).decimals());
        uint256 minOutTooHigh = expectedOut + 1;
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__MinimumAssetsNotMet.selector));
        atomicQueue.instantWithdraw(ERC20(address(boringVault)), USDC, amount, minOutTooHigh, teller);
        vm.stopPrank();
    }

    // ========================================= INVESTOR INTEGRATION TESTS =========================================

    function _setupInvestor()
        internal
        returns (Investor _investor, MockERC4626VaultAQ _mockVault)
    {
        _mockVault = new MockERC4626VaultAQ(ERC20(address(USDC)));
        _investor = new Investor(address(this), rolesAuthority, address(boringVault));

        // Grant Investor the manage(address,bytes,uint256) capability on BoringVault
        rolesAuthority.setRoleCapability(
            INVESTOR_ROLE,
            address(boringVault),
            bytes4(keccak256("manage(address,bytes,uint256)")),
            true
        );
        rolesAuthority.setUserRole(address(_investor), INVESTOR_ROLE, true);

        // Grant AtomicQueue the autoWithdrawal capability on Investor
        rolesAuthority.setRoleCapability(
            QUEUE_INVESTOR_ROLE, address(_investor), Investor.autoWithdrawal.selector, true
        );
        rolesAuthority.setUserRole(address(atomicQueue), QUEUE_INVESTOR_ROLE, true);

        // Grant admin capability to set investor
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.setInvestor.selector, true);

        // Set the investor on the queue
        atomicQueue.setInvestor(address(_investor));

        // Configure vault in investor
        Investor.VaultInfo[] memory vaults = new Investor.VaultInfo[](1);
        vaults[0] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(_mockVault)});
        _investor.setVaults(vaults);
    }

    function testSetInvestor() external {
        Investor _investor = new Investor(address(this), rolesAuthority, address(boringVault));

        vm.expectEmit(true, true, true, true);
        emit InvestorUpdated(address(_investor));

        atomicQueue.setInvestor(address(_investor));

        assertEq(address(atomicQueue.investor()), address(_investor));
    }

    function testSetInvestorRequiresAuth() external {
        address unauthorized = vm.addr(99);
        vm.prank(unauthorized);
        vm.expectRevert("UNAUTHORIZED");
        atomicQueue.setInvestor(address(1));
    }

    function testSetInvestorToZero() external {
        atomicQueue.setInvestor(address(0));
        assertEq(address(atomicQueue.investor()), address(0));
    }

    function testInstantWithdrawInvestorFreesEnough() external {
        (Investor _investor, MockERC4626VaultAQ _mockVault) = _setupInvestor();

        // Drain most USDC from boringVault so it doesn't have enough
        uint256 vaultUsdcBalance = USDC.balanceOf(address(boringVault));
        // Keep only 100 USDC in the vault, need to withdraw 500 USDC worth of shares
        uint256 amountToRemove = vaultUsdcBalance - 100e6;
        // Move USDC out by dealing it away
        deal(address(USDC), address(boringVault), 100e6);

        // Put 1000 USDC into the ERC4626 vault as shares held by boringVault
        deal(address(_mockVault), address(boringVault), 1_000e6);
        deal(address(USDC), address(_mockVault), 1_000e6);

        vm.startPrank(user);

        uint256 offerAmount = 500e6;
        uint256 userSharesBefore = boringVault.balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);

        // Expect share Transfer and InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(boringVault));
        emit Transfer(user, address(atomicQueue), offerAmount);
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(user, address(boringVault), address(USDC), offerAmount, offerAmount, block.timestamp);

        atomicQueue.instantWithdraw(ERC20(address(boringVault)), USDC, offerAmount, 0, teller);

        // Check balance diffs
        assertEq(USDC.balanceOf(user), userUSDCBefore + offerAmount, "User receives 500 USDC");
        assertEq(USDC.balanceOf(user) - userUSDCBefore, offerAmount, "USDC diff matches");
        assertEq(boringVault.balanceOf(user), userSharesBefore - offerAmount, "Shares burned");

        vm.stopPrank();
    }

    function testInstantWithdrawInvestorCannotFreeEnough() external {
        (Investor _investor, MockERC4626VaultAQ _mockVault) = _setupInvestor();

        // Vault has only 100 USDC, ERC4626 has only 50 USDC
        deal(address(USDC), address(boringVault), 100e6);
        deal(address(_mockVault), address(boringVault), 50e6);
        deal(address(USDC), address(_mockVault), 50e6);

        vm.startPrank(user);

        // Try to withdraw 500 shares = 500 USDC needed, only 150 available total
        uint256 offerAmount = 500e6;
        uint256 totalRequired = offerAmount; // no pending, discount=0, rate=1

        vm.expectRevert(
            abi.encodeWithSelector(
                AtomicQueue.AtomicQueue__InsufficientVaultLiquidity.selector, totalRequired, 150e6
            )
        );
        atomicQueue.instantWithdraw(ERC20(address(boringVault)), USDC, offerAmount, 0, teller);

        vm.stopPrank();
    }

    function testInstantWithdrawWithInvestorAndDiscount() external {
        (Investor _investor, MockERC4626VaultAQ _mockVault) = _setupInvestor();

        uint256 discountPpm = 500; // 0.05%
        atomicQueue.setDiscount(discountPpm);

        // Create a pending withdrawal to inflate totalRequired beyond assetsOut,
        // ensuring the investor frees enough USDC to cover the full undiscounted exit.
        vm.startPrank(user);
        AtomicRequest memory pendingReq = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() * 2),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(100e6),
            user: user,
            offer: address(boringVault),
            want: address(USDC)
        });
        atomicQueue.updateAtomicRequest(pendingReq);
        vm.stopPrank();

        // Set vault USDC low so investor is triggered
        deal(address(USDC), address(boringVault), 10e6);
        deal(address(_mockVault), address(boringVault), 2_000e6);
        deal(address(USDC), address(_mockVault), 2_000e6);

        vm.startPrank(user);

        uint256 offerAmount = 200e6;
        // assetsOut = 200e6 (rate=1). assetOutWithDiscount = 200e6 * (1e6 - 500) / 1e6 = 199_900_000
        // pendingWithdrawAssets = 100e6. totalRequired = 199_900_000 + 100e6 = 299_900_000
        // vaultBalance = 10e6 < 299_900_000 → investor triggered
        // Investor frees 289_900_000. Post: 10e6 + 289_900_000 = 299_900_000. Passes check.
        // exit needs 200e6 USDC from vault. 299_900_000 >= 200e6 ✓
        uint256 expectedOut = uint256(offerAmount).mulDivDown(1e6 - discountPpm, 1e6);

        uint256 userSharesBefore = boringVault.balanceOf(user);
        uint256 userUSDCBefore = USDC.balanceOf(user);

        // Expect share Transfer and InstantWithdraw event
        vm.expectEmit(true, true, true, true, address(boringVault));
        emit Transfer(user, address(atomicQueue), offerAmount);
        vm.expectEmit(true, true, true, true, address(atomicQueue));
        emit InstantWithdraw(user, address(boringVault), address(USDC), offerAmount, expectedOut, block.timestamp);

        atomicQueue.instantWithdraw(ERC20(address(boringVault)), USDC, offerAmount, 0, teller);

        // Check balance diffs
        assertEq(USDC.balanceOf(user), userUSDCBefore + expectedOut, "User receives discounted amount");
        assertEq(boringVault.balanceOf(user), userSharesBefore - offerAmount, "Shares burned");
        vm.stopPrank();
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}
