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
import {AtomicSolverV4, AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicSolverV4.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";

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
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 amount,
        uint256 deadline,
        uint256 minPrice,
        uint256 timestamp
    );

    event AtomicRequestCancelled(
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 amount,
        uint256 deadline,
        uint256 minPrice,
        uint256 timestamp
    );

    event AtomicRequestFulfilled(
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 amount,
        uint256 minPrice,
        uint256 timestamp
    );  

    event MaturityTimeUpdated(uint256 oldMaturityTime, uint256 newMaturityTime);

    uint256 constant DEFAULT_MATURITY_TIME = 1 hours;

    function setUp() external {
        USDC = new MockUSDC();
        
        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 6);

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

        teller = new TellerWithMultiAssetSupport(
            address(this), 
            address(boringVault), 
            address(accountant), 
            address(USDC)
        );

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));

        atomicQueue = new AtomicQueue(address(this), rolesAuthority);
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
        rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.updateAtomicRequest.selector, true);
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.solve.selector, true);
        rolesAuthority.setPublicCapability(address(atomicSolverV4), AtomicSolverV4.redeemSelfSolve.selector, true);

        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicSolverV4), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), QUEUE_ROLE, true);

        teller.addAsset(USDC);

        USDC.mint(address(user), 1_000_000_000e6);

        vm.startPrank(user);
        USDC.approve(address(boringVault), type(uint256).max);
        boringVault.approve(address(atomicQueue), type(uint256).max);
        teller.deposit(USDC, 1_000_000_000e6, 0);
        assertEq(boringVault.balanceOf(user), 1_000_000_000e6);
        assertEq(USDC.balanceOf(user), 0);
        vm.stopPrank();
    }

    function testGetWithdrawRequests() external {
        vm.startPrank(user);
        
        // first request
        AtomicRequest memory req1 = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6), // Changed to USDC decimals
            offerAmount: uint96(1_000e6) // Changed to USDC amount
        });

        // Create request 1
        atomicQueue.updateAtomicRequest(boringVault, USDC, req1);

        // 10 blocks later
        vm.warp(block.timestamp + 10);

        // second request
        AtomicRequest memory req2 = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6), // Changed to USDC decimals
            offerAmount: uint96(2_000e6) // Changed to USDC amount
        });

        // Create request 2
        atomicQueue.updateAtomicRequest(boringVault, USDC, req2);

        // 10 blocks later
        vm.warp(block.timestamp + 10);

        // third request
        AtomicRequest memory req3 = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6), // Changed to USDC decimals
            offerAmount: uint96(3_000e6) // Changed to USDC amount
        });

        // Create request 3
        atomicQueue.updateAtomicRequest(boringVault, USDC, req3);

        // Get both requestIds and requests
        (bytes32[] memory requestIds, AtomicRequest[] memory requests) = atomicQueue.getWithdrawRequests();
        
        assertEq(requestIds.length, 3);
        assertEq(requestIds[0], keccak256(abi.encode(user, address(boringVault), address(USDC), req1)));
        assertEq(requestIds[1], keccak256(abi.encode(user, address(boringVault), address(USDC), req2)));
        assertEq(requestIds[2], keccak256(abi.encode(user, address(boringVault), address(USDC), req3)));

        // Test actual requests
        assertEq(requests.length, 3);
        assertEq(abi.encode(requests[0]), abi.encode(req1));
        assertEq(abi.encode(requests[1]), abi.encode(req2));
        assertEq(abi.encode(requests[2]), abi.encode(req3));

        vm.stopPrank();
    }

    function testGetAtomicRequest() external {
        vm.startPrank(user);
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6), // Changed to USDC decimals
            offerAmount: uint96(1_000e6) // Changed to USDC amount
        });
        atomicQueue.updateAtomicRequest(boringVault, USDC, req);

        bytes32 requestId = keccak256(abi.encode(
            user,
            address(boringVault),
            address(USDC),
            req
        ));
        AtomicRequest memory request = atomicQueue.getAtomicRequest(requestId);
        assertEq(request.deadline, req.deadline);
        assertEq(request.creationTime, req.creationTime);
        assertEq(request.atomicPrice, req.atomicPrice);
        assertEq(request.offerAmount, req.offerAmount);
    }

    function testGetTotalWithdrawInProgressAmount() external {
        // Setup initial state
        vm.startPrank(user);
        
        // Create a request
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6),
            offerAmount: uint96(1_000e6)
        });
        
        // Verify initial amount is 0
        assertEq(atomicQueue.withdrawInProgressAmount(boringVault), 0);
        
        // Update request and verify amount increased
        atomicQueue.updateAtomicRequest(boringVault, USDC, req);
        assertEq(atomicQueue.withdrawInProgressAmount(boringVault), 1_000e6);
        
        vm.stopPrank();
    }

    function testGetWithdrawRequestsEmpty() external {
        (bytes32[] memory requestIds, AtomicRequest[] memory requests) = atomicQueue.getWithdrawRequests();
        assertEq(requestIds.length, 0);
        assertEq(requests.length, 0);
    }

    function testGetWithdrawRequestsMultiple() external {
        vm.startPrank(user);
        
        // Create multiple requests with different timestamps
        AtomicRequest memory req1 = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6),
            offerAmount: uint96(1_000e6)
        });
        atomicQueue.updateAtomicRequest(boringVault, USDC, req1);
        
        vm.warp(block.timestamp + 10);
        
        AtomicRequest memory req2 = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6),
            offerAmount: uint96(2_000e6)
        });
        atomicQueue.updateAtomicRequest(boringVault, USDC, req2);
        
        // Verify both requests are stored correctly
        (bytes32[] memory requestIds, AtomicRequest[] memory requests) = atomicQueue.getWithdrawRequests();
        assertEq(requestIds.length, 2);
        assertEq(requests.length, 2);
        
        vm.stopPrank();
    }

    function testUpdateAtomicRequestBasic() external {
        vm.startPrank(user);
        
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6),
            offerAmount: uint96(1_000e6)
        });
        
        // Verify event emission
        vm.expectEmit(true, true, true, true);
        emit AtomicRequestUpdated(
            user,
            address(boringVault),
            address(USDC),
            1_000e6,
            req.deadline,
            req.atomicPrice,
            block.timestamp
        );
        
        atomicQueue.updateAtomicRequest(boringVault, USDC, req);
        
        // Verify request was stored
        bytes32 requestId = keccak256(abi.encode(
            user,
            address(boringVault),
            address(USDC),
            req
        ));
        AtomicRequest memory storedReq = atomicQueue.getAtomicRequest(requestId);
        assertEq(storedReq.deadline, req.deadline);
        assertEq(storedReq.creationTime, req.creationTime);
        assertEq(storedReq.atomicPrice, req.atomicPrice);
        assertEq(storedReq.offerAmount, req.offerAmount);
        
        vm.stopPrank();
    }

    function testCancelAtomicRequest() external {
        vm.startPrank(user);
        
        // First create a request
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6),
            offerAmount: uint96(1_000e6)
        });
        
        atomicQueue.updateAtomicRequest(boringVault, USDC, req);
        
        // Verify request exists
        (bytes32[] memory requestIdsBefore,) = atomicQueue.getWithdrawRequests();
        assertEq(requestIdsBefore.length, 1);
        
        // Cancel request
        vm.expectEmit(true, true, true, true);
        emit AtomicRequestCancelled(
            user,
            address(boringVault),
            address(USDC),
            req.offerAmount,
            req.deadline,
            req.atomicPrice,
            block.timestamp
        );
        
        atomicQueue.cancelAtomicRequest(boringVault, USDC, req);
        
        // Verify request was removed
        (bytes32[] memory requestIdsAfter,) = atomicQueue.getWithdrawRequests();
        assertEq(requestIdsAfter.length, 0);
        
        vm.stopPrank();
    }

    function testSolveRequest() external {
        vm.startPrank(user);
        
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.MATURITY_TIME() + 1), 
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6),
            offerAmount: uint96(1_000e6)
        });
        
        atomicQueue.updateAtomicRequest(boringVault, USDC, req);

        // Verify request was added
        (bytes32[] memory requestIds,) = atomicQueue.getWithdrawRequests();
        assertEq(requestIds.length, 1);
        
        // Setup solver
        address solver = address(atomicSolverV4);
        
        // Approve solver
        USDC.approve(solver, type(uint256).max);
        boringVault.approve(solver, type(uint256).max);
        
        // Warp past maturity time
        vm.warp(block.timestamp + atomicQueue.MATURITY_TIME() + 1);
        
        // Should emit event
        vm.expectEmit(true, true, true, true);
        emit AtomicRequestFulfilled(
            user,
            address(boringVault),
            address(USDC),
            req.offerAmount,
            req.atomicPrice * req.offerAmount / 1e6,
            block.timestamp
        );
        
        atomicSolverV4.redeemSelfSolve(
            atomicQueue,
            boringVault,
            USDC,
            user,
            0,
            type(uint256).max,
            teller,
            req
        );
        
        // Verify request was removed
        (requestIds,) = atomicQueue.getWithdrawRequests();
        assertEq(requestIds.length, 0);

        // check user balance
        assertEq(USDC.balanceOf(user), 1_000e6);
        assertEq(boringVault.balanceOf(user), 1_000_000_000e6 - 1_000e6);
        
        vm.stopPrank();
    }

    function testSolveRequestExpiredDeadline() external {
        vm.startPrank(user);
        
        // Create request with short deadline but after maturity time
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.MATURITY_TIME() + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6),
            offerAmount: uint96(1_000e6)
        });
        
        atomicQueue.updateAtomicRequest(boringVault, USDC, req);
        
        // Move time past maturity time and deadline
        vm.warp(block.timestamp + atomicQueue.MATURITY_TIME() + 2);
        
        // Setup solver
        address[] memory users = new address[](1);
        users[0] = user;
        
        // Expect revert on solve
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__RequestDeadlineExceeded.selector, user));
        atomicQueue.solve(boringVault, USDC, users, "", address(atomicSolverV4), req);
        
        vm.stopPrank();
    }

    function testSolveRequestZeroAmount() external {
        vm.startPrank(user);
        
        // Create request with zero amount but valid maturity time
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.MATURITY_TIME() + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6),
            offerAmount: 0
        });
        
        atomicQueue.updateAtomicRequest(boringVault, USDC, req);
        
        // Move time past maturity time
        vm.warp(block.timestamp + atomicQueue.MATURITY_TIME() + 1);
        
        // Setup solver
        address[] memory users = new address[](1);
        users[0] = user;
        
        // Expect revert on solve
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__ZeroOfferAmount.selector, user));
        atomicQueue.solve(boringVault, USDC, users, "", address(atomicSolverV4), req);
        
        vm.stopPrank();
    }

    function testSolveRequestBeforeMaturity() external {
        vm.startPrank(user);
        
        // Create request
        AtomicRequest memory req = AtomicRequest({
            deadline: uint64(block.timestamp + atomicQueue.MATURITY_TIME() + 1),
            creationTime: uint64(block.timestamp),
            atomicPrice: uint88(1e6),
            offerAmount: uint96(1_000e6)
        });
        
        atomicQueue.updateAtomicRequest(boringVault, USDC, req);
        
        // Try to solve before maturity time
        address[] memory users = new address[](1);
        users[0] = user;
        
        // Should revert because maturity time hasn't passed
        vm.expectRevert(abi.encodeWithSelector(AtomicQueue.AtomicQueue__RequestNotMature.selector, user));
        atomicQueue.solve(boringVault, USDC, users, "", address(atomicSolverV4), req);
        
        // Warp past maturity time
        vm.warp(block.timestamp + atomicQueue.MATURITY_TIME() + 1);
        
        // Now the solve should work
        USDC.approve(address(atomicSolverV4), type(uint256).max);
        boringVault.approve(address(atomicSolverV4), type(uint256).max);
        
        atomicSolverV4.redeemSelfSolve(
            atomicQueue,
            boringVault,
            USDC,
            user,
            0,
            type(uint256).max,
            teller,
            req
        );
        
        vm.stopPrank();
    }

    function testSetMaturityTime() external {
        uint256 newMaturityTime = 2 hours;
        
        // Should emit event with correct initial value (1 days)
        vm.expectEmit(true, true, true, true);
        emit MaturityTimeUpdated(1 days, newMaturityTime);
        
        // Set new maturity time
        atomicQueue.setMaturityTime(newMaturityTime);
        
        // Verify new value
        assertEq(atomicQueue.MATURITY_TIME(), newMaturityTime);
    }

    function testSetMaturityTimeUnauthorized() external {
        vm.prank(user);
        vm.expectRevert("UNAUTHORIZED");
        atomicQueue.setMaturityTime(2 hours);
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}