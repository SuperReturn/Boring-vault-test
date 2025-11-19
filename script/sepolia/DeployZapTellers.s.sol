// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Deployer} from "src/helper/Deployer.sol";
import {SSuperusdZapTeller} from "src/zaps/SSuperusdZapTeller.sol";
import {SSuperusdSakeZapTeller} from "src/zaps/SSuperusdSakeZapTeller.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {SepoliaAddresses} from "test/resources/SepoliaAddresses.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/DeployZapTellers.s.sol:DeployZapTellers --with-gas-price 70000000 --evm-version london --broadcast --etherscan-api-key $OPTIMISMSCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployZapTellers is Script, ContractNames, SepoliaAddresses {
    uint256 public privateKey;

    address public devOwner = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public canSolve = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public admin = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public globalOwner = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    Deployer public deployer = Deployer(deployerAddress);
    address public owner = dev1Address;

    // already deployed contracts
    address public superusd;
    address public ssuperusd;
    address public superusdTeller;
    address public ssuperusdTeller;
    address public sakePool = address(0); // set these if sake is deployed on this network
    address public assuperusd = address(0);

    // Contracts to deploy
    address public ssuperusdZapTeller;
    address public ssuperusdSakeZapTeller;

    // Roles
    uint8 public constant CAN_SOLVE_ROLE = 31;
    uint8 public constant ONLY_QUEUE_ROLE = 32;
    uint8 public constant ADMIN_ROLE = 33;
    uint8 public constant INSTANT_WITHDRAW_ROLE = 34;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("sepolia");
    }

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.startBroadcast(privateKey);

        superusd = _getAddressIfDeployed(UsdaiVaultName);
        ssuperusd = _getAddressIfDeployed(sUsdaiVaultName);
        superusdTeller = _getAddressIfDeployed(UsdaiVaultTellerName);
        ssuperusdTeller = _getAddressIfDeployed(sUsdaiVaultTellerName);

        bool areDependenciesDeployed = true;
        if(superusd == address(0)) {
            console.log("SuperUSD not deployed yet");
            areDependenciesDeployed = false;
        }
        if(ssuperusd == address(0)) {
            console.log("sSuperUSD not deployed yet");
            areDependenciesDeployed = false;
        }
        if(superusdTeller == address(0)) {
            console.log("SuperUSD Teller not deployed yet");
            areDependenciesDeployed = false;
        }
        if(ssuperusdTeller == address(0)) {
            console.log("sSuperUSD Teller not deployed yet");
            areDependenciesDeployed = false;
        }
        if(!areDependenciesDeployed) {
            console.log("Deploy the dependencies first");
            vm.stopBroadcast();
            return;
        }

        ssuperusdZapTeller = _getAddressIfDeployed(sSuperUSDZapTellerName);
        if(ssuperusdZapTeller == address(0)) {
            creationCode = type(SSuperusdZapTeller).creationCode;
            constructorArgs = abi.encode(owner, superusd, ssuperusd, superusdTeller, ssuperusdTeller);
            ssuperusdZapTeller = deployer.deployContract(sSuperUSDZapTellerName, creationCode, constructorArgs, 0);
        } else {
            ssuperusdZapTeller = deployer.getAddress(sSuperUSDZapTellerName);
        }

        if(sakePool == address(0)) {
            console.log("Sake pool not deployed on this network");
            areDependenciesDeployed = false;
        }
        if(assuperusd == address(0)) {
            console.log("asSuperUSD not deployed on this network");
            areDependenciesDeployed = false;
        }
        if(!areDependenciesDeployed) {
            console.log("Skip deploying SSuperUSDSakeZapTeller");
            vm.stopBroadcast();
            return;
        }
        
        ssuperusdSakeZapTeller = _getAddressIfDeployed(sSuperUSDSakeZapTellerName);
        if(ssuperusdSakeZapTeller == address(0)) {
            creationCode = type(SSuperusdSakeZapTeller).creationCode;
            constructorArgs = abi.encode(owner, superusd, ssuperusd, superusdTeller, ssuperusdTeller, sakePool, assuperusd);
            ssuperusdSakeZapTeller = deployer.deployContract(sSuperUSDSakeZapTellerName, creationCode, constructorArgs, 0);
        } else {
            ssuperusdSakeZapTeller = deployer.getAddress(sSuperUSDSakeZapTellerName);
        }

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