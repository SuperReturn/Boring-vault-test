// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {PlumeAddresses} from "test/resources/PlumeAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {WithdrawZapTeller} from "src/zaps/WithdrawZapTeller.sol";

contract UnstakeAndWithdrawScript is Script, PlumeAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    WithdrawZapTeller public withdrawZapTeller;
    address public sSuperUSD;

    // User's initial share balance
    uint256 withdrawShares;

    function setUp() public {
        vm.createSelectFork("plume");
        setSourceChainName("plume");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        withdrawZapTeller = WithdrawZapTeller(deployer.getAddress(WithdrawZapTellerName));
        sSuperUSD = previoussSuperUSD;
    }

    function run() public {
        uint256 privateKey = vm.envUint("PLUME_STRATEGIST_MERKL");
        address user = vm.addr(privateKey);
        
        withdrawShares = 1 * 1e4;
        vm.startBroadcast(privateKey);
        ERC20(sSuperUSD).approve(address(withdrawZapTeller), type(uint256).max);
        withdrawZapTeller.unstakeAndWithdraw(withdrawShares, address(PUSD), 0, uint64(block.timestamp + 3600));
        
        vm.stopBroadcast();
    }
}
