// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { AtomicQueue } from "./atomic-queue/AtomicQueue.sol";
import { TellerWithMultiAssetSupport } from "./base/Roles/TellerWithMultiAssetSupport.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";

/// @title SuperUSDWrapper
/// @author SuperFi Labs
/// @notice Wraps superUSD share redemption via instantWithdraw, routing proceeds to a specified recipient.
///         Pass `msg.sender` as recipient to receive USDC back; pass `aeonPay` to forward directly to Aeon Pay.
/// @dev This contract must be granted `instantWithdraw` caller authority on the AtomicQueue before use.
///      Access to all user-facing functions is gated by the Authority contract, matching the same
///      role-based permission model used by TellerWithMultiAssetSupport.
contract SuperUSDWrapper is Auth, ReentrancyGuard {

    /***************************************
    CONSTANTS
    ***************************************/

    /// @notice The AtomicQueue used to execute instant withdrawals.
    AtomicQueue public immutable queue;

    /// @notice The Aeon Pay address that receives forwarded funds.
    address public immutable aeonPay;

    /***************************************
    ERRORS
    ***************************************/

    /// @notice Thrown when an invalid (zero) address is provided.
    error SuperUSDWrapper__InvalidAddress();

    /// @notice Thrown when a zero amount is provided.
    error SuperUSDWrapper__ZeroAmount();

    /***************************************
    EVENTS
    ***************************************/

    /// @notice Emitted when shares are redeemed and the proceeds are sent to a recipient.
    /// @param sender The original caller.
    /// @param share The vault share token redeemed.
    /// @param recipient The address that received the want tokens.
    /// @param sharesIn The amount of shares redeemed.
    /// @param assetsOut The amount of want tokens sent to the recipient.
    event WithdrawnA(
        address indexed sender,
        address indexed share,
        address indexed recipient,
        uint256 sharesIn,
        uint256 assetsOut
    );

    /// @notice Emitted when a user forwards their own tokens to Aeon Pay via this contract.
    /// @param sender The original caller (the user whose funds are being forwarded).
    /// @param token The token forwarded.
    /// @param amount The amount forwarded.
    event WithdrawnB(
        address indexed sender,
        address indexed token,
        uint256 amount
    );

    /***************************************
    CONSTRUCTOR
    ***************************************/

    /// @notice Constructs the SuperUSDWrapper contract.
    /// @param _owner The initial owner of the contract (passed to Auth).
    /// @param _authority The Authority contract controlling role-based access (passed to Auth).
    /// @param queue_ The address of the AtomicQueue used for instant withdrawals.
    /// @param aeonPay_ The address of Aeon Pay that receives forwarded funds.
    constructor(
        address _owner,
        Authority _authority,
        address queue_,
        address aeonPay_
    ) Auth(_owner, _authority) {
        if (queue_ == address(0) || aeonPay_ == address(0)) revert SuperUSDWrapper__InvalidAddress();
        queue = AtomicQueue(queue_);
        aeonPay = aeonPay_;
    }

    /***************************************
    EXTERNAL FUNCTIONS
    ***************************************/

    // /// @notice Redeems vault shares via instantWithdraw and sends the proceeds to `recipient`.
    // /// @dev Callable by addresses authorized via the Authority contract.
    // ///      - Pass `msg.sender` as recipient to receive USDC back (Function B, step 1).
    // ///      - Pass `aeonPay` as recipient to forward directly to Aeon Pay (Function A).
    // /// @param share The vault share token to redeem.
    // /// @param want The base asset to receive (e.g. USDC).
    // /// @param shareAmount The amount of shares to redeem.
    // /// @param minimumAssetsOut The minimum amount of want tokens to accept.
    // /// @param teller The teller contract associated with the vault.
    // /// @return assetsOut The amount of want tokens sent to the recipient.
    // function withdrawA(
    //     ERC20 share,
    //     ERC20 want,
    //     uint256 shareAmount,
    //     uint256 minimumAssetsOut,
    //     TellerWithMultiAssetSupport teller,
    //     address recipient
    // ) external requiresAuth nonReentrant returns (uint256 assetsOut) {
    //     if (shareAmount == 0) revert SuperUSDWrapper__ZeroAmount();

    //     // 1. Pull shares from caller into this contract
    //     SafeERC20.safeTransferFrom(IERC20(address(share)), msg.sender, address(this), shareAmount);

    //     // Approve the queue to pull shares from this contract for the redemption
    //     SafeERC20.forceApprove(IERC20(address(share)), address(queue), shareAmount);

    //     // 2. Execute instantWithdraw — queue pulls shares from this contract, sends want tokens here
    //     assetsOut = queue.instantWithdraw(share, want, shareAmount, minimumAssetsOut, teller);

    //     // 3. Send want tokens to Aeon Pay
    //     SafeERC20.safeTransfer(IERC20(address(want)), aeonPay, assetsOut);

    //     emit WithdrawnA(msg.sender, address(share), aeonPay, shareAmount, assetsOut);
    // }

    function withdrawB(
        ERC20 share,
        ERC20 want,
        uint256 shareAmount,
        uint256 minimumAssetsOut,
        TellerWithMultiAssetSupport teller
    ) external requiresAuth nonReentrant returns (uint256 assetsOut) {
        if (shareAmount == 0) revert SuperUSDWrapper__ZeroAmount();

        // 1. Pull shares from caller into this contract
        SafeERC20.safeTransferFrom(IERC20(address(share)), msg.sender, address(this), shareAmount);

        // Approve the queue to pull shares from this contract for the redemption
        SafeERC20.forceApprove(IERC20(address(share)), address(queue), shareAmount);

        // 2. Execute instantWithdraw — queue pulls shares from this contract, sends want tokens here
        assetsOut = queue.instantWithdraw(share, want, shareAmount, minimumAssetsOut, teller);
        
        // 3. Send want tokens back to the caller
        SafeERC20.safeTransfer(IERC20(address(want)), msg.sender, assetsOut);

        // 4. Send want tokens from caller to Aeon Pay
        SafeERC20.safeTransferFrom(IERC20(address(want)), msg.sender, aeonPay, assetsOut);

        emit WithdrawnB(msg.sender, address(want), assetsOut);
    }

    // function withdrawC(
    //     ERC20 share,
    //     ERC20 want,
    //     uint256 shareAmount,
    //     uint256 minimumAssetsOut,
    //     TellerWithMultiAssetSupport teller
    // ) external requiresAuth nonReentrant returns (uint256 assetsOut) {
    //     if (shareAmount == 0) revert SuperUSDWrapper__ZeroAmount();
    // }
}
