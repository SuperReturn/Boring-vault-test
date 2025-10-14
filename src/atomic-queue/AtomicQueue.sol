// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "@solmate/utils/ReentrancyGuard.sol";
import {IAtomicSolver} from "./IAtomicSolver.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";

/**
 * @notice Stores request information needed to fulfill a users atomic request.
 * @param deadline unix timestamp for when request is no longer valid
 * @param atomicPrice the price in terms of `want` asset the user wants their `offer` assets "sold" at
 * @dev atomicPrice MUST be in terms of `want` asset decimals.
 * @param offerAmount the amount of `offer` asset the user wants converted to `want` asset
 */
struct AtomicRequest {
    uint64 deadline; // deadline to fulfill request
    uint64 creationTime; // timestamp when request was created
    uint88 atomicPrice; // In terms of want asset decimals
    uint96 offerAmount; // The amount of offer asset the user wants to sell.
}

contract AtomicQueue is ReentrancyGuard, Auth {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // ========================================= GLOBAL STATE =========================================
    EnumerableSet.Bytes32Set private _withdrawRequests;

    uint256 public MATURITY_TIME = 1 days;

    /**
     * @notice Mapping of request Ids to AtomicRequests.
     */
    mapping(bytes32 => AtomicRequest) internal onChainWithdraws;

    mapping(ERC20 => uint256) public withdrawInProgressAmount;

    /**
     * @notice Mapping to track whitelisted addresses.
     */
    mapping(address => bool) public whitelist;

    /**
     * @notice The divisor used to reduce maturity time for whitelisted users.
     */
    uint256 public whitelistMaturityDivisor = 10;

    //============================== ERRORS ===============================

    error AtomicQueue__RequestDeadlineExceeded(address user);
    error AtomicQueue__ZeroOfferAmount(address user);
    error AtomicQueue__RequestNotMature(address user);
    error BoringOnChainQueue__BadWhitelistDivisor();

    //============================== EVENTS ===============================
    /**
     * @notice Emitted when `setMaturityTime` is called.
     */
    event MaturityTimeUpdated(uint256 oldMaturityTime, uint256 newMaturityTime);

    /**
     * @notice Emitted when `updateAtomicRequest` is called.
     */
    event AtomicRequestUpdated(
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 amount,
        uint256 deadline,
        uint256 minPrice,
        uint256 timestamp
    );

    /**
     * @notice Emitted when `solve` exchanges a users offer asset for their want asset.
     */
    event AtomicRequestFulfilled(
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 offerAmountSpent,
        uint256 wantAmountReceived,
        uint256 timestamp
    );

    /**
     * @notice Emitted when `cancelAtomicRequest` is called.
     */
    event AtomicRequestCancelled(
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 amount,
        uint256 deadline,
        uint256 minPrice,
        uint256 timestamp
    );

    event WhitelistAdded(address indexed user);

    event WhitelistRemoved(address indexed user);

    event WhitelistMaturityDivisorUpdated(uint256 newDivisor);

    //============================== IMMUTABLES ===============================

    /**
     * @notice Constructor
     * @param _owner The owner of the contract
     * @param _authority The authority of the contract
     */
    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    //============================== ADMIN FUNCTIONS ===============================

    /**
     * @notice Allows the owner to update the maturity time
     * @param newMaturityTime The new maturity time in seconds
     */
    function setMaturityTime(uint256 newMaturityTime) external requiresAuth {
        uint256 oldMaturityTime = MATURITY_TIME;
        MATURITY_TIME = newMaturityTime;
        emit MaturityTimeUpdated(oldMaturityTime, newMaturityTime);
    }

    //============================== USER FUNCTIONS ===============================

    function getTotalWithdrawInProgressAmount(address offer) external view returns (uint256) {
        return withdrawInProgressAmount[ERC20(offer)];
    }

    /**
     * @notice Add an address to the whitelist.
     * @dev Callable by MULTISIG_ROLE.
     * @param user The address to add to the whitelist.
     */
    function addToWhitelist(address user) external requiresAuth {
        whitelist[user] = true;
        emit WhitelistAdded(user);
    }

    /**
     * @notice Remove an address from the whitelist.
     * @dev Callable by MULTISIG_ROLE.
     * @param user The address to remove from the whitelist.
     */
    function removeFromWhitelist(address user) external requiresAuth {
        whitelist[user] = false;
        emit WhitelistRemoved(user);
    }

    /**
     * @notice Update the whitelist maturity divisor.
     * @dev Callable by MULTISIG_ROLE.
     * @param newDivisor The new divisor value.
     */
    function updateWhitelistMaturityDivisor(uint256 newDivisor) external requiresAuth {
        require(newDivisor > 0, "Divisor must be greater than 0");
        whitelistMaturityDivisor = newDivisor;
        emit WhitelistMaturityDivisorUpdated(newDivisor);
    }

    //============================== VIEW FUNCTIONS ===============================
    /**
     * @notice Get all request Ids currently in the queue.
     * @dev Includes requests that are not mature, matured, and expired. But does not include requests that have been solved.
     * @return requestIds The request Ids.
     */
    function getRequestIds() public view returns (bytes32[] memory) {
        return _withdrawRequests.values();
    }

    /**
     * @notice Get all withdraw requests.
     * @dev Includes requests that are not mature, matured, and expired. But does not include requests that have been solved.
     * @dev Does not verify nonce is zero, as you could have not been tracking withdraws for a period of time.
     * @dev If withdraws are made when not tracking, they will show up as empty requests here.
     */
    function getWithdrawRequests()
        external
        view
        returns (bytes32[] memory requestIds, AtomicRequest[] memory requests)
    {
        requestIds = getRequestIds();
        uint256 requestsLength = requestIds.length;
        requests = new AtomicRequest[](requestsLength);
        for (uint256 i = 0; i < requestsLength; ++i) {
            requests[i] = onChainWithdraws[requestIds[i]];
        }
    }

    /**
     * @notice Get a withdraw request.
     * @dev Does verify nonce is non-zero.
     * @param requestId The request Id.
     * @return request The request.
     */
    function getAtomicRequest(bytes32 requestId) public view returns (AtomicRequest memory) {
        return onChainWithdraws[requestId];
    }

    //============================== HELPER FUNCTIONS ===============================

    /**
     * @notice Helper function that returns either
     *         true: Withdraw request is valid.
     *         false: Withdraw request is not valid.
     * @dev It is possible for a withdraw request to return false from this function, but using the
     *      request in `updateAtomicRequest` will succeed, but solvers will not be able to include
     *      the user in `solve` unless some other state is changed.
     * @param offer the ERC0 token they want to exchange for the want
     * @param user the address of the user making the request
     * @param userRequest the request struct to validate
     */
    function isAtomicRequestValid(ERC20 offer, address user, AtomicRequest calldata userRequest)
        external
        view
        returns (bool)
    {
        // Validate amount.
        if (userRequest.offerAmount > offer.balanceOf(user)) return false;
        // Validate deadline.
        if (block.timestamp > userRequest.deadline) return false;
        // Validate approval.
        if (offer.allowance(user, address(this)) < userRequest.offerAmount) return false;
        // Validate offerAmount is nonzero.
        if (userRequest.offerAmount == 0) return false;
        // Validate atomicPrice is nonzero.
        if (userRequest.atomicPrice == 0) return false;

        return true;
    }

    /**
     * @notice Allows user to add/update their withdraw request.
     * @notice It is possible for a withdraw request with a zero atomicPrice to be made, and solved.
     *         If this happens, users will be selling their shares for no assets in return.
     *         To determine a safe atomicPrice, share.previewRedeem should be used to get
     *         a good share price, then the user can lower it from there to make their request fill faster.
     * @param offer the ERC20 token the user is offering in exchange for the want
     * @param want the ERC20 token the user wants in exchange for offer
     * @param userRequest the users request
     */
    function updateAtomicRequest(ERC20 offer, ERC20 want, AtomicRequest calldata userRequest) external nonReentrant {
        withdrawInProgressAmount[offer] += userRequest.offerAmount;

        bytes32 requestId = keccak256(abi.encode(msg.sender, address(offer), address(want), userRequest));

        _withdrawRequests.add(requestId);
        onChainWithdraws[requestId] = userRequest;

        emit AtomicRequestUpdated(
            msg.sender,
            address(offer),
            address(want),
            userRequest.offerAmount,
            userRequest.deadline,
            userRequest.atomicPrice,
            block.timestamp
        );
    }

    /**
     * @notice Allows user to cancel their withdraw request.
     * @param offer the ERC20 token the user is offering in exchange for the want
     * @param want the ERC20 token the user wants in exchange for offer
     * @param userRequest the users request
     */
    function cancelAtomicRequest(ERC20 offer, ERC20 want, AtomicRequest calldata userRequest) external {
        bytes32 requestId = keccak256(abi.encode(msg.sender, address(offer), address(want), userRequest));

        _withdrawRequests.remove(requestId);
        emit AtomicRequestCancelled(
            msg.sender,
            address(offer),
            address(want),
            userRequest.offerAmount,
            userRequest.deadline,
            userRequest.atomicPrice,
            block.timestamp
        );
    }

    //============================== SOLVER FUNCTIONS ===============================

    /**
     * @notice Called by solvers in order to exchange offer asset for want asset.
     * @notice Solvers are optimistically transferred the offer asset, then are required to
     *         approve this contract to spend enough of want assets to cover all requests.
     * @dev It is very likely `solve` TXs will be front run if broadcasted to public mem pools,
     *      so solvers should use private mem pools.
     * @param offer the ERC20 offer token to solve for
     * @param want the ERC20 want token to solve for
     * @param users an array of user addresses to solve for
     * @param runData extra data that is passed back to solver when `finishSolve` is called
     * @param solver the address to make `finishSolve` callback to
     */
    function solve(
        ERC20 offer,
        ERC20 want,
        address[] calldata users,
        bytes calldata runData,
        address solver,
        AtomicRequest calldata request
    ) external nonReentrant {
        // Save offer asset decimals.
        uint8 offerDecimals = offer.decimals();
        // bytes32 requestId = keccak256(abi.encode(request));

        uint256 assetsToOffer;
        uint256 assetsForWant;
        for (uint256 i; i < users.length; ++i) {
            // Add maturity time check
            if (
                block.timestamp
                    < request.creationTime
                        + (whitelist[users[i]] ? MATURITY_TIME / whitelistMaturityDivisor : MATURITY_TIME)
            ) {
                revert AtomicQueue__RequestNotMature(users[i]);
            }

            if (block.timestamp > request.deadline) {
                revert AtomicQueue__RequestDeadlineExceeded(users[i]);
            }
            if (request.offerAmount == 0) {
                revert AtomicQueue__ZeroOfferAmount(users[i]);
            }

            // User gets whatever their atomic price * offerAmount is.
            assetsForWant += _calculateAssetAmount(request.offerAmount, request.atomicPrice, offerDecimals);

            // If all checks above passed, the users request is valid and should be fulfilled.
            assetsToOffer += request.offerAmount;

            // Transfer shares from user to solver.
            offer.safeTransferFrom(users[i], solver, request.offerAmount);
        }

        IAtomicSolver(solver).finishSolve(runData, msg.sender, offer, want, assetsToOffer, assetsForWant);

        for (uint256 i; i < users.length; ++i) {
            // Send user their share of assets.
            uint256 assetsToUser = _calculateAssetAmount(request.offerAmount, request.atomicPrice, offerDecimals);

            want.safeTransferFrom(solver, users[i], assetsToUser);

            withdrawInProgressAmount[offer] -= request.offerAmount;

            emit AtomicRequestFulfilled(
                users[i], address(offer), address(want), request.offerAmount, assetsToUser, block.timestamp
            );

            bytes32 requestId = keccak256(abi.encode(users[i], address(offer), address(want), request));
            _withdrawRequests.remove(requestId);
        }
    }

    //============================== INTERNAL FUNCTIONS ===============================

    /**
     * @notice Helper function to calculate the amount of want assets a users wants in exchange for
     *         `offerAmount` of offer asset.
     */
    function _calculateAssetAmount(uint256 offerAmount, uint256 atomicPrice, uint8 offerDecimals)
        internal
        pure
        returns (uint256)
    {
        return atomicPrice.mulDivDown(offerAmount, 10 ** offerDecimals);
    }
}
