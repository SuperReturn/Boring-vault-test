// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISakePool } from "./../interfaces/external/sake/ISakePool.sol";
import { ZapTellerBase } from "./ZapTellerBase.sol";


/// @title SSuperusdSakeZapTeller
/// @author SuperFi Labs
/// @notice A teller that helps convert a base asset to Sake asSuperUSD.
///
/// Designed for use on Soneium only.
contract SSuperusdSakeZapTeller is ZapTellerBase {

    /***************************************
    CONSTANTS
    ***************************************/

    /// @notice The address of the Sake pool
    address public immutable sakePool;

    /// @notice The address of the asSuperUSD token contract
    address public immutable assuperusd;

    /***************************************
    CONSTRUCTOR
    ***************************************/

    /// @notice Constructs the SSuperusdSakeZapTeller contract.
    /// @param initialOwner The initial owner of the contract.
    /// @param superusd_ The address of the SuperUSD token contract.
    /// @param ssuperusd_ The address of the sSuperUSD token contract.
    /// @param superusdTeller_ The address of the SuperUSD teller.
    /// @param ssuperusdTeller_ The address of the sSuperUSD teller.
    /// @param sakePool_ The address of the Sake pool.
    /// @param assuperusd_ The address of the asSuperUSD token contract.
    constructor(
        address initialOwner,
        address superusd_,
        address ssuperusd_,
        address superusdTeller_,
        address ssuperusdTeller_,
        address sakePool_,
        address assuperusd_
    ) ZapTellerBase(initialOwner, superusd_, ssuperusd_, superusdTeller_, ssuperusdTeller_) {
        // checks
        if(
            (sakePool_ == address(0)) ||
            (assuperusd_ == address(0))
        ) revert AddressZero();
        // set
        sakePool = sakePool_;
        assuperusd = assuperusd_;
        // pre approve ssuperusd to sake pool
        SafeERC20.forceApprove(IERC20(ssuperusd_), sakePool_, type(uint256).max);
    }

    /***************************************
    DEPOSIT FUNCTIONS
    ***************************************/

    /// @notice Deposits an asset to asSuperUSD.
    /// @param asset The asset to deposit.
    /// @param depositAmount The amount to deposit.
    /// @param minimumMint The minimum amount of asSuperUSD to mint.
    /// @return assuperusdAmount The amount of asSuperUSD minted.
    function depositAssetToasSuperUSD(
        address asset,
        uint256 depositAmount,
        uint256 minimumMint,
        address receiver
    ) external returns (uint256 assuperusdAmount) {
        // deposit and zap to assuperusd, sending it to the receiver
        assuperusdAmount = _depositAssetToSSuperUSD(asset, depositAmount, minimumMint, receiver);
    }

    /// @notice Deposits an asset to asSuperUSD.
    /// @param asset The asset to deposit.
    /// @param depositAmount The amount to deposit.
    /// @param minimumMint The minimum amount of asSuperUSD to mint.
    /// @param deadline The permit deadline.
    /// @param v Part of the permit signature.
    /// @param r Part of the permit signature.
    /// @param s Part of the permit signature.
    /// @return assuperusdAmount The amount of asSuperUSD minted.
    function depositAssetToasSuperUSDWithPermit(
        address asset,
        uint256 depositAmount,
        uint256 minimumMint,
        address receiver,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 assuperusdAmount) {
        // permit
        IERC20Permit(asset).permit(msg.sender, address(this), depositAmount, deadline, v, r, s);
        // deposit and zap to assuperusd, sending it to the receiver
        assuperusdAmount = _depositAssetToSSuperUSD(asset, depositAmount, minimumMint, receiver);
    }

    /***************************************
    HELPER FUNCTIONS
    ***************************************/

    /// @notice Deposits an asset to sSuperUSD.
    /// @param asset The asset to deposit.
    /// @param depositAmount The amount to deposit.
    /// @param minimumMint The minimum amount of sSuperUSD to mint.
    /// @param receiver The address to receive the newly minted sSuperUSD.
    /// @return assuperusdAmount The amount of asSuperUSD minted.
    function _depositAssetToSSuperUSD(
        address asset,
        uint256 depositAmount,
        uint256 minimumMint,
        address receiver
    ) internal returns (uint256 assuperusdAmount) {
        // convert the asset to ssuperusd
        assuperusdAmount = _convertAssetToSSuperUSD(asset, depositAmount, minimumMint);
        // check approval of ssuperusd to the sake pool
        _checkApproval(ssuperusd, sakePool, assuperusdAmount);
        // deposit ssuperusd to sake pool on behalf of the receiver
        ISakePool(sakePool).supply(ssuperusd, assuperusdAmount, receiver, 0);
    }
}
