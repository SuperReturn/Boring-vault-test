// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {Ownable2StepWTR} from "./../zaps/Ownable2StepWTR.sol";

/// @title Multisend
/// @notice Distributes ERC20 tokens or native ETH to multiple recipients in one transaction.
/// @dev Uses Solmate's SafeTransferLib for compatibility with non-standard ERC20s (e.g. USDT).
///      The caller must approve this contract for `totalAmount` before calling `multisend`.
contract Multisend is Ownable2StepWTR {
    /// @notice A recipient address paired with the token amount they should receive.
    /// @param receiver The address to send tokens to.
    /// @param amount The number of tokens (in the token's smallest unit) to send.
    struct ReceiverAndAmount {
        address receiver;
        uint256 amount;
    }

    /// @notice Thrown when the sum of individual amounts does not equal the declared total.
    /// @param totalAmount The total amount the caller declared.
    /// @param calculatedAmount The actual sum of individual receiver amounts.
    error AmountMismatch(uint256 totalAmount, uint256 calculatedAmount);

    /// @notice Thrown when an ETH transfer to a receiver fails.
    /// @param receiver The address that the ETH transfer failed for.
    error ETHTransferFailed(address receiver);

    /// @notice Constructs the Multisend contract.
    /// @param initialOwner The initial owner of the contract, used for token rescues.
    constructor(address initialOwner) Ownable2StepWTR(initialOwner) {}

    /// @notice Transfers `totalAmount` of `token` from the caller, then distributes to each receiver.
    /// @dev Pulls all tokens up-front via `safeTransferFrom`, then pushes to each receiver via `safeTransfer`.
    ///      Reverts after distribution if the sum of amounts does not match `totalAmount`.
    /// @param token The ERC20 token to distribute.
    /// @param totalAmount The exact total of tokens to pull from the caller. Must equal the sum of all receiver amounts.
    /// @param receivers An array of (address, amount) pairs specifying each distribution.
    function multisend(address token, uint256 totalAmount, ReceiverAndAmount[] calldata receivers) external {
        // Pull all tokens from the caller in a single transferFrom.
        SafeTransferLib.safeTransferFrom(ERC20(token), msg.sender, address(this), totalAmount);
        // Push tokens to each receiver.
        uint256 calculatedAmount = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            calculatedAmount += receivers[i].amount;
            SafeTransferLib.safeTransfer(ERC20(token), receivers[i].receiver, receivers[i].amount);
        }
        // Verify the declared total matches the actual sum to prevent tokens getting stuck.
        if (calculatedAmount != totalAmount) {
            revert AmountMismatch(totalAmount, calculatedAmount);
        }
    }

    /// @notice Distributes native ETH to multiple recipients in one transaction.
    /// @dev Reverts if the sum of individual amounts does not equal `msg.value`.
    /// @param receivers An array of (address, amount) pairs specifying each distribution.
    function multisendETH(ReceiverAndAmount[] calldata receivers) external payable {
        // Push tokens to each receiver.
        uint256 calculatedAmount = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            calculatedAmount += receivers[i].amount;
            (bool success,) = receivers[i].receiver.call{value: receivers[i].amount}("");
            if (!success) revert ETHTransferFailed(receivers[i].receiver);
        }
        // Verify the declared total matches the actual sum to prevent tokens getting stuck.
        if (calculatedAmount != msg.value) {
            revert AmountMismatch(msg.value, calculatedAmount);
        }
    }
}
