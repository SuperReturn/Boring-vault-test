// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ZapTellerBase } from "./ZapTellerBase.sol";


/// @title SSuperusdZapTeller
/// @author SuperFi Labs
/// @notice A teller that helps convert a base asset to sSuperUSD.
contract SSuperusdZapTeller is ZapTellerBase {

    /***************************************
    CONSTRUCTOR
    ***************************************/

    /// @notice Constructs the SSuperusdZapTeller contract.
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
    ) ZapTellerBase(initialOwner, superusd_, ssuperusd_, superusdTeller_, ssuperusdTeller_) {}

    /***************************************
    DEPOSIT FUNCTIONS
    ***************************************/

    /// @notice Deposits an asset to sSuperUSD.
    /// @param asset The asset to deposit.
    /// @param depositAmount The amount to deposit.
    /// @param minimumMint The minimum amount of sSuperUSD to mint.
    /// @param receiver The address to receive the newly minted sSuperUSD.
    /// @return ssuperusdAmount The amount of sSuperUSD minted.
    function depositAssetToSSuperUSD(
        address asset,
        uint256 depositAmount,
        uint256 minimumMint,
        address receiver
    ) external returns (uint256 ssuperusdAmount) {
        // deposit and zap to ssuperusd, sending it to the receiver
        ssuperusdAmount = _depositAssetToSSuperUSD(asset, depositAmount, minimumMint, receiver);
    }

    /// @notice Deposits an asset to sSuperUSD using ERC2612 permit.
    /// @param asset The asset to deposit.
    /// @param depositAmount The amount to deposit.
    /// @param minimumMint The minimum amount of sSuperUSD to mint.
    /// @param receiver The address to receive the newly minted sSuperUSD.
    /// @param deadline The permit deadline.
    /// @param v Part of the permit signature.
    /// @param r Part of the permit signature.
    /// @param s Part of the permit signature.
    /// @return ssuperusdAmount The amount of sSuperUSD minted.
    function depositAssetToSSuperUSDWithPermit(
        address asset,
        uint256 depositAmount,
        uint256 minimumMint,
        address receiver,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 ssuperusdAmount) {
        // permit
        IERC20Permit(asset).permit(msg.sender, address(this), depositAmount, deadline, v, r, s);
        // deposit and zap to ssuperusd, sending it to the receiver
        ssuperusdAmount = _depositAssetToSSuperUSD(asset, depositAmount, minimumMint, receiver);
    }

    /***************************************
    HELPER FUNCTIONS
    ***************************************/

    /// @notice Deposits an asset to sSuperUSD.
    /// @param asset The asset to deposit.
    /// @param depositAmount The amount to deposit.
    /// @param minimumMint The minimum amount of sSuperUSD to mint.
    /// @param receiver The address to receive the newly minted sSuperUSD.
    /// @return ssuperusdAmount The amount of sSuperUSD minted.
    function _depositAssetToSSuperUSD(
        address asset,
        uint256 depositAmount,
        uint256 minimumMint,
        address receiver
    ) internal returns (uint256 ssuperusdAmount) {
        // convert the asset to ssuperusd
        ssuperusdAmount = _convertAssetToSSuperUSD(asset, depositAmount, minimumMint);
        // transfer ssuperusd to the receiver
        SafeERC20.safeTransfer(IERC20(ssuperusd), receiver, ssuperusdAmount);
    }
}
