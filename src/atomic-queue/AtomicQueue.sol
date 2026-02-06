// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "@solmate/utils/ReentrancyGuard.sol";
import {IAtomicSolver} from "./IAtomicSolver.sol";
import {IInvestor} from "./IInvestor.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
/**
 * @notice Stores request information needed to fulfill a users atomic request.
 * @param deadline unix timestamp for when request is no longer valid
 * @param creationTime timestamp when request was created
 * @param offerAmount the amount of `offer` asset the user wants converted to `want` asset
 * @param user The address of the user making the request
 * @param offer The address of the offer token
 * @param want The address of the want token
 */
struct AtomicRequest {
    uint64 deadline; // deadline to fulfill request
    uint64 creationTime; // timestamp when request was created
    uint96 offerAmount; // The amount of offer asset the user wants to sell.
    address user; // The address of the user making the request
    address offer; // The address of the offer token
    address want; // The address of the want token
}

contract AtomicQueue is ReentrancyGuard, Auth {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // ========================================= GLOBAL STATE =========================================
    /**
     * @notice The set of request Ids currently in the queue.
     * @dev Requests are removed when solve or cancel is called.
     */
    EnumerableSet.Bytes32Set internal _existingWithdrawRequests;

    /**
     * @notice The maturity time of the atomic request.
     */
    uint256 public maturityTime = 1 days;

    /**
     * @notice Mapping of request Ids to AtomicRequests.
     * @dev Requests won't be removed when solve or cancel is called.
     */
    mapping(bytes32 => AtomicRequest) internal onChainWithdraws;

    /**
     * @notice This mapping tracks the total amount of 'offer' tokens in progress for withdrawal requests per want token.
     * @dev It is incremented when a new request is submitted and decremented when the request is fulfilled or cancelled.
     */
    mapping(address => mapping(address => uint256)) public withdrawInProgressAmount;

    /**
     * @notice Mapping to track whitelisted addresses, which can be solved quickly.
     */
    mapping(address => bool) public whitelist;

    /**
     * @notice The accountant contract to use for withdrawal
     */
    AccountantWithRateProviders public immutable accountant;

    /**
     * @notice The divisor used to reduce maturity time for whitelisted users.
     */
    uint256 public whitelistMaturityDivisor = 10;

    /**
     * @notice The discount(redemption fee) in parts-per-million (0.05% => 500)
     */
    uint256 public discount = 500; // 0.05% (ppm)

    /**
     * @notice Denominator for discount calculations (parts-per-million)
     */
    uint256 private constant DISCOUNT_DENOMINATOR = 1e6;

    //============================== ERRORS ===============================

    error AtomicQueue__BadWhitelistDivisor();
    error AtomicQueue__BadDiscount();
    error AtomicQueue__RemovedRequest();
    error AtomicQueue__DuplicateRequest();
    error AtomicQueue__OfferAmountIsZero();
    error AtomicQueue__UserAddressIsZero();
    error AtomicQueue__OfferAddressIsZero();
    error AtomicQueue__WantAddressIsZero();
    error AtomicQueue__InsufficientBalance();
    error AtomicQueue__DeadlineExpired();
    error AtomicQueue__RequestAccountantOfferMismatch(address offer, address vault);
    error AtomicQueue__BadUser();
    error AtomicQueue__BoringVaultTellerMismatch(address vault, address teller);
    error AtomicQueue__ZeroOfferAmount(address user);
    error AtomicQueue__InsufficientVaultLiquidity(uint256 required, uint256 available);
    error AtomicQueue__RequestNotMature(address user);
    error AtomicQueue__MinimumAssetsNotMet();
    error AtomicQueue__InstantWithdrawShortfall(uint256 expected, uint256 actual);
    error AtomicQueue__InsufficientBalanceInUserWallet(address user, uint256 required, uint256 available);
    error AtomicQueue__UnauthorizedSolver(address caller);
    //============================== EVENTS ===============================
    /**
     * @notice Emitted when `setMaturityTime` is called.
     */
    event MaturityTimeUpdated(uint256 oldMaturityTime, uint256 newMaturityTime);

    /**
     * @notice Emitted when `updateAtomicRequest` is called.
     */
    event AtomicRequestUpdated(
        bytes32 indexed requestId,
        address indexed user,
        address offerToken,
        address indexed wantToken,
        uint256 amount,
        uint256 deadline,
        uint256 timestamp
    );

    /**
     * @notice Emitted when `solve` exchanges a users offer asset for their want asset.
     */
    event AtomicRequestFulfilled(
        bytes32 indexed requestId,
        address indexed user,
        address offerToken,
        address indexed wantToken,
        uint256 offerAmountSpent,
        uint256 wantAmountReceived,
        uint256 timestamp
    );

    /**
     * @notice Emitted when `cancelAtomicRequest` is called.
     */
    event AtomicRequestCancelled(
        bytes32 indexed requestId,
        address indexed user,
        address offerToken,
        address indexed wantToken,
        uint256 amount,
        uint256 deadline,
        uint256 timestamp
    );

    /**
     * @notice Emitted when `instantWithdraw` is called.
     */
    event InstantWithdraw(
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 offerAmount,
        uint256 wantAmount,
        uint256 timestamp
    );

    /**
     * @notice Emitted when `addToWhitelist` is called.
     */
    event WhitelistAdded(address indexed user);

    /**
     * @notice Emitted when `removeFromWhitelist` is called.
     */
    event WhitelistRemoved(address indexed user);

    /**
     * @notice Emitted when `updateWhitelistMaturityDivisor` is called.
     */
    event WhitelistMaturityDivisorUpdated(uint256 newDivisor);

    /**
     * @notice Emitted when `setDiscount` is called.
     */
    event DiscountUpdated(uint256 newDiscount);

    /**
     * @notice Emitted when `setSolver` is called.
     */
    event SolverUpdated(address newSolver);

    /**
     * @notice Emitted when `setInvestor` is called.
     */
    event InvestorUpdated(address newInvestor);

    //============================== VARIABLES ===============================
    /**
     * @notice The solver contract to use for solving
     */
    IAtomicSolver public solver;

    /**
     * @notice The investor contract to use for managed instant withdrawals.
     */
    IInvestor public investor;

    /**
     * @notice Constructor
     * @param _owner The owner of the contract
     * @param _authority The authority of the contract
     * @param _accountant The accountant contract to use for withdrawal
     * @param _solver The solver contract to use for solving
     */
    constructor(address _owner, Authority _authority, address _accountant, address _solver) Auth(_owner, _authority) {
        accountant = AccountantWithRateProviders(_accountant);
        solver = IAtomicSolver(_solver);
    }

    //============================== ADMIN FUNCTIONS ===============================

    /**
     * @notice Allows the owner to update the maturity time
     * @param newMaturityTime The new maturity time in seconds
     */
    function setMaturityTime(uint256 newMaturityTime) external requiresAuth {
        uint256 oldMaturityTime = maturityTime;
        maturityTime = newMaturityTime;
        emit MaturityTimeUpdated(oldMaturityTime, newMaturityTime);
    }

    /**
     * @notice Allows the owner to update the discount
     * @param newDiscount The new discount in parts-per-million (500 = 0.05%)
     */
    function setDiscount(uint256 newDiscount) external requiresAuth {
        if (newDiscount >= DISCOUNT_DENOMINATOR) revert AtomicQueue__BadDiscount();
        discount = newDiscount;
        emit DiscountUpdated(newDiscount);
    }

    /**
     * @notice Add an address to the whitelist.
     * @dev Callable by MULTISIG_ROLE.
     * @param user The address to add to the whitelist.
     */
    function addToWhitelist(address user) external requiresAuth {
        if (user == address(0)) revert AtomicQueue__UserAddressIsZero();
        whitelist[user] = true;
        emit WhitelistAdded(user);
    }

    /**
     * @notice Remove an address from the whitelist.
     * @dev Callable by MULTISIG_ROLE.
     * @param user The address to remove from the whitelist.
     */
    function removeFromWhitelist(address user) external requiresAuth {
        if (user == address(0)) revert AtomicQueue__UserAddressIsZero();
        whitelist[user] = false;
        emit WhitelistRemoved(user);
    }

    /**
     * @notice Update the whitelist maturity divisor.
     * @dev Callable by MULTISIG_ROLE.
     * @param newDivisor The new divisor value.
     */
    function updateWhitelistMaturityDivisor(uint256 newDivisor) external requiresAuth {
        if (newDivisor == 0) revert AtomicQueue__BadWhitelistDivisor();
        whitelistMaturityDivisor = newDivisor;
        emit WhitelistMaturityDivisorUpdated(newDivisor);
    }

    /**
     * @notice Allows the owner to update the solver contract
     * @dev Callable by MULTISIG_ROLE.
     * @param newSolver The new solver contract address.
     */
    function setSolver(address newSolver) external requiresAuth {
        solver = IAtomicSolver(newSolver);
        emit SolverUpdated(newSolver);
    }

    /**
     * @notice Allows the admin to cancel multiple withdraw requests.
     * @dev Callable by MULTISIG_ROLE.
     * @param userRequests The array of user requests to cancel.
     */
    function cancelAtomicRequestByAdmin(AtomicRequest[] calldata userRequests) external requiresAuth {
        for (uint256 i = 0; i < userRequests.length; ++i) {
            AtomicRequest calldata userRequest = userRequests[i];
            bytes32 requestId = keccak256(abi.encode(userRequest));
            if (!_existingWithdrawRequests.contains(requestId)) revert AtomicQueue__RemovedRequest();
            withdrawInProgressAmount[userRequest.offer][userRequest.want] -= userRequest.offerAmount;

            _existingWithdrawRequests.remove(requestId);

            // Transfer offer shares from solver contract to user
            IAtomicSolver(solver).approveOfferForQueue(address(this), userRequest);
            ERC20(userRequest.offer).safeTransferFrom(address(solver), userRequest.user, userRequest.offerAmount);

            emit AtomicRequestCancelled(
                requestId,
                userRequest.user,
                userRequest.offer,
                userRequest.want,
                userRequest.offerAmount,
                userRequest.deadline,
                block.timestamp
            );
        }
    }

    /**
     * @notice Allows the owner to update the investor contract
     * @dev Callable by MULTISIG_ROLE.
     * @param newInvestor The new investor contract address.
     */
    function setInvestor(address newInvestor) external requiresAuth {
        investor = IInvestor(newInvestor);
        emit InvestorUpdated(newInvestor);
    }

    //============================== VIEW FUNCTIONS ===============================
    /**
     * @notice Get the total amount of 'offer' tokens in progress for withdrawal requests for a specific want token.
     * @param offer The address of the offer token.
     * @param want The address of the want token.
     * @return The total amount of 'offer' tokens in progress for withdrawal requests for the specified want token.
     */
    function getTotalWithdrawInProgressAmount(address offer, address want) external view returns (uint256) {
        return withdrawInProgressAmount[offer][want];
    }

    /**
     * @notice Get all existing withdraw request Ids currently in the queue.
     * @dev Includes requests that are not mature, matured, and expired. But does not include requests that have been solved.
     * @return requestIds The request Ids.
     */
    function getExistingWithdrawRequestIds() public view returns (bytes32[] memory) {
        return _existingWithdrawRequests.values();
    }

    /**
     * @notice Get all existing withdraw requests.
     * @dev Includes requests that are not mature, matured, and expired. But does not include requests that have been solved.
     */
    function getExistingWithdrawRequests()
        external
        view
        returns (bytes32[] memory requestIds, AtomicRequest[] memory requests)
    {
        requestIds = getExistingWithdrawRequestIds();
        uint256 requestsLength = requestIds.length;
        requests = new AtomicRequest[](requestsLength);
        for (uint256 i = 0; i < requestsLength; ) {
            requests[i] = onChainWithdraws[requestIds[i]];
            unchecked { ++i; }
        }
    }

    /**
     * @notice Get all existing withdraw requests by user.
     * @dev Includes requests that are not mature, matured, and expired. But does not include requests that have been solved.
     * @param user The address of the user.
     * @return requestIds The request Ids.
     * @return requests The requests.
     */
    function getExistingWithdrawRequestsByUser(address user)
        external
        view
        returns (bytes32[] memory requestIds, AtomicRequest[] memory requests)
    {
        bytes32[] memory allExistingWithdrawRequestIds = getExistingWithdrawRequestIds();
        uint256 allExistingWithdrawRequestsLength = allExistingWithdrawRequestIds.length;

        // First pass: count how many requests belong to this user
        uint256 userRequestCount = 0;
        for (uint256 i = 0; i < allExistingWithdrawRequestsLength; ) {
            if (onChainWithdraws[allExistingWithdrawRequestIds[i]].user == user) {
                userRequestCount++;
            }
            unchecked { ++i; }
        }

        // Initialize arrays with the correct size
        requestIds = new bytes32[](userRequestCount);
        requests = new AtomicRequest[](userRequestCount);

        // Second pass: populate the arrays with user's requests
        uint256 index = 0;
        for (uint256 i = 0; i < allExistingWithdrawRequestsLength; ) {
            bytes32 requestId = allExistingWithdrawRequestIds[i];
            AtomicRequest memory request = onChainWithdraws[requestId];
            if (request.user == user) {
                requestIds[index] = requestId;
                requests[index] = request;
                unchecked { ++index; }
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice Get a withdraw request by request Id.
     * @dev Does verify nonce is non-zero.
     * @param requestId The request Id.
     * @return request The request.
     */
    function getAtomicRequestById(bytes32 requestId) public view returns (AtomicRequest memory) {
        return onChainWithdraws[requestId];
    }

    /**
     * @notice Preview the amount of want assets that would be received for an atomic request.
     * @dev This is a view function that calculates the expected output without executing the transaction.
     * @param request The atomic request to preview.
     * @return wantAmountReceived The expected amount of want assets to be received.
     */
    function previewReceivedAmount(AtomicRequest calldata request) external view returns (uint256 wantAmountReceived) {
        // Basic validation (similar to checkAtomicRequestValid but without queue existence check)
        if (request.offerAmount == 0) revert AtomicQueue__OfferAmountIsZero();
        if (request.user == address(0)) revert AtomicQueue__UserAddressIsZero();
        if (request.offer == address(0)) revert AtomicQueue__OfferAddressIsZero();
        if (request.want == address(0)) revert AtomicQueue__WantAddressIsZero();
        if (block.timestamp > request.deadline) revert AtomicQueue__DeadlineExpired();

        // Get the offer token decimals
        ERC20 offer = ERC20(request.offer);
        uint8 offerDecimals = offer.decimals();

        // Get the rate and apply discount (same logic as in solve function)
        uint256 safeRate = accountant.getRateInQuoteSafe(ERC20(request.want));
        uint256 safeAtomicPriceWithDiscount = safeRate.mulDivDown(DISCOUNT_DENOMINATOR - discount, DISCOUNT_DENOMINATOR);

        // Calculate the want amount
        wantAmountReceived = _calculateAssetAmount(request.offerAmount, safeAtomicPriceWithDiscount, offerDecimals);
    }

    //============================== HELPER FUNCTIONS ===============================

    /**
     * @notice Helper function that validates a withdraw request.
     * @dev Reverts with specific error if the request is invalid.
     *      It is possible for a withdraw request to pass validation here, but solvers 
     *      may not be able to include the user in `solve` unless some other state is changed.
     * @param userRequest the full request struct to validate (should have correct .offer, .want, .user fields)
     */
    function checkAtomicRequestValid(AtomicRequest calldata userRequest)
        public
        view
    {
        bytes32 requestId = keccak256(abi.encode(userRequest));
        if (!_existingWithdrawRequests.contains(requestId)) revert AtomicQueue__RemovedRequest();

        address requestUser = userRequest.user;
        ERC20 offer = ERC20(userRequest.offer);

        // Validate offerAmount is nonzero.
        if (userRequest.offerAmount == 0) revert AtomicQueue__OfferAmountIsZero();
        // Validate user address is not zero.
        if (requestUser == address(0)) revert AtomicQueue__UserAddressIsZero();
        // Validate offer address is not zero.
        if (address(offer) == address(0)) revert AtomicQueue__OfferAddressIsZero();
        // Validate want address is not zero.
        if (userRequest.want == address(0)) revert AtomicQueue__WantAddressIsZero();

        // Validate deadline.
        if (block.timestamp > userRequest.deadline) revert AtomicQueue__DeadlineExpired();
    }

    //============================== USER FUNCTIONS ===============================

    /**
     * @notice Allows user to add their withdraw request.
     * @dev This function will completely ignore the provided atomic price and calculate a new one based off the
     *      the accountant rate in quote.
     * @param userRequest the users request
     */
    function updateAtomicRequest(AtomicRequest memory userRequest) external nonReentrant returns (bytes32) {
        if (userRequest.offer != address(accountant.vault())) revert AtomicQueue__RequestAccountantOfferMismatch(address(userRequest.offer), address(accountant.vault()));
        if (userRequest.user != msg.sender) revert AtomicQueue__BadUser();

        // try to gate rate from the accountant, should revert if the want token is not supported
        accountant.getRateInQuoteSafe(ERC20(userRequest.want));

        // Normalize creation time to prevent bypassing maturity
        userRequest.creationTime = uint64(block.timestamp);

        // Validate basic fields at submission time
        if (userRequest.offerAmount == 0) revert AtomicQueue__OfferAmountIsZero();
        if (userRequest.offer == address(0)) revert AtomicQueue__OfferAddressIsZero();
        if (userRequest.want == address(0)) revert AtomicQueue__WantAddressIsZero();
        if (userRequest.offerAmount > ERC20(userRequest.offer).balanceOf(userRequest.user)) revert AtomicQueue__InsufficientBalance();
        if (block.timestamp > userRequest.deadline) revert AtomicQueue__DeadlineExpired();

        bytes32 requestId = keccak256(abi.encode(userRequest));
        if (!_existingWithdrawRequests.add(requestId)) revert AtomicQueue__DuplicateRequest();

        onChainWithdraws[requestId] = userRequest;
        withdrawInProgressAmount[userRequest.offer][userRequest.want] += userRequest.offerAmount;

        // Transfer offer shares from user to solver contract
        ERC20(userRequest.offer).safeTransferFrom(userRequest.user, address(solver), userRequest.offerAmount);

        emit AtomicRequestUpdated(
            requestId,
            msg.sender,
            userRequest.offer,
            userRequest.want,
            userRequest.offerAmount,
            userRequest.deadline,
            block.timestamp
        );

        return requestId;
    }

    /**
     * @notice Allows user to cancel their withdraw request.
     * @param userRequest the user's request
     */
    function cancelAtomicRequest(AtomicRequest calldata userRequest) external {
        if (userRequest.user != msg.sender) revert AtomicQueue__BadUser();
        bytes32 requestId = keccak256(abi.encode(userRequest));
        if (!_existingWithdrawRequests.contains(requestId)) revert AtomicQueue__RemovedRequest();
        withdrawInProgressAmount[userRequest.offer][userRequest.want] -= userRequest.offerAmount;

        _existingWithdrawRequests.remove(requestId);

        // Transfer offer shares from solver contract to user
        IAtomicSolver(solver).approveOfferForQueue(address(this), userRequest);
        ERC20(userRequest.offer).safeTransferFrom(address(solver), userRequest.user, userRequest.offerAmount);

        emit AtomicRequestCancelled(
            requestId,
            userRequest.user,
            userRequest.offer,
            userRequest.want,
            userRequest.offerAmount,
            userRequest.deadline,
            block.timestamp
        );
    }

    /**
    * @notice Allows role granted users to instantly withdraw without going through the request queue.
    * @dev Callable by role granted users only.
    * @dev Ensures that the withdrawal amount plus pending queue withdrawals don't exceed vault liquidity.
    * @param offer The vault share token to burn
    * @param want The underlying asset to receive
    * @param offerAmount Amount of shares to withdraw
    * @param minimumAssetsOut Minimum amount of assets expected
    * @param teller The teller contract to use for withdrawal
    */
    function instantWithdraw(
        ERC20 offer,
        ERC20 want,
        uint256 offerAmount,
        uint256 minimumAssetsOut,
        TellerWithMultiAssetSupport teller
    ) external nonReentrant requiresAuth returns (uint256 assetsOut) {
        // Validate inputs
        if (offerAmount == 0) revert AtomicQueue__ZeroOfferAmount(msg.sender);
        
        // Get vault from accountant
        BoringVault vault = accountant.vault();
        if (address(offer) != address(vault)) revert AtomicQueue__RequestAccountantOfferMismatch(address(offer), address(vault));
        if (address(offer) != address(teller.vault())) revert AtomicQueue__BoringVaultTellerMismatch(address(offer), address(teller));
        uint256 ONE_SHARE = 10 ** offer.decimals();
        
        // Calculate assets that will be withdrawn
        assetsOut = offerAmount.mulDivDown(
            accountant.getRateInQuoteSafe(want), 
            ONE_SHARE
        );

        uint256 assetOutWithDiscount = assetsOut.mulDivDown(DISCOUNT_DENOMINATOR - discount, DISCOUNT_DENOMINATOR);
        
        // Ensure minimum output is met
        if (assetOutWithDiscount < minimumAssetsOut) {
            revert AtomicQueue__MinimumAssetsNotMet();
        }
        
        // Calculate assets needed for pending withdrawal requests for this want token
        uint256 pendingWithdrawAssets = withdrawInProgressAmount[address(offer)][address(want)].mulDivDown(
            accountant.getRateInQuoteSafe(want),
            ONE_SHARE
        );
        
        // Check vault has enough liquidity
        uint256 vaultBalance = want.balanceOf(address(vault));
        uint256 totalRequired = assetOutWithDiscount + pendingWithdrawAssets;
        
        if (totalRequired > vaultBalance) {
            // cannot withdraw from zero address investor
            IInvestor _investor = investor;
            if (address(_investor) == address(0)) revert AtomicQueue__InsufficientVaultLiquidity(totalRequired, vaultBalance);
            // manage the vault to free funds
            _investor.autoWithdrawal(vaultBalance, totalRequired, want);
            // check vault balance after management
            vaultBalance = want.balanceOf(address(vault));
            if (totalRequired > vaultBalance) {
                revert AtomicQueue__InsufficientVaultLiquidity(totalRequired, vaultBalance);
            }
        }
        
        // Transfer shares from user to this contract
        offer.safeTransferFrom(msg.sender, address(this), offerAmount);
        
        // Execute withdrawal through teller
        assetsOut = teller.bulkWithdraw(want, offerAmount, minimumAssetsOut, address(this));

        if (assetsOut < assetOutWithDiscount) {
            revert AtomicQueue__InstantWithdrawShortfall(assetOutWithDiscount, assetsOut);
        }

        uint256 excessAssets = assetsOut - assetOutWithDiscount;
        if (excessAssets > 0) {
            want.safeTransfer(address(vault), excessAssets);
        }

        want.safeTransfer(msg.sender, assetOutWithDiscount);
        assetsOut = assetOutWithDiscount;

        emit InstantWithdraw(
            msg.sender,
            address(offer),
            address(want),
            offerAmount,
            assetOutWithDiscount,
            block.timestamp
        );
    }

    //============================== SOLVER FUNCTIONS ===============================

    /**
     * @notice Called by solvers in order to exchange offer asset for want asset.
     * @notice Solvers are optimistically transferred the offer asset, then are required to
     *         approve this contract to spend enough of want assets to cover the request.
     * @dev It is very likely `solve` TXs will be front run if broadcasted to public mem pools,
     *      so solvers should use private mem pools.
     * @param runData extra data that is passed back to solver when `finishSolve` is called
     * @param request the atomic request to solve
     */
    function solve(
        bytes calldata runData,
        AtomicRequest calldata request
    ) external nonReentrant {
        ERC20 offer = ERC20(request.offer);
        ERC20 want = ERC20(request.want);
        address user = request.user;
        
        // Save offer asset decimals.
        uint8 offerDecimals = offer.decimals();

        checkAtomicRequestValid(request);

        // Check maturity time
        if (
            block.timestamp
                < request.creationTime
                    + (whitelist[user] ? maturityTime / whitelistMaturityDivisor : maturityTime)
        ) {
            revert AtomicQueue__RequestNotMature(user);
        }

        // Check if the caller is the solver
        if (msg.sender != address(solver)) revert AtomicQueue__UnauthorizedSolver(msg.sender);

        uint256 safeRate = accountant.getRateInQuoteSafe(ERC20(request.want));
        uint256 safeAtomicPriceWithDiscount = safeRate.mulDivDown(DISCOUNT_DENOMINATOR - discount, DISCOUNT_DENOMINATOR);

        // Calculate want assets needed
        uint256 assetsForWant = _calculateAssetAmount(request.offerAmount, safeAtomicPriceWithDiscount, offerDecimals);

        // // Transfer offer shares from user to solver contract
        // offer.safeTransferFrom(user, solver, request.offerAmount);

        // Call solver contract to finish the solve
        IAtomicSolver(solver).finishSolve(runData, msg.sender, offer, want, request.offerAmount, assetsForWant, address(accountant.vault()));

        // Transfer want assets from solver contract to user
        want.safeTransferFrom(address(solver), user, assetsForWant);

        // Decrease the withdraw in progress amount
        withdrawInProgressAmount[address(offer)][address(want)] -= request.offerAmount;

        bytes32 requestId = keccak256(abi.encode(request));
        // Emit event
        emit AtomicRequestFulfilled(
            requestId, user, address(offer), address(want), request.offerAmount, assetsForWant, block.timestamp
        );

        // Remove request from queue
        _existingWithdrawRequests.remove(requestId);
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
