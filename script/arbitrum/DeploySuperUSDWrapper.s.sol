// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Deployer} from "src/helper/Deployer.sol";
import {SuperUSDWrapper} from "src/wrappers.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {ArbitrumAddresses} from "test/resources/ArbitrumAddresses.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 * source .env && forge script script/arbitrum/DeploySuperUSDWrapper.s.sol:DeploySuperUSDWrapper --with-gas-price 70000000 --evm-version london --broadcast --etherscan-api-key $ARBISCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeploySuperUSDWrapper is Script, ContractNames, ArbitrumAddresses {
    uint256 public privateKey;

    Deployer public deployer = Deployer(deployerAddress);
    address public owner = dev1Address;

    address public queue = 0xf3aA6324Aa5C9Ded16Eb7ED651152aC30588BAc1;
    address public aeonPay = 0xF91F479Ea9A1efeCBeD6f9E4CF195BA17c36333D;

    address public superUSDWrapper;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("arbitrum");
    }

    function run() external {
        RolesAuthority rolesAuthority = RolesAuthority(deployer.getAddress(RolesAuthorityName));
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.startBroadcast(privateKey);

        superUSDWrapper = _getAddressIfDeployed(SuperUSDWrapperName);
        console.log("SuperUSD Wrapper:", superUSDWrapper);
        if (superUSDWrapper == address(0)) {
            creationCode = type(SuperUSDWrapper).creationCode;
            constructorArgs = abi.encode(owner, Authority(address(0)), queue, aeonPay);
            superUSDWrapper = deployer.deployContract(SuperUSDWrapperName, creationCode, constructorArgs, 0);
            console.log("SuperUSD Wrapper deployed at:", superUSDWrapper);
        } else {
            superUSDWrapper = deployer.getAddress(SuperUSDWrapperName);
            console.log("SuperUSD Wrapper already deployed at:", superUSDWrapper);
        }

        // Set SuperUSDWrapper as INSTANT_WITHDRAW_ROLE (34)
        rolesAuthority.setUserRole(superUSDWrapper, 34, true);

        vm.stopBroadcast();
    }

    function _getAddressIfDeployed(string memory name) internal view returns (address) {
        address deployedAt = deployer.getAddress(name);
        uint256 size;
        assembly {
            size := extcodesize(deployedAt)
        }
        return size > 0 ? deployedAt : address(0);
    }
}
