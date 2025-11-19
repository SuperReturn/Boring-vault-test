// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { TellerWithMultiAssetSupport } from "./../base/Roles/TellerWithMultiAssetSupport.sol";
//import { Errors } from "./../libraries/Errors.sol";
import { Ownable2StepWTR } from "./Ownable2StepWTR.sol";


/// @title ZapTellerBase
/// @author SuperFi Labs
/// @notice A base contract for zap tellers.
contract ZapTellerBase is Ownable2StepWTR {

    /***************************************
    CONSTANTS
    ***************************************/

    /// @notice The address of the SuperUSD token contract
    address public immutable superusd;

    /// @notice The address of the sSuperUSD token contract
    address public immutable ssuperusd;

    /// @notice The address of the SuperUSD teller contract
    address public immutable superusdTeller;

    /// @notice The address of the sSuperUSD teller contract
    address public immutable ssuperusdTeller;

    /***************************************
    ERRORS
    ***************************************/

    /// @notice Thrown when inputting an invalid zero address
    error AddressZero();

    /// @notice Thrown when inputting an invalid zero amount
    error AmountZero();

    /***************************************
    CONSTRUCTOR
    ***************************************/

    /// @notice Constructs the ZapTellerBase contract.
    /// @param initialOwner The initial owner of the contract.
    /// @param superusd_ The address of the SuperUSD token contract.
    /// @param ssuperusd_ The address of the sSuperUSD token contract.
    /// @param superusdTeller_ The address of the SuperUSD teller.
    /// @param ssuperusdTeller_ The address of the sSuperUSD teller.
    constructor(
        address initialOwner,
        address superusd_,
        address ssuperusd_,
        address superusdTeller_,
        address ssuperusdTeller_
    ) Ownable2StepWTR(initialOwner) {
        // checks
        if(
            (superusd_ == address(0)) ||
            (ssuperusd_ == address(0)) ||
            (superusdTeller_ == address(0)) ||
            (ssuperusdTeller_ == address(0))
        ) revert AddressZero();
        // set
        superusd = superusd_;
        ssuperusd = ssuperusd_;
        superusdTeller = superusdTeller_;
        ssuperusdTeller = ssuperusdTeller_;
        // pre approve superusd to ssuperusd
        SafeERC20.forceApprove(IERC20(superusd_), ssuperusd_, type(uint256).max);
    }

    /***************************************
    HELPER FUNCTIONS
    ***************************************/

    /// @notice Converts an asset to sSuperUSD.
    /// The sSuperUSD will be held in this contract, the inheriting contract should do something with it.
    /// @param asset The asset to deposit.
    /// @param depositAmount The amount to deposit.
    /// @param minimumMint The minimum amount of sSuperUSD to mint.
    /// @return ssuperusdAmount The amount of sSuperUSD minted.
    function _convertAssetToSSuperUSD(
        address asset,
        uint256 depositAmount,
        uint256 minimumMint
    ) internal returns (uint256 ssuperusdAmount) {
        // must deposit a valid token
        if(asset == address(0)) revert AddressZero();
        // must deposit nonzero amount
        if(depositAmount == 0) revert AmountZero();
        // transfer tokens in
        SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), depositAmount);
        // get new token balance
        uint256 assetBalance = IERC20(asset).balanceOf(address(this));
        // check approval of asset to superusd
        _checkApproval(asset, superusd, assetBalance);
        // convert asset to superusd
        TellerWithMultiAssetSupport(superusdTeller).deposit(ERC20(asset), assetBalance, 0); // will revert if asset not supported
        // get superusd balance
        uint256 superusdBalance = IERC20(superusd).balanceOf(address(this));
        // check approval of superusd to ssuperusd
        _checkApproval(superusd, ssuperusd, superusdBalance);
        // convert superusd to ssuperusd
        TellerWithMultiAssetSupport(ssuperusdTeller).deposit(ERC20(superusd), superusdBalance, minimumMint); // will revert if insufficient amount minted
        // return ssuperusd amount
        ssuperusdAmount = IERC20(ssuperusd).balanceOf(address(this));
    }

    /// @notice Checks the approval of an ERC20 token from this contract to another address
    /// @param token The token to check allowance
    /// @param recipient The address to give allowance to
    /// @param minAmount The minimum amount of the allowance
    function _checkApproval(address token, address recipient, uint256 minAmount) internal {
        // If current allowance is insufficient
        if(IERC20(token).allowance(address(this), recipient) < minAmount) {
            // Set allowance to max
            SafeERC20.forceApprove(IERC20(token), recipient, type(uint256).max);
        }
    }
}
