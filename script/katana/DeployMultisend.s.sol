// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Multisend} from "src/helper/Multisend.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {KatanaAddresses} from "test/resources/KatanaAddresses.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/DeployMultisend.s.sol:DeployMultisendScript --with-gas-price 70000000 --evm-version london --broadcast --etherscan-api-key $KATANA_SCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployMultisendScript is Script, ContractNames, KatanaAddresses {
    uint256 public privateKey;

    address public devOwner = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public canSolve = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public admin = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public globalOwner = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    address public owner = dev1Address;

    // Contracts to deploy
    address public multisend = address(0xA7d223bB910442A35be348658EEecA866002e8A3);

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("katana");
    }

    function run() external {
        vm.startBroadcast(privateKey);
        
        console.log("Deployer                :", deployerAddress);

        if(!_isDeployed(multisend)) {
            console.log("Deploying Multisend");
            multisend = address(new Multisend(owner));
            console.log("Deployed Multisend at ", multisend);
        }

        vm.stopBroadcast();
    }

    function _isDeployed(address addr) internal view returns (bool) {
        if(addr == address(0)) return false;
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}