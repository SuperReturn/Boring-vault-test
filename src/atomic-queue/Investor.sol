// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ERC4626 } from "@solmate/tokens/ERC4626.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { BoringVault } from "./../base/BoringVault.sol";
import { ISakePool } from "./../interfaces/external/sake/ISakePool.sol";
import { IAToken } from "./../interfaces/external/sake/IAToken.sol";
import { IInvestor } from "./IInvestor.sol";


contract Investor is IInvestor, Auth {

    address public immutable boringVault;

    enum VaultType { ERC4626, AaveV3 }
    struct VaultInfo {
        VaultType vaultType;
        address vault;
    }
    uint256 public numVaults;
    mapping(uint256 index => VaultInfo vaultInfo) internal _vaultInfos;

    error UnsupportedVaultType();
    error Investor__VaultAddressZero();
    error Investor__VaultAddressDuplicate(address vault);
    error Investor__VaultIndexOutOfBounds();

    event VaultsUpdated(uint256 newNumVaults);
    event BoringVaultManaged();

    /**
     * @notice Constructor
     * @param _owner The owner of the contract
     * @param _authority The authority of the contract
     * @param _boringVault The BoringVault contract to use for withdrawal
     */
    constructor(
        address _owner,
        Authority _authority,
        address _boringVault
    ) Auth(_owner, _authority) {
        boringVault = _boringVault;
    }

    /**
     * @notice Sets the list of vaults to withdraw from during autoWithdrawal.
     * @dev Overwrites all existing entries and deletes any stale tail entries.
     * @param vaultInfos The new ordered list of vaults.
     */
    function setVaults(VaultInfo[] calldata vaultInfos) external requiresAuth {
        // check for duplicate vaults
        for (uint256 i = 0; i < vaultInfos.length; i++) {
            address vaultI = vaultInfos[i].vault;
            if (vaultI == address(0)) revert Investor__VaultAddressZero();
            for (uint256 j = i+1; j < vaultInfos.length; j++) {
                if (vaultI == vaultInfos[j].vault) revert Investor__VaultAddressDuplicate(vaultI);
            }
        }
        uint256 newLen = vaultInfos.length;
        uint256 oldLen = numVaults;
        // set the new vaults
        for (uint256 i = 0; i < newLen; i++) {
            _vaultInfos[i] = vaultInfos[i];
        }
        // delete the old vaults
        for (uint256 i = newLen; i < oldLen; i++) {
            delete _vaultInfos[i];
        }
        // set length
        numVaults = newLen;
        // emit event
        emit VaultsUpdated(newLen);
    }

    /**
     * @notice Returns vault info at the given index.
     * @dev Can be enumerated [0, numVaults()-1].
     * @param vaultIndex The index to query.
     * @return vault The vault address.
     * @return vaultType The vault type as uint8.
     */
    function getVaultInfo(uint256 vaultIndex) external view returns (address vault, uint8 vaultType) {
        if (vaultIndex >= numVaults) revert Investor__VaultIndexOutOfBounds();
        VaultInfo memory info = _vaultInfos[vaultIndex];
        vault = info.vault;
        vaultType = uint8(info.vaultType);
    }

    /**
     * @notice Manages the vault to free funds
     * @param vaultBalance The current balance of the vault in the want token
     * @param totalRequired The total amount of assets needed
     * @param want The want token
     */
    function autoWithdrawal(uint256 vaultBalance, uint256 totalRequired, ERC20 want) external override requiresAuth {
        // exit early if the vault has enough funds
        if(vaultBalance >= totalRequired) return;
        // calculate the amount required
        uint256 amountRequired = totalRequired - vaultBalance;
        // free funds
        uint256 len = numVaults;
        // loop through vaults
        for(uint256 vaultIndex = 0; vaultIndex < len; vaultIndex++) {
            // get vault info
            VaultInfo memory vaultInfo = _vaultInfos[vaultIndex];
            // get the balance of the vault
            uint256 vaultTokenBalance = ERC20(vaultInfo.vault).balanceOf(boringVault);
            // skip if the balance is 0
            if(vaultTokenBalance == 0) continue;
            // withdraw
            _withdraw(want, vaultInfo, vaultTokenBalance, amountRequired);
            // get the new vault balance
            vaultBalance = want.balanceOf(boringVault);
            // exit early if the vault has enough funds
            if(vaultBalance >= totalRequired) return;
            // calculate the new amount required
            amountRequired = totalRequired - vaultBalance;
        }
    }

    /**
     * @notice Withdraws assets from the vault
     * @param want The want token
     * @param vaultInfo The vault info
     * @param vaultTokenBalance The balance of the BoringVault in the investment vault token
     * @param amountRequired The amount of assets needed
     */
    function _withdraw(ERC20 want, VaultInfo memory vaultInfo, uint256 vaultTokenBalance, uint256 amountRequired) internal {
        if(vaultInfo.vaultType == VaultType.ERC4626) {
            _withdrawERC4626(want, vaultInfo, vaultTokenBalance, amountRequired);
        }
        else if(vaultInfo.vaultType == VaultType.AaveV3) {
            _withdrawAaveV3(want, vaultInfo, vaultTokenBalance, amountRequired);
        }
        else {
            revert UnsupportedVaultType();
        }
    }

    /**
     * @notice Withdraws assets from an ERC4626 vault
     * @param want The want token
     * @param vaultInfo The vault info
     * @param vaultTokenBalance The balance of the BoringVault in the investment vault token
     * @param amountRequired The amount of assets needed
     */
    function _withdrawERC4626(ERC20 want, VaultInfo memory vaultInfo, uint256 vaultTokenBalance, uint256 amountRequired) internal {
        // try redeem first
        uint256 amountWithdrawn = ERC4626(vaultInfo.vault).previewRedeem(vaultTokenBalance);
        // if lte amount required, redeem full balance
        if(amountWithdrawn <= amountRequired) {
            _manage(vaultInfo.vault, abi.encodeWithSelector(ERC4626.redeem.selector, vaultTokenBalance, boringVault, boringVault));
        }
        // if more than enough, only withdraw what is needed
        else if(amountWithdrawn > amountRequired) {
            _manage(vaultInfo.vault, abi.encodeWithSelector(ERC4626.withdraw.selector, amountRequired, boringVault, boringVault));
        }
    }

    /**
     * @notice Withdraws assets from an Aave V3 pool
     * @param want The want token
     * @param vaultInfo The vault info
     * @param vaultTokenBalance The balance of the BoringVault in the investment vault token
     * @param amountRequired The amount of assets needed
     */
    function _withdrawAaveV3(ERC20 want, VaultInfo memory vaultInfo, uint256 vaultTokenBalance, uint256 amountRequired) internal {
        // only withdraw the amount required
        uint256 amountWithdrawn = Math.min(vaultTokenBalance, amountRequired);
        // get the address of the pool
        address poolAddress = IAToken(vaultInfo.vault).POOL();
        // manage the vault
        _manage(poolAddress, abi.encodeWithSelector(ISakePool.withdraw.selector, address(want), amountWithdrawn, boringVault));
    }

    /**
     * @notice Manages the vault
     * @param target The target of the manage call
     * @param data The data of the manage call
     */
    function _manage(address target, bytes memory data) internal {
        try BoringVault(payable(boringVault)).manage(target, data, 0) {
            // success
            emit BoringVaultManaged();
        } catch {
            // ignore errors, continue to next vault
        }
    }

    /**
     * @notice Calculates the max that can be withdrawn from all vaults
     * @return amount The max amount returned in a withdraw
     */
    function getMaxAutoWithdraw() external view returns (uint256 amount) {
        uint256 len = numVaults;
        // loop through vaults
        for(uint256 vaultIndex = 0; vaultIndex < len; vaultIndex++) {
            // get vault info
            VaultInfo memory vaultInfo = _vaultInfos[vaultIndex];
            // get the balance of the vault
            uint256 vaultTokenBalance = ERC20(vaultInfo.vault).balanceOf(boringVault);
            // skip if the balance is 0
            if(vaultTokenBalance == 0) continue;
            // calculate max withdraw and add to total
            amount += _previewMaxWithdraw(vaultInfo, vaultTokenBalance);
        }
    }

    /**
     * @notice Previews a max withdraw from the vault
     * @param vaultInfo The vault info
     * @param vaultTokenBalance The balance of the BoringVault in the investment vault token
     * @return amount The max amount returned in a withdraw
     */
    function _previewMaxWithdraw(VaultInfo memory vaultInfo, uint256 vaultTokenBalance) internal view returns (uint256 amount) {
        if(vaultInfo.vaultType == VaultType.ERC4626) {
            return _previewMaxWithdrawERC4626(vaultInfo, vaultTokenBalance);
        }
        else if(vaultInfo.vaultType == VaultType.AaveV3) {
            return _previewMaxWithdrawAaveV3(vaultInfo, vaultTokenBalance);
        }
        else {
            revert UnsupportedVaultType();
        }
    }

    /**
     * @notice Previews a max withdraw from an ERC4626 vault
     * @param vaultInfo The vault info
     * @param vaultTokenBalance The balance of the BoringVault in the investment vault token
     * @return amount The max amount returned in a withdraw
     */
    function _previewMaxWithdrawERC4626(VaultInfo memory vaultInfo, uint256 vaultTokenBalance) internal view returns (uint256 amount) {
        // preview redeem of the entire balance
        return ERC4626(vaultInfo.vault).previewRedeem(vaultTokenBalance);
    }

    /**
     * @notice Previews a max withdraw from an Aave V3 pool
     * @param vaultInfo The vault info
     * @param vaultTokenBalance The balance of the BoringVault in the investment vault token
     * @return amount The max amount returned in a withdraw
     */
    function _previewMaxWithdrawAaveV3(VaultInfo memory vaultInfo, uint256 vaultTokenBalance) internal view returns (uint256 amount) {
        // aTokens are 1:1 with the underlying asset
        return vaultTokenBalance;
    }
}
