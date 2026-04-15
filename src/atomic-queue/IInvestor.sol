// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import { ERC20 } from "@solmate/tokens/ERC20.sol";


interface IInvestor {
    
    /**
     * @notice Manages the vault to free funds
     * @param vaultBalance The current balance of the vault in the want token
     * @param totalRequired The total amount of assets needed
     * @param want The want token
     */
    function autoWithdrawal(uint256 vaultBalance, uint256 totalRequired, ERC20 want) external;

}
