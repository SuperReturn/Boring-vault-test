// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { TellerWithMultiAssetSupport } from "./Roles/TellerWithMultiAssetSupport.sol";
import { AtomicQueue } from "./../atomic-queue/AtomicQueue.sol";

contract AirVault is Auth, Initializable, ERC20Upgradeable, UUPSUpgradeable {
    using Address for address;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ========================================= STATE =========================================

    uint8 private _decimals;

    struct TokenSeconds {
        uint216 tokenSeconds; // the accumulated token seconds as of the last update
        uint40 timestamp; // the timestamp of the last update
    }

    // the last known token seconds for each account
    mapping(address => TokenSeconds) private _tokenSeconds;

    // a list of all holders past and present
    EnumerableSet.AddressSet private _holders;

    /// @notice The address of the SuperUSD token contract
    address public immutable superusd;

    /// @notice The address of the sSuperUSD token contract
    address public immutable ssuperusd;

    /// @notice The address of the SuperUSD teller contract
    address public immutable superusdTeller;

    /// @notice The address of the sSuperUSD teller contract
    address public immutable ssuperusdTeller;
    
    /// @notice The address of the sSuperUSD AtomicQueue contract
    address public immutable ssuperusdAtomicQueue;

    error AddressZero();
    error InsufficientMinted();

    event Deposit(address indexed from, address indexed to, address indexed asset, uint256 depositAmount, uint256 amountMinted);
    event Withdraw(address indexed from, address indexed to, uint256 amountShares, uint256 amountSSuperUSD);

    //============================== CONSTRUCTOR ===============================

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice Constructs the AirVault implementation contract.
    /// @param superusd_ The address of the SuperUSD token contract.
    /// @param ssuperusd_ The address of the sSuperUSD token contract.
    /// @param superusdTeller_ The address of the SuperUSD teller.
    /// @param ssuperusdTeller_ The address of the sSuperUSD teller.
    /// @param ssuperusdAtomicQueue_ The address of the sSuperUSD AtomicQueue contract.
    constructor(
        address superusd_,
        address ssuperusd_,
        address superusdTeller_,
        address ssuperusdTeller_,
        address ssuperusdAtomicQueue_
    ) Auth(address(0), Authority(address(0))) {
        if(
            superusd_ == address(0) ||
            ssuperusd_ == address(0) ||
            superusdTeller_ == address(0) ||
            ssuperusdTeller_ == address(0) ||
            ssuperusdAtomicQueue_ == address(0)
        ) {
            revert AddressZero();
        }
        _disableInitializers();
        superusd = superusd_;
        ssuperusd = ssuperusd_;
        superusdTeller = superusdTeller_;
        ssuperusdTeller = ssuperusdTeller_;
        ssuperusdAtomicQueue = ssuperusdAtomicQueue_;
    }

    function initialize(
        address _owner,
        Authority _authority,
        string memory _name,
        string memory _symbol,
        uint8 decimals_
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __UUPSUpgradeable_init();
        owner = _owner;
        authority = _authority;
        _decimals = decimals_;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        requiresAuth
    {}

    //============================== DEPOSIT ===============================

    /// @notice Deposits an asset.
    /// @param asset The asset to deposit.
    /// @param depositAmount The amount to deposit.
    /// @param minimumMint The minimum amount of vault token to mint.
    /// @param receiver The address to receive the newly minted vault token.
    /// @return amountMinted The amount of vault token minted.
    function deposit(
        address asset,
        uint256 depositAmount,
        uint256 minimumMint,
        address receiver
    ) external returns (uint256 amountMinted) {
        // transfer the token from msg.sender to this contract
        SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), depositAmount);
        // if the asset is superusd
        if(asset == superusd) {
            // mint the vault token 1:1
            amountMinted = depositAmount;
        }
        // if the asset is ssuperusd
        else if(asset == ssuperusd) {
            // redeem the ssuperusd to superusd
            amountMinted = _convertSSuperUSDToSuperUSD(depositAmount);
        }
        // if the asset is another token
        else {
            // deposit the asset into superusd
            amountMinted = _convertAssetToSuperUSD(asset, depositAmount);
        }
        // check minimum mint
        if(amountMinted < minimumMint) revert InsufficientMinted();
        // mint the vault token
        _mint(receiver, amountMinted);
        // emit event
        emit Deposit(msg.sender, receiver, asset, depositAmount, amountMinted);
    }

    //============================== WITHDRAW ===============================

    /// @notice Withdraws from the vault.
    /// Burns shares from the caller and transfers ssuperusd to the receiver.
    /// @param amountShares The amount of shares to withdraw.
    /// @param receiver The address to receive sSuperUSD.
    /// @return amountSSuperUSD The amount of sSuperUSD transferred.
    function withdraw(uint256 amountShares, address receiver) external returns (uint256 amountSSuperUSD) {
        // burn shares from msg.sender
        _burn(msg.sender, amountShares);
        // convert superusd to ssuperusd
        amountSSuperUSD = _convertSuperUSDToSSuperUSD(amountShares);
        // transfer ssuperusd from this contract to receiver
        SafeERC20.safeTransfer(IERC20(ssuperusd), receiver, amountSSuperUSD);
        // emit event
        emit Withdraw(msg.sender, receiver, amountShares, amountSSuperUSD);
    }

    //============================== TOKEN SECONDS ===============================

    /// @notice Gets the tokenSeconds for an account, updated to the current timestamp.
    /// @param account The account to get the tokenSeconds for.
    /// @return tokenSeconds_ The tokenSeconds for the account.
    function getAccountTokenSeconds(address account) external view returns (uint216 tokenSeconds_) {
        // do not track address zero
        if(account == address(0)) revert AddressZero();
        // get last known token seconds
        TokenSeconds memory tokenSeconds = _tokenSeconds[account];
        // if first time return zero
        if(tokenSeconds.timestamp == 0) return 0;
        // get current timestamp
        uint40 timestamp = _getCurrentTimestamp();
        // if timestamp has not changed, return current value
        if(tokenSeconds.timestamp >= timestamp) return tokenSeconds.tokenSeconds;
        // if timestamp has changed, accumulate token seconds
        uint40 timeElapsed = timestamp - tokenSeconds.timestamp;
        uint256 accumulated = balanceOf(account) * timeElapsed;
        return SafeCast.toUint216(tokenSeconds.tokenSeconds + accumulated);
    }

    /// @notice Called on balance changes.
    /// @param from The account the tokens are transferred from.
    /// @param to The account the tokens are transferred to.
    /// @param value The amount of tokens transferred.
    function _update(address from, address to, uint256 value) internal virtual override {
        // accumulate token seconds for sender and receiver
        _accumulateTokenSeconds(from);
        _accumulateTokenSeconds(to);
        // add the receiver to the holders list
        if(to != address(0) && value > 0) _holders.add(to);
        // update balances
        super._update(from, to, value);
    }

    /// @notice Accumulates token seconds for an account up to the current timestamp.
    /// @param account The account to accumulate token seconds for.
    function _accumulateTokenSeconds(address account) internal {
        // do not track address zero
        if(account == address(0)) return;
        // get last known token seconds
        TokenSeconds memory tokenSeconds = _tokenSeconds[account];
        // get current timestamp
        uint40 timestamp = _getCurrentTimestamp();
        // if first time, set timestamp and exit
        if(tokenSeconds.timestamp == 0) {
            tokenSeconds.timestamp = timestamp;
            _tokenSeconds[account] = tokenSeconds;
            return;
        }
        // if timestamp has not changed, do nothing
        if(tokenSeconds.timestamp >= timestamp) return;
        // if timestamp has changed, accumulate token seconds
        uint40 timeElapsed = timestamp - tokenSeconds.timestamp;
        uint256 accumulated = balanceOf(account) * timeElapsed;
        tokenSeconds.tokenSeconds = SafeCast.toUint216(tokenSeconds.tokenSeconds + accumulated);
        tokenSeconds.timestamp = timestamp;
        // store changes
        _tokenSeconds[account] = tokenSeconds;
    }

    /// @notice Safely returns the current timestamp.
    /// @return timestamp The current timestamp.
    function _getCurrentTimestamp() internal view returns (uint40 timestamp) {
        // get current timestamp
        uint256 blockTimestamp = block.timestamp;
        // cap timestamp
        if(blockTimestamp > type(uint40).max) blockTimestamp = type(uint40).max;
        // cast to uint40
        timestamp = uint40(blockTimestamp);
    }

    //============================== HOLDERS ===============================

    /// @notice Returns the number of holders past and present.
    function getNumberOfHolders() external view returns (uint256) {
        return _holders.length();
    }

    /// @notice Returns the address of the holder at the given index.
    function getHolderAtIndex(uint256 index) external view returns (address) {
        return _holders.at(index);
    }

    //============================== METADATA ===============================
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    /// @notice Sets the name and symbol of the token.
    /// @dev Callable by authorized roles.
    /// @param name_ The name of the token.
    /// @param symbol_ The symbol of the token.
    function setNameAndSymbol(string calldata name_, string calldata symbol_) external requiresAuth {
        // get storage
        bytes32 ERC20StorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;
        ERC20Upgradeable.ERC20Storage storage $;
        assembly {
            $.slot := ERC20StorageLocation
        }
        // set name and symbol in storage
        $._name = name_;
        $._symbol = symbol_;
    }

    //============================== TOKEN CONVERSION FUNCTIONS ===============================

    /// @notice Converts an asset to superusd.
    /// @param asset The asset to convert.
    /// @param depositAmount The amount to convert.
    /// @return superusdAmount The amount of superusd minted.
    function _convertAssetToSuperUSD(address asset, uint256 depositAmount) internal returns (uint256 superusdAmount) {
        // check approval of asset to superusd
        _checkApproval(asset, superusd, depositAmount);
        // convert asset to superusd
        superusdAmount = TellerWithMultiAssetSupport(superusdTeller).deposit(ERC20(asset), depositAmount, 0); // will revert if asset not supported
    }

    /// @notice Converts ssuperusd to superusd.
    /// @param depositAmount The amount of ssuperusd to convert.
    /// @return superusdAmount The amount of superusd redeemed.
    function _convertSSuperUSDToSuperUSD(uint256 depositAmount) internal returns (uint256 superusdAmount) {
        // check approval of ssuperusd to queue
        _checkApproval(ssuperusd, ssuperusdAtomicQueue, depositAmount);
        // call instantWithdraw on sSuperUSD to get superUSD
        superusdAmount = AtomicQueue(ssuperusdAtomicQueue).instantWithdraw(
            ERC20(ssuperusd),
            ERC20(superusd),
            depositAmount,
            0,
            TellerWithMultiAssetSupport(ssuperusdTeller)
        );
    }

    /// @notice Converts superusd to ssuperusd.
    /// @param amountSSuperUSD The amount of SuperUSD to convert.
    /// @return amountSSuperUSD The amount of sSuperUSD received from the conversion.
    function _convertSuperUSDToSSuperUSD(uint256 amountSuperUSD) internal returns (uint256 amountSSuperUSD) {
        // check approval of superusd to ssuperusd
        _checkApproval(superusd, ssuperusd, amountSuperUSD);
        // convert superusd to ssuperusd
        amountSSuperUSD = TellerWithMultiAssetSupport(ssuperusdTeller).deposit(ERC20(superusd), amountSuperUSD, 0);
    }

    //============================== HELPER FUNCTIONS ===============================

    /// @notice Checks the approval of an ERC20 token from this contract to another address.
    /// @param token The token to check allowance.
    /// @param recipient The address to give allowance to.
    /// @param minAmount The minimum amount of the allowance.
    function _checkApproval(address token, address recipient, uint256 minAmount) internal {
        // If current allowance is insufficient
        if(IERC20(token).allowance(address(this), recipient) < minAmount) {
            // Set allowance to max
            SafeERC20.forceApprove(IERC20(token), recipient, type(uint256).max);
        }
    }
}