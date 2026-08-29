// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;


interface IAToken {

    function POOL() external view returns (address);
    
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    
}
