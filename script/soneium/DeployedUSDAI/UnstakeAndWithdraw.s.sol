// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SoneiumAddresses} from "test/resources/SoneiumAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {WithdrawZapTeller} from "src/zaps/WithdrawZapTeller.sol";

contract UnstakeAndWithdrawScript is Script, SoneiumAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    WithdrawZapTeller public withdrawZapTeller;
    address public sSuperUSD;

    // User's initial share balance
    uint256 withdrawShares;

    function setUp() public {
        vm.createSelectFork("soneium");
        setSourceChainName("soneium");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        withdrawZapTeller = WithdrawZapTeller(deployer.getAddress(WithdrawZapTellerName));
        sSuperUSD = previoussSuperUSD;
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        
        withdrawShares = 1 * 1e4;
        vm.startBroadcast(privateKey);
        ERC20(sSuperUSD).approve(address(withdrawZapTeller), type(uint256).max);
        withdrawZapTeller.unstakeAndWithdraw(withdrawShares, address(USDC), 0, uint64(block.timestamp + 3600));
        
        vm.stopBroadcast();
    }
}
