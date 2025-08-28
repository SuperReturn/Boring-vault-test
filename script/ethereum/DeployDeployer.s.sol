// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Deployer} from "src/helper/Deployer.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/DeployDeployer.s.sol:DeployDeployerScript --with-gas-price 30000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployDeployerScript is Script, ContractNames, MainnetAddresses {
    uint256 public privateKey;

    // Contracts to deploy
    RolesAuthority public rolesAuthority;
    Deployer public deployer;

    uint8 public DEPLOYER_ROLE = 1;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("mainnet");
    }

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        bytes32 DEPLOYER_SALT = keccak256(abi.encode(UsdaiDeployerName));
 
        vm.startBroadcast(privateKey);

        creationCode = type(Deployer).creationCode;
        constructorArgs = abi.encode(dev0Address, Authority(address(0)));
        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
        
        address predictedAddress = computeCreate2Address(DEPLOYER_SALT, keccak256(initCode));
        console.log("Deployer will be deployed at:", predictedAddress);
        
        address deployerAddress = deployWithCreate2(initCode, DEPLOYER_SALT);
        
        require(deployerAddress != address(0), "CREATE2 deployment failed");
        console.log("Deployer successfully deployed at:", deployerAddress);

        deployer = Deployer(deployerAddress);
        creationCode = type(RolesAuthority).creationCode;
        constructorArgs = abi.encode(dev0Address, Authority(address(0)));
        rolesAuthority =
            RolesAuthority(previousRolesAuthority);

        deployer.setAuthority(rolesAuthority);

        rolesAuthority.setRoleCapability(DEPLOYER_ROLE, address(deployer), Deployer.deployContract.selector, true);
        rolesAuthority.setUserRole(dev0Address, DEPLOYER_ROLE, true);
        rolesAuthority.setUserRole(dev1Address, DEPLOYER_ROLE, true);

        vm.stopBroadcast();
    }

    function deployWithCreate2(bytes memory initCode, bytes32 salt) internal returns (address deployedAddress) {
        assembly {
            deployedAddress := create2(0, add(initCode, 0x20), mload(initCode), salt)
            if iszero(deployedAddress) {
                revert(0, 0)
            }
        }
    }
}
