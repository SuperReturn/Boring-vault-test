// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2StepWTR } from "./Ownable2StepWTR.sol";
import { AtomicQueue, AtomicRequest } from "./../atomic-queue/AtomicQueue.sol";
import { AtomicSolverV4 } from "./../atomic-queue/AtomicSolverV4.sol";
import { TellerWithMultiAssetSupport } from "./../base/Roles/TellerWithMultiAssetSupport.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";

/// @notice Stores zap request information needed to fulfill a users atomic request.
/// @param deadline unix timestamp for when request is no longer valid
/// @param creationTime timestamp when request was created
/// @param offerAmount the amount of `offer` asset the user wants converted to `want` asset
/// @param minimumAssetsOut the minimum amount of want assets to receive
/// @param user The address of the zapper contract (this contract)
/// @param sender The original address that initiated the request
/// @param offer The address of the offer token
/// @param want The address of the want token
struct ZapAtomicRequest {
    uint64 deadline; // deadline to fulfill request
    uint64 creationTime; // timestamp when request was created
    uint96 offerAmount; // The amount of offer asset the zapper wants to sell.
    uint256 minimumAssetsOut; // The minimum amount of want assets to receive
    address user; // The address of the zapper contract
    address sender; // The original sender who initiated the request
    address offer; // The address of the offer token
    address want; // The address of the want token
}

/// @title WithdrawZapTeller
/// @author SuperFi Labs
/// @notice A teller that helps convert sSuperUSD to base assets by bundling instantWithdraw and updateAtomicRequest operations.
contract WithdrawZapTeller is Ownable2StepWTR, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /***************************************
    CONSTANTS
    ***************************************/

    /// @notice The address of the superUSD AtomicQueue contract
    AtomicQueue public immutable superUSDAtomicQueue;
    
    /// @notice The address of the sSuperUSD AtomicQueue contract
    AtomicQueue public immutable sSuperUSDAtomicQueue;

    /// @notice The address of the SuperUSD token contract
    address public immutable superUSD;

    /// @notice The address of the sSuperUSD token contract
    address public immutable sSuperUSD;

    /// @notice The address of the SuperUSD teller contract
    address public immutable superUSDTeller;

    /// @notice The address of the sSuperUSD teller contract
    address public immutable sSuperUSDTeller;

    /// @notice The address of the AtomicSolverV4 contract
    AtomicSolverV4 public immutable superUSDSolver;

    /***************************************
    STORAGE
    ***************************************/

    /// @notice The set of zap request Ids currently in the zapper.
    /// @dev Requests are removed when solve or cancel is called.
    EnumerableSet.Bytes32Set internal _existingZapWithdrawRequests;

    /// @notice Mapping of zap request Ids to ZapAtomicRequests.
    /// @dev Requests won't be removed when solve or cancel is called.
    mapping(bytes32 => ZapAtomicRequest) internal zapWithdraws;

    /***************************************
    ERRORS
    ***************************************/

    /// @notice Thrown when inputting an invalid address
    error InvalidAddress();

    /// @notice Thrown when a zap request is not found
    error ZapRequestNotFound();

    /// @notice Thrown when user tries to cancel a request they didn't create
    error UnauthorizedZapCancellation();

    /// @notice Thrown when the deadline for a zap request is in the past
    error InvalidDeadline();

    /// @notice Thrown when no tokens are received after solving a zap request
    error NoTokensReceived();

    /***************************************
    EVENTS
    ***************************************/

    /// @notice Emitted when a zap withdraw request is created
    /// @param requestId The ID of the zap request
    /// @param sender The address that initiated the request
    /// @param sSuperUSDAmount The amount of sSuperUSD unstaked
    /// @param superUSDAmount The amount of superUSD received
    /// @param offer The offer token address
    /// @param want The want token address
    /// @param deadline The deadline for the request
    event ZapWithdrawRequestCreated(
        bytes32 indexed requestId,
        address indexed sender,
        uint256 sSuperUSDAmount,
        uint256 superUSDAmount,
        address offer,
        address want,
        uint64 deadline
    );

    /// @notice Emitted when a zap withdraw request is cancelled
    /// @param requestId The ID of the cancelled zap request
    /// @param sender The address that initiated the request
    /// @param offerAmount The amount of offer tokens returned
    /// @param offer The offer token address
    /// @param want The want token address
    event ZapWithdrawRequestCancelled(
        bytes32 indexed requestId,
        address indexed sender,
        uint256 offerAmount,
        address offer,
        address want
    );

    /// @notice Emitted when a zap withdraw request is solved
    /// @param requestId The ID of the solved zap request
    /// @param sender The address that initiated the request
    /// @param offerAmount The amount of offer tokens spent
    /// @param wantAmount The amount of want tokens received
    /// @param offer The offer token address
    /// @param want The want token address
    event ZapWithdrawRequestSolved(
        bytes32 indexed requestId,
        address indexed sender,
        uint256 offerAmount,
        uint256 wantAmount,
        address offer,
        address want
    );

    /***************************************
    CONSTRUCTOR
    ***************************************/

    /// @notice Constructs the WithdrawZapTeller contract.
    /// @param initialOwner The initial owner of the contract.
    /// @param superUSD_ The address of the superUSD token contract.
    /// @param sSuperUSD_ The address of the sSuperUSD token contract.
    /// @param superUSDAtomicQueue_ The address of the SuperUSD AtomicQueue contract.
    /// @param sSuperUSDAtomicQueue_ The address of the sSuperUSD AtomicQueue contract.
    /// @param sSuperUSDTeller_ The address of the sSuperUSD teller contract.
    /// @param superUSDTeller_ The address of the SuperUSD teller contract.
    /// @param atomicSolver_ The address of the AtomicSolverV4 contract.
    constructor(
        address initialOwner,
        address superUSD_,
        address sSuperUSD_,
        address superUSDAtomicQueue_,
        address sSuperUSDAtomicQueue_,
        address superUSDTeller_,
        address sSuperUSDTeller_,
        address atomicSolver_
    ) Ownable2StepWTR(initialOwner) {
        // checks
        if(
            (initialOwner == address(0)) ||
            (superUSD_ == address(0)) ||
            (sSuperUSD_ == address(0)) ||
            (superUSDAtomicQueue_ == address(0)) ||
            (sSuperUSDAtomicQueue_ == address(0)) ||
            (sSuperUSDTeller_ == address(0)) ||
            (superUSDTeller_ == address(0)) ||
            (atomicSolver_ == address(0))
        ) revert InvalidAddress();
        // set
        superUSDAtomicQueue = AtomicQueue(superUSDAtomicQueue_);
        sSuperUSDAtomicQueue = AtomicQueue(sSuperUSDAtomicQueue_);
        superUSD = superUSD_;
        sSuperUSD = sSuperUSD_;
        superUSDTeller = superUSDTeller_;
        sSuperUSDTeller = sSuperUSDTeller_;
        superUSDSolver = AtomicSolverV4(atomicSolver_);
        // pre approve sSuperUSD to sSuperUSD atomic queue
        SafeERC20.forceApprove(IERC20(sSuperUSD_), address(sSuperUSDAtomicQueue), type(uint256).max);
        // pre approve superUSD to superUSD atomic queue
        SafeERC20.forceApprove(IERC20(superUSD_), address(superUSDAtomicQueue), type(uint256).max);
        // pre approve superUSD to sSuperUSD vault (needed for deposits via teller)
        SafeERC20.forceApprove(IERC20(superUSD_), sSuperUSD, type(uint256).max);
    }

    /***************************************
    VIEW FUNCTIONS
    ***************************************/

    /// @notice Get all existing zap withdraw request Ids currently in the zapper.
    /// @dev Includes requests that are not mature, matured, and expired. But does not include requests that have been solved.
    /// @return requestIds The request Ids.
    function getExistingZapWithdrawRequestIds() public view returns (bytes32[] memory) {
        return _existingZapWithdrawRequests.values();
    }

    /// @notice Get all existing zap withdraw requests.
    /// @dev Includes requests that are not mature, matured, and expired. But does not include requests that have been solved.
    function getExistingZapWithdrawRequests()
        external
        view
        returns (bytes32[] memory requestIds, ZapAtomicRequest[] memory requests)
    {
        requestIds = getExistingZapWithdrawRequestIds();
        uint256 requestsLength = requestIds.length;
        requests = new ZapAtomicRequest[](requestsLength);
        for (uint256 i = 0; i < requestsLength; ) {
            requests[i] = zapWithdraws[requestIds[i]];
            unchecked { ++i; }
        }
    }

    /// @notice Get all existing zap withdraw requests by sender.
    /// @dev Includes requests that are not mature, matured, and expired. But does not include requests that have been solved.
    /// @param sender The address of the sender.
    /// @return requestIds The request Ids.
    /// @return requests The requests.
    function getZapExistingWithdrawRequestsByUser(address sender)
        external
        view
        returns (bytes32[] memory requestIds, ZapAtomicRequest[] memory requests)
    {
        bytes32[] memory allExistingZapWithdrawRequestIds = _existingZapWithdrawRequests.values();
        uint256 allExistingZapWithdrawRequestsLength = allExistingZapWithdrawRequestIds.length;

        // Create arrays with maximum possible size
        requestIds = new bytes32[](allExistingZapWithdrawRequestsLength);
        requests = new ZapAtomicRequest[](allExistingZapWithdrawRequestsLength);

        // Single pass: populate arrays conditionally
        uint256 count = 0;
        for (uint256 i = 0; i < allExistingZapWithdrawRequestsLength; ) {
            bytes32 requestId = allExistingZapWithdrawRequestIds[i];
            ZapAtomicRequest memory request = zapWithdraws[requestId];
            if (request.sender == sender) {
                requestIds[count] = requestId;
                requests[count] = request;
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }

        // Trim arrays to correct length using assembly
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(requestIds, count)
            mstore(requests, count)
        }
    }

    /// @notice Get a zap withdraw request by request Id.
    /// @dev Does verify nonce is non-zero.
    /// @param requestId The request Id.
    /// @return request The request.
    function getZapAtomicRequestById(bytes32 requestId) public view returns (ZapAtomicRequest memory) {
        return zapWithdraws[requestId];
    }

    /***************************************
    WITHDRAW FUNCTIONS
    ***************************************/

    /// @notice Unstakes sSuperUSD and withdraws to a base asset in a single transaction.
    /// @param sSuperUSDAmount The amount of sSuperUSD to unstake.
    /// @param wantAsset The base asset to withdraw to.
    /// @param minimumAssetsOut The minimum amount of base assets to receive.
    /// @param deadline The deadline for the atomic request.
    /// @return requestId The ID of the zap atomic request created.
    function unstakeAndWithdraw(
        uint256 sSuperUSDAmount,
        address wantAsset,
        uint256 minimumAssetsOut,
        uint64 deadline
    ) public nonReentrant returns (bytes32 requestId) {
        // Add deadline validation
        if (deadline <= block.timestamp) revert InvalidDeadline();
        
        // Add wantAsset validation
        if (wantAsset == address(0)) revert InvalidAddress();

        // transfer sSuperUSD from user to this contract
        SafeERC20.safeTransferFrom(IERC20(sSuperUSD), msg.sender, address(this), sSuperUSDAmount);

        // call instantWithdraw on sSuperUSD to get superUSD
        uint256 superUSDAmount = sSuperUSDAtomicQueue.instantWithdraw(
            ERC20(sSuperUSD),
            ERC20(superUSD),
            sSuperUSDAmount,
            0,
            TellerWithMultiAssetSupport(sSuperUSDTeller)
        );

        // create zap atomic request to convert superUSD to base asset
        ZapAtomicRequest memory zapRequest = ZapAtomicRequest({
            deadline: deadline,
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(superUSDAmount),
            minimumAssetsOut: minimumAssetsOut,
            user: address(this), // the zapper contract is the user for the atomic request
            sender: msg.sender, // the original sender who initiated the request
            offer: superUSD,
            want: wantAsset
        });

        // store the zap request
        requestId = keccak256(abi.encode(zapRequest));
        _existingZapWithdrawRequests.add(requestId);
        zapWithdraws[requestId] = zapRequest;

        // create atomic request to convert superUSD to base asset
        AtomicRequest memory userRequest = AtomicRequest({
            deadline: deadline,
            creationTime: uint64(block.timestamp),
            offerAmount: uint96(superUSDAmount),
            user: address(this), // the zapper contract is the user for the atomic request
            offer: superUSD,
            want: wantAsset
        });

        // call updateAtomicRequest to create the withdrawal request
        superUSDAtomicQueue.updateAtomicRequest(userRequest);

        // emit event for zap request creation
        emit ZapWithdrawRequestCreated(
            requestId,
            msg.sender,
            sSuperUSDAmount,
            superUSDAmount,
            superUSD,
            wantAsset,
            deadline
        );
    }

    /// @notice Allows a sender to cancel their zap atomic request.
    /// @param zapRequest The zap request to cancel.
    function cancelByZap(ZapAtomicRequest calldata zapRequest) external nonReentrant {
        if (zapRequest.sender != msg.sender) revert UnauthorizedZapCancellation();

        bytes32 requestId = keccak256(abi.encode(zapRequest));
        if (!_existingZapWithdrawRequests.contains(requestId)) revert ZapRequestNotFound();

        // Remove from zap storage
        _existingZapWithdrawRequests.remove(requestId);

        // Create corresponding AtomicRequest to cancel in the queue
        AtomicRequest memory atomicRequest = AtomicRequest({
            deadline: zapRequest.deadline,
            creationTime: zapRequest.creationTime,
            offerAmount: zapRequest.offerAmount,
            user: zapRequest.user,
            offer: zapRequest.offer,
            want: zapRequest.want
        });

        // Cancel the atomic request in the queue
        superUSDAtomicQueue.cancelAtomicRequest(atomicRequest);

        uint256 balanceBefore = IERC20(sSuperUSD).balanceOf(address(this));

        // Stake the superUSD to get sSuperUSD
        TellerWithMultiAssetSupport(sSuperUSDTeller).deposit(ERC20(zapRequest.offer), zapRequest.offerAmount, 0);

        uint256 sSuperUSDAmount = IERC20(sSuperUSD).balanceOf(address(this)) - balanceBefore;

        // Transfer sSuperUSD back to the original sender
        SafeERC20.safeTransfer(IERC20(sSuperUSD), zapRequest.sender, sSuperUSDAmount);

        // emit event for zap request cancellation
        emit ZapWithdrawRequestCancelled(
            requestId,
            zapRequest.sender,
            sSuperUSDAmount,
            zapRequest.offer,
            zapRequest.want
        );
    }

    /// @notice Allows the admin to cancel multiple zap withdraw requests.
    /// @dev Callable by owner only.
    /// @param zapRequests The array of zap requests to cancel.
    function cancelZapAtomicRequestByAdmin(ZapAtomicRequest[] calldata zapRequests) external onlyOwner nonReentrant {
        for (uint256 i = 0; i < zapRequests.length; ++i) {
            ZapAtomicRequest calldata zapRequest = zapRequests[i];
            bytes32 requestId = keccak256(abi.encode(zapRequest));
            if (!_existingZapWithdrawRequests.contains(requestId)) revert ZapRequestNotFound();

            // Remove from zap storage
            _existingZapWithdrawRequests.remove(requestId);

            // Create corresponding AtomicRequest to cancel in the queue
            AtomicRequest memory atomicRequest = AtomicRequest({
                deadline: zapRequest.deadline,
                creationTime: zapRequest.creationTime,
                offerAmount: zapRequest.offerAmount,
                user: zapRequest.user,
                offer: zapRequest.offer,
                want: zapRequest.want
            });

            // Cancel the atomic request in the queue
            superUSDAtomicQueue.cancelAtomicRequest(atomicRequest);

            uint256 balanceBefore = IERC20(sSuperUSD).balanceOf(address(this));

            // Stake the superUSD to get sSuperUSD
            TellerWithMultiAssetSupport(sSuperUSDTeller).deposit(ERC20(zapRequest.offer), zapRequest.offerAmount, 0);

            uint256 sSuperUSDAmount = IERC20(sSuperUSD).balanceOf(address(this)) - balanceBefore;

            // Transfer superUSD back to the original sender
            SafeERC20.safeTransfer(IERC20(sSuperUSD), zapRequest.sender, sSuperUSDAmount);

            // emit event for each cancelled zap request
            emit ZapWithdrawRequestCancelled(
                requestId,
                zapRequest.sender,
                sSuperUSDAmount,
                zapRequest.offer,
                zapRequest.want
            );
        }
    }

    /// @notice Called by solvers to exchange offer asset for want asset for zap requests.
    /// @param zapRequest The zap atomic request to solve.
    function solveByZap(ZapAtomicRequest calldata zapRequest) external nonReentrant {
        bytes32 requestId = keccak256(abi.encode(zapRequest));
        if (!_existingZapWithdrawRequests.contains(requestId)) revert ZapRequestNotFound();

        // Remove from zap storage
        _existingZapWithdrawRequests.remove(requestId);

        // Create corresponding AtomicRequest to solve in the queue
        AtomicRequest memory atomicRequest = AtomicRequest({
            deadline: zapRequest.deadline,
            creationTime: zapRequest.creationTime,
            offerAmount: zapRequest.offerAmount,
            user: zapRequest.user,
            offer: zapRequest.offer,
            want: zapRequest.want
        });

        // Record balance before redeemSolve
        uint256 balanceBefore = IERC20(zapRequest.want).balanceOf(address(this));

        // Call redeemSolve instead of queue.solve
        superUSDSolver.redeemSolve(
            superUSDAtomicQueue,
            zapRequest.minimumAssetsOut,
            type(uint256).max, // maxAssets - allow unlimited since this is solving our own request
            TellerWithMultiAssetSupport(superUSDTeller),
            atomicRequest
        );

        // Get the amount of want tokens received (difference from before)
        uint256 balanceAfter = IERC20(zapRequest.want).balanceOf(address(this));
        uint256 wantAmount = balanceAfter - balanceBefore;

        if (wantAmount == 0) revert NoTokensReceived();

        // Transfer want assets from this contract to the original sender
        SafeERC20.safeTransfer(IERC20(zapRequest.want), zapRequest.sender, wantAmount);

        // emit event for zap request solution
        emit ZapWithdrawRequestSolved(
            requestId,
            zapRequest.sender,
            zapRequest.offerAmount,
            wantAmount,
            zapRequest.offer,
            zapRequest.want
        );
    }
}