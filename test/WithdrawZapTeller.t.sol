// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";
import {WithdrawZapTeller} from "src/zaps/WithdrawZapTeller.sol";
import {Ownable2StepWTR} from "src/zaps/Ownable2StepWTR.sol";
import {PlumeAddresses} from "test/resources/PlumeAddresses.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";
import {WithdrawZapTeller, ZapAtomicRequest} from "src/zaps/WithdrawZapTeller.sol";
import {AtomicSolverV4} from "src/atomic-queue/AtomicSolverV4.sol";

contract WithdrawZapTellerTest is Test, PlumeAddresses {
    using SafeERC20 for ERC20;
    using stdStorage for StdStorage;

    WithdrawZapTeller public teller;

    address public owner = dev0Address;
    address public user1 = vm.addr(1);
    address public user2 = vm.addr(2);

    // Contract addresses from deployment
    address public constant SUPERUSD_ADDRESS = 0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB;
    address public constant SSUPERUSD_ADDRESS = 0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd;
    address public constant SUPERUSD_ATOMIC_QUEUE_ADDRESS = 0xf3aA6324Aa5C9Ded16Eb7ED651152aC30588BAc1;
    address public constant SSUPERUSD_ATOMIC_QUEUE_ADDRESS = 0xd484d2991D168b33cC61e25f80af0145883Bc465;
    address public constant SUPERUSD_TELLER_ADDRESS = 0xF62D61F304C9c65C96a94c2b0b93c8f93C96e91D;
    address public constant SSUPERUSD_TELLER_ADDRESS = 0xa8aA5c00d6c3f7A77FC5769770f6bC7b9244699b;
    address public constant ATOMIC_SOLVER_V4_ADDRESS = 0x1DB629316B3fB6B026f9ebD5c379a72235a4d5E9;

    ERC20 public pusd;
    ERC20 public superusd;
    ERC20 public ssuperusd;

    uint256 public constant WeiPerUsdc = 1_000_000; // 6 decimals
    uint256 public constant WeiPerSuperusd = 1_000_000; // 6 decimals
    uint256 public constant WeiPerSsuperusd = 1_000_000; // 6 decimals

    function setUp() external {
        // Setup forked environment for Plume
        string memory rpcKey = "PLUME_MAINNET_RPC_URL";
        uint256 blockNumber = 40901500;

        vm.createSelectFork(vm.envString(rpcKey), blockNumber);

        pusd = ERC20(PUSD);
        superusd = ERC20(SUPERUSD_ADDRESS);
        ssuperusd = ERC20(SSUPERUSD_ADDRESS);

        // Deploy the WithdrawZapTeller contract
        teller = new WithdrawZapTeller(owner, SUPERUSD_ADDRESS, SSUPERUSD_ADDRESS, SUPERUSD_ATOMIC_QUEUE_ADDRESS, SSUPERUSD_ATOMIC_QUEUE_ADDRESS, SUPERUSD_TELLER_ADDRESS, SSUPERUSD_TELLER_ADDRESS, ATOMIC_SOLVER_V4_ADDRESS);

        // Fund test users
        deal(address(pusd), user1, WeiPerUsdc * 1000);
        deal(address(pusd), user2, WeiPerUsdc * 1000);
        deal(address(ssuperusd), user1, WeiPerSsuperusd * 1000);
    }

    function testCannotDeployWithAddressZero() public {
        // address zero owner is allowed in this case, so we skip that test
        vm.expectRevert();
        new WithdrawZapTeller(owner, address(0), SSUPERUSD_ADDRESS, SUPERUSD_ATOMIC_QUEUE_ADDRESS, SSUPERUSD_ATOMIC_QUEUE_ADDRESS, SSUPERUSD_TELLER_ADDRESS, SUPERUSD_TELLER_ADDRESS, ATOMIC_SOLVER_V4_ADDRESS);

        vm.expectRevert();
        new WithdrawZapTeller(owner, SUPERUSD_ADDRESS, address(0), SUPERUSD_ATOMIC_QUEUE_ADDRESS, SSUPERUSD_ATOMIC_QUEUE_ADDRESS, SSUPERUSD_TELLER_ADDRESS, SUPERUSD_TELLER_ADDRESS, ATOMIC_SOLVER_V4_ADDRESS);

        vm.expectRevert();
        new WithdrawZapTeller(owner, SUPERUSD_ADDRESS, SSUPERUSD_ADDRESS, address(0), SSUPERUSD_ATOMIC_QUEUE_ADDRESS, SSUPERUSD_TELLER_ADDRESS, SUPERUSD_TELLER_ADDRESS, ATOMIC_SOLVER_V4_ADDRESS);

        vm.expectRevert();
        new WithdrawZapTeller(owner, SUPERUSD_ADDRESS, SSUPERUSD_ADDRESS, SUPERUSD_ATOMIC_QUEUE_ADDRESS, address(0), SSUPERUSD_TELLER_ADDRESS, SUPERUSD_TELLER_ADDRESS, ATOMIC_SOLVER_V4_ADDRESS);

        vm.expectRevert();
        new WithdrawZapTeller(owner, SUPERUSD_ADDRESS, SSUPERUSD_ADDRESS, SUPERUSD_ATOMIC_QUEUE_ADDRESS, SSUPERUSD_ATOMIC_QUEUE_ADDRESS, address(0), SUPERUSD_TELLER_ADDRESS, ATOMIC_SOLVER_V4_ADDRESS);

        vm.expectRevert();
        new WithdrawZapTeller(owner, SUPERUSD_ADDRESS, SSUPERUSD_ADDRESS, SUPERUSD_ATOMIC_QUEUE_ADDRESS, SSUPERUSD_ATOMIC_QUEUE_ADDRESS, SSUPERUSD_TELLER_ADDRESS, address(0), ATOMIC_SOLVER_V4_ADDRESS);

        vm.expectRevert();
        new WithdrawZapTeller(owner, SUPERUSD_ADDRESS, SSUPERUSD_ADDRESS, SUPERUSD_ATOMIC_QUEUE_ADDRESS, SSUPERUSD_ATOMIC_QUEUE_ADDRESS, SSUPERUSD_TELLER_ADDRESS, SUPERUSD_TELLER_ADDRESS, address(0));
    }

    function testCanDeployWithdrawZapTeller() public {
        // Already deployed in setUp, just verify it exists
        assertTrue(address(teller) != address(0), "Teller should be deployed");
    }

    function testStartsWithCorrectOwner() public {
        assertEq(teller.owner(), owner, "Owner should be set correctly");
    }

    function testStartsWithCorrectAddresses() public {
        assertEq(teller.superUSD(), SUPERUSD_ADDRESS, "SuperUSD address should be set correctly");
        assertEq(teller.sSuperUSD(), SSUPERUSD_ADDRESS, "sSuperUSD address should be set correctly");
        assertEq(address(teller.superUSDAtomicQueue()), SUPERUSD_ATOMIC_QUEUE_ADDRESS, "SuperUSD atomic queue address should be set correctly");
        assertEq(address(teller.sSuperUSDAtomicQueue()), SSUPERUSD_ATOMIC_QUEUE_ADDRESS, "sSuperUSD atomic queue address should be set correctly");
        assertEq(teller.sSuperUSDTeller(), SSUPERUSD_TELLER_ADDRESS, "sSuperUSD teller address should be set correctly");
        assertEq(teller.superUSDTeller(), SUPERUSD_TELLER_ADDRESS, "SuperUSD teller address should be set correctly");
        assertEq(address(teller.superUSDSolver()), ATOMIC_SOLVER_V4_ADDRESS, "AtomicSolverV4 address should be set correctly");
    }

    function testCannotWithdrawInvalidToken() public {
        vm.expectRevert();
        vm.prank(user1);
        teller.unstakeAndWithdraw(1, address(0), 1, uint64(block.timestamp + 3600));
    }

    function testCannotWithdrawAmountZero() public {
        vm.expectRevert();
        vm.prank(user1);
        teller.unstakeAndWithdraw(0, address(pusd), 1, uint64(block.timestamp + 3600));
    }

    function testCannotWithdrawWithInsufficientBalance() public {
        // User1 has no sSuperUSD tokens
        vm.expectRevert(); // ERC20: transfer amount exceeds balance
        vm.prank(user1);
        teller.unstakeAndWithdraw(WeiPerUsdc, address(pusd), 0, uint64(block.timestamp + 3600));
    }

    function testCanApproveSSuperusd() public {
        vm.prank(user1);
        ssuperusd.approve(address(teller), type(uint256).max);
        assertEq(ssuperusd.allowance(user1, address(teller)), type(uint256).max, "Allowance should be set");
    }

    function testCanUnstakeAndWithdrawAndSolve() public {
        deal(address(superusd), address(ssuperusd), WeiPerSuperusd * 1000);
        deal(address(pusd), address(superusd), WeiPerUsdc * 1000);
        uint256 unstakeAmount = 1e6;
        uint256 minimumAssetsOut = 1.05 * 1e6; // price
        vm.startPrank(user1);
        ssuperusd.approve(address(teller), type(uint256).max);
        bytes32 requestId = teller.unstakeAndWithdraw(WeiPerSsuperusd, address(pusd), minimumAssetsOut, uint64(block.timestamp +  AtomicQueue(SUPERUSD_ATOMIC_QUEUE_ADDRESS).maturityTime() * 2));
        vm.stopPrank();

        vm.warp(block.timestamp + AtomicQueue(SUPERUSD_ATOMIC_QUEUE_ADDRESS).maturityTime() + 1);

        // Get the zap request from the teller
        (bytes32[] memory requestIds, ZapAtomicRequest[] memory requests) = teller.getZapExistingWithdrawRequestsByUser(user1);
        assertEq(requestIds.length, 1, "Should have one request");
        ZapAtomicRequest memory zapReq = requests[0];
        assertEq(zapReq.sender, user1, "Sender should be user1");

        // Solve using the new solveByZap function
        teller.solveByZap(zapReq);

        // Check that user1 received the tokens
        assertGt(pusd.balanceOf(user1), 0, "User should have received PUSD tokens");
    }

    function testGetZapExistingWithdrawRequestsByUser() public {
        deal(address(superusd), address(ssuperusd), WeiPerSuperusd * 1000);
        deal(address(pusd), address(superusd), WeiPerUsdc * 1000);

        vm.startPrank(user1);
        ssuperusd.approve(address(teller), type(uint256).max);

        // Create a request
        bytes32 requestId1 = teller.unstakeAndWithdraw(WeiPerSsuperusd, address(pusd), 0, uint64(block.timestamp + 3600));

        // Get requests for user1
        (bytes32[] memory requestIds, ZapAtomicRequest[] memory requests) = teller.getZapExistingWithdrawRequestsByUser(user1);
        assertEq(requestIds.length, 1, "Should have one request for user1");
        assertEq(requests.length, 1, "Should have one request for user1");
        assertEq(requests[0].sender, user1, "Request sender should be user1");

        vm.stopPrank();
    }

    function testCancelByZap() public {
        deal(address(superusd), address(ssuperusd), WeiPerSuperusd * 1000);

        vm.startPrank(user1);
        ssuperusd.approve(address(teller), type(uint256).max);
        bytes32 requestId = teller.unstakeAndWithdraw(WeiPerSsuperusd, address(pusd), 0, uint64(block.timestamp + 3600));
        uint256 userSSuperUSDBalanceBefore = ssuperusd.balanceOf(user1);
        // Get the request
        (bytes32[] memory requestIds, ZapAtomicRequest[] memory requests) = teller.getZapExistingWithdrawRequestsByUser(user1);
        assertEq(requestIds.length, 1, "Should have one request");

        // Cancel the request
        teller.cancelByZap(requests[0]);

        // Check that request was removed
        (requestIds, requests) = teller.getZapExistingWithdrawRequestsByUser(user1);
        assertEq(requestIds.length, 0, "Should have no requests after cancel");

        assertGt(ssuperusd.balanceOf(user1), userSSuperUSDBalanceBefore, "User1 should have received sSuperUSD back");
        vm.stopPrank();
    }

    function testCannotCancelByZapUnauthorized() public {
        deal(address(superusd), address(ssuperusd), WeiPerSuperusd * 1000);

        vm.startPrank(user1);
        ssuperusd.approve(address(teller), type(uint256).max);
        bytes32 requestId = teller.unstakeAndWithdraw(WeiPerSsuperusd, address(pusd), 0, uint64(block.timestamp + 3600));

        // Get the request
        (bytes32[] memory requestIds, ZapAtomicRequest[] memory requests) = teller.getZapExistingWithdrawRequestsByUser(user1);
        vm.stopPrank();
        // Try to cancel from user2 (should fail)
        vm.prank(user2);
        vm.expectRevert(WithdrawZapTeller.UnauthorizedZapCancellation.selector);
        teller.cancelByZap(requests[0]);
        vm.stopPrank();
    }

    function testCancelZapAtomicRequestByAdmin() public {
        deal(address(superusd), address(ssuperusd), WeiPerSuperusd * 1000);

        vm.startPrank(user1);
        ssuperusd.approve(address(teller), type(uint256).max);
        bytes32 requestId = teller.unstakeAndWithdraw(WeiPerSsuperusd, address(pusd), 0, uint64(block.timestamp + 3600));

        // Get the request
        (bytes32[] memory requestIds, ZapAtomicRequest[] memory requests) = teller.getZapExistingWithdrawRequestsByUser(user1);
        assertEq(requestIds.length, 1, "Should have one request");
        vm.stopPrank();
        // Cancel by admin
        vm.prank(owner);
        teller.cancelZapAtomicRequestByAdmin(requests);

        // Check that request was removed
        (requestIds, requests) = teller.getZapExistingWithdrawRequestsByUser(user1);
        assertEq(requestIds.length, 0, "Should have no requests after admin cancel");
        vm.stopPrank();
    }

    function testGetExistingZapWithdrawRequestIds() public {
        deal(address(superusd), address(ssuperusd), WeiPerSuperusd * 1000);
        deal(address(pusd), address(superusd), WeiPerUsdc * 1000);

        vm.startPrank(user1);
        ssuperusd.approve(address(teller), type(uint256).max);

        // Create multiple requests
        bytes32 requestId1 = teller.unstakeAndWithdraw(WeiPerSsuperusd, address(pusd), 0, uint64(block.timestamp + 3600));
        bytes32 requestId2 = teller.unstakeAndWithdraw(WeiPerSsuperusd * 2, address(pusd), 0, uint64(block.timestamp + 3600));

        // Get all existing request IDs
        bytes32[] memory requestIds = teller.getExistingZapWithdrawRequestIds();
        assertEq(requestIds.length, 2, "Should have two requests");

        // Verify the request IDs match what we created
        assertEq(requestIds[0], requestId1, "First request ID should match");
        assertEq(requestIds[1], requestId2, "Second request ID should match");

        vm.stopPrank();
    }

    function testGetExistingZapWithdrawRequests() public {
        deal(address(superusd), address(ssuperusd), WeiPerSuperusd * 1000);
        deal(address(pusd), address(superusd), WeiPerUsdc * 1000);

        vm.startPrank(user1);
        ssuperusd.approve(address(teller), type(uint256).max);

        // Create a request
        bytes32 requestId = teller.unstakeAndWithdraw(WeiPerSsuperusd, address(pusd), 0, uint64(block.timestamp + 3600));

        // Get all existing requests
        (bytes32[] memory requestIds, ZapAtomicRequest[] memory requests) = teller.getExistingZapWithdrawRequests();
        assertEq(requestIds.length, 1, "Should have one request");
        assertEq(requests.length, 1, "Should have one request");
        assertEq(requests[0].sender, user1, "Request sender should be user1");
        assertEq(requests[0].offer, SUPERUSD_ADDRESS, "Request offer should be superUSD");
        assertEq(requests[0].want, address(pusd), "Request want should be PUSD");

        vm.stopPrank();
    }

    function testGetZapAtomicRequestById() public {
        deal(address(superusd), address(ssuperusd), WeiPerSuperusd * 1000);
        deal(address(pusd), address(superusd), WeiPerUsdc * 1000);

        vm.startPrank(user1);
        ssuperusd.approve(address(teller), type(uint256).max);

        // Create a request
        uint256 offerAmount = WeiPerSsuperusd;
        uint256 minimumAssetsOut = 0;
        uint64 deadline = uint64(block.timestamp + 3600);
        bytes32 requestId = teller.unstakeAndWithdraw(offerAmount, address(pusd), minimumAssetsOut, deadline);

        // Get the specific request by ID
        ZapAtomicRequest memory request = teller.getZapAtomicRequestById(requestId);
        assertEq(request.sender, user1, "Request sender should be user1");
        assertEq(request.user, address(teller), "Request user should be the teller contract");
        assertEq(request.minimumAssetsOut, minimumAssetsOut, "Request minimum assets out should match");
        assertEq(request.offer, SUPERUSD_ADDRESS, "Request offer should be superUSD");
        assertEq(request.want, address(pusd), "Request want should be PUSD");
        assertEq(request.deadline, deadline, "Request deadline should match");

        vm.stopPrank();
    }

    function testGetZapAtomicRequestByIdNonExistent() public {
        // Try to get a non-existent request (should return empty/default struct)
        bytes32 nonExistentId = keccak256("non-existent");
        ZapAtomicRequest memory request = teller.getZapAtomicRequestById(nonExistentId);
        
        // Since it's a mapping, non-existent entries return default values
        assertEq(request.sender, address(0), "Non-existent request sender should be zero");
        assertEq(request.user, address(0), "Non-existent request user should be zero");
        assertEq(request.offerAmount, 0, "Non-existent request offer amount should be zero");
    }
}
