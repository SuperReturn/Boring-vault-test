// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Multisend} from "src/helper/Multisend.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {KatanaAddresses} from "test/resources/KatanaAddresses.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/UseMultisend.s.sol:UseMultisendScript --with-gas-price 70000000 --evm-version london --broadcast --etherscan-api-key $KATANA_SCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract UseMultisendScript is Script, ContractNames, KatanaAddresses {
    uint256 public privateKey;

    address public devOwner = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public canSolve = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public admin = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public globalOwner = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    address public owner = dev1Address;

    ERC20 public kat = ERC20(0x7F1f4b4b29f5058fA32CC7a97141b8D7e5ABDC2d);
    Multisend public multisend = Multisend(0xA7d223bB910442A35be348658EEecA866002e8A3);

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("katana");
    }

    function run() external {
        vm.startBroadcast(privateKey);
        
        console.log("Deployer                :", deployerAddress);

        // TODO: fill this in with correct values
        uint256 totalAmount = 123;
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](3);
        receivers[0] = Multisend.ReceiverAndAmount(address(1), 100);
        receivers[1] = Multisend.ReceiverAndAmount(address(2), 20);
        receivers[2] = Multisend.ReceiverAndAmount(address(3), 3);

        uint256 allowance = kat.allowance(owner, address(multisend));
        if(allowance < totalAmount) {
            console.log("approving kat to multisend ...");
            kat.approve(address(multisend), type(uint256).max);
            console.log("approved kat to multisend");
        }
        console.log("multisending kat ...");
        multisend.multisend(address(kat), totalAmount, receivers);
        console.log("multisent kat");

        vm.stopBroadcast();
    }
}