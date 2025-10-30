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

/// @title MockUSDC
/// @notice Mock USDC token for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC", 6) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
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

        atomicQueue = new AtomicQueue(address(this), rolesAuthority, address(accountant));
        atomicSolverV4 = new AtomicSolverV4(address(this), rolesAuthority);

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
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.addToWhitelist.selector, true);
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(atomicQueue), AtomicQueue.removeFromWhitelist.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(atomicQueue), AtomicQueue.updateWhitelistMaturityDivisor.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(atomicQueue), AtomicQueue.setDiscount.selector, true
        );
        rolesAuthority.setRoleCapability(
            WITHDRAW_ROLE, address(atomicQueue), AtomicQueue.instantWithdraw.selector, true
        );
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
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault)), 0);

        // Update request and verify amount increased
        atomicQueue.updateAtomicRequest(req);
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault)), 1_000e6);

        // cancel request
        atomicQueue.cancelAtomicRequest(req);
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault)), 0);

        // Update request and solve it
        atomicQueue.updateAtomicRequest(req);
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault)), 1_000e6);
        skip(atomicQueue.maturityTime() + 1);

        // Approve solver
        USDC.approve(address(atomicSolverV4), type(uint256).max);

        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req
        );
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault)), 0);

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
    //============================== USER FUNCTIONS TESTS ================================

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
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault)), 1_000e6);
        assertEq(atomicQueue.getAtomicRequestById(keccak256(abi.encode(req))).user, user);

        // Cancel request
        vm.expectEmit(true, true, true, true);
        emit AtomicRequestCancelled(
            keccak256(abi.encode(req)),
            user, address(boringVault), address(USDC), req.offerAmount, req.deadline, block.timestamp
        );

        atomicQueue.cancelAtomicRequest(req);

        // Verify request was removed
        (bytes32[] memory requestIdsAfter,) = atomicQueue.getExistingWithdrawRequests();
        assertEq(requestIdsAfter.length, 0);
        assertEq(atomicQueue.withdrawInProgressAmount(address(boringVault)), 0);
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
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__SafeRequestAccountantOfferMismatch.selector));
        atomicQueue.updateAtomicRequest(bad);
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

        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req
        );

        vm.stopPrank();
    }

    function testSolveInsufficientAllowanceReverts() external {
        address other = vm.addr(4);
        // fund and deposit for other, but DO NOT approve atomicQueue with vault shares
        deal(address(USDC), other, 5_000e6);
        vm.startPrank(other);
        USDC.approve(address(boringVault), type(uint256).max);
        boringVault.approve(address(atomicQueue), 0); // ensure no allowance
        teller.deposit(USDC, 5_000e6, 0);

        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.maturityTime() * 2),
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(1_000e6),
            user: other,
            offer: address(boringVault),
            want: address(USDC)
        });
        atomicQueue.updateAtomicRequest(req);
        vm.warp(block.timestamp + atomicQueue.maturityTime() + 1);
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__InsufficientAllowance.selector));
        atomicSolverV4.redeemSolve(atomicQueue, 0, type(uint256).max, teller, req);
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

        // Approve solver
        USDC.approve(address(atomicSolverV4), type(uint256).max);

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

        // instant withdraw
        atomicQueue.instantWithdraw(ERC20(address(boringVault)), USDC, 1e6, 0, teller);
        // Check the usdc and vault share amount
        assertEq(USDC.balanceOf(user), 1e6);
        assertEq(USDC.balanceOf(address(boringVault)), userUSDCInitialBalance - 1e6);
        assertEq(boringVault.balanceOf(user), userUSDCInitialBalance - 1e6);

        // all the remaining requests should can still be solved
        USDC.approve(address(atomicSolverV4), type(uint256).max);
        atomicSolverV4.redeemSolve(
            atomicQueue, 0, type(uint256).max, teller, req1
        );
        assertEq(USDC.balanceOf(user), userUSDCInitialBalance - 1000e6 + 1e6);
        assertEq(USDC.balanceOf(address(boringVault)), 1000e6 - 1e6);
        assertEq(boringVault.balanceOf(user), 1000e6 - 1e6);

        vm.stopPrank();
    }

    function testInstantWithdrawWithDiscount() external {
        vm.startPrank(user);
        uint256 discount = 500; // 0.05%
        atomicQueue.setDiscount(discount);

        // instant withdraw
        atomicQueue.instantWithdraw(ERC20(address(boringVault)), USDC, 1000e6, 0, teller);
        // Check the usdc and vault share amount
        assertEq(USDC.balanceOf(user), uint256(1000e6).mulDivDown(1e6 - discount, 1e6));
        assertEq(USDC.balanceOf(address(boringVault)), userUSDCInitialBalance - 1000e6 + uint256(1000e6).mulDivDown(discount, 1e6));
        assertEq(boringVault.balanceOf(user), userUSDCInitialBalance - 1000e6);

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

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}
