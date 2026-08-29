// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {AirVault} from "src/base/AirVault.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {KatanaBokutoAddresses} from "test/resources/KatanaBokutoAddresses.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/DeployKatSuperUSD.s.sol:DeployKatSuperUSDScript --with-gas-price 70000000 --evm-version london --broadcast --etherscan-api-key $KATANA_BOKUTO_SCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployKatSuperUSDScript is Script, ContractNames, KatanaBokutoAddresses {
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
    address public ssuperusdAtomicQueue;
    address public superusdRolesAuthority;

    // Contracts to deploy
    address public airVault;
    address public airVaultImpl;

    address public airVaultExpected = address(0xd6619fbD8F8a02D8eF71B35723d0E7C5C3878f01);
    address public airVaultImplExpected = address(0x05Af96873Fc2a21d743F136ca643a1295ff8C558);

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("katanabokuto");
    }

    function run() external {
        vm.startBroadcast(privateKey);
        
        superusd = address(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);
        ssuperusd = address(0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd);
        superusdTeller = address(0xF62D61F304C9c65C96a94c2b0b93c8f93C96e91D);
        ssuperusdTeller = address(0xa8aA5c00d6c3f7A77FC5769770f6bC7b9244699b);
        ssuperusdAtomicQueue = address(0xd484d2991D168b33cC61e25f80af0145883Bc465);
        superusdRolesAuthority = address(0x0953c2E6c82633CdA982E90A6287f66493c5cF0B);
        
        console.log("Deployer                :", deployerAddress);
        console.log("SuperUSD                :", superusd);
        console.log("sSuperUSD               :", ssuperusd);
        console.log("SuperUSD Teller         :", superusdTeller);
        console.log("sSuperUSD Teller        :", ssuperusdTeller);
        console.log("sSuperUSD AtomicQueue   :", ssuperusdAtomicQueue);
        console.log("SuperUSD RolesAuthority :", superusdRolesAuthority);

        bool areDependenciesDeployed = true;
        if(!_isDeployed(superusd)) {
            console.log("SuperUSD not deployed yet");
            areDependenciesDeployed = false;
        }
        if(!_isDeployed(ssuperusd)) {
            console.log("sSuperUSD not deployed yet");
            areDependenciesDeployed = false;
        }
        if(!_isDeployed(superusdTeller)) {
            console.log("SuperUSD Teller not deployed yet");
            areDependenciesDeployed = false;
        }
        if(!_isDeployed(ssuperusdTeller)) {
            console.log("sSuperUSD Teller not deployed yet");
            areDependenciesDeployed = false;
        }
        if(!_isDeployed(ssuperusdAtomicQueue)) {
            console.log("sSuperUSD Atomic Queue not deployed yet");
            areDependenciesDeployed = false;
        }
        if(!_isDeployed(superusdRolesAuthority)) {
            console.log("SuperUSD Roles Authority not deployed yet");
            areDependenciesDeployed = false;
        }
        if(!areDependenciesDeployed) {
            console.log("Deploy the dependencies first");
            vm.stopBroadcast();
            return;
        }

        string memory airVaultImplName = string.concat(airVaultName, "-Implementation");
        airVaultImpl = _getAddressIfDeployed(airVaultImplName);
        airVault = _getAddressIfDeployed(airVaultName);

        if(airVaultImpl == address(0)) {
            console.log("Deploying AirVault implementation");
            airVaultImpl = deployer.deployContract(
                airVaultImplName,
                type(AirVault).creationCode,
                abi.encode(address(superusd), address(ssuperusd), address(superusdTeller), address(ssuperusdTeller), address(ssuperusdAtomicQueue)),
                0
            );
            console.log("Deployed AirVault implementation at ", airVaultImpl);
            if(airVaultImplExpected != address(0) && airVaultImpl != airVaultImplExpected) {
                console.log("Incorrect AirVault implementation address. Expected", airVaultImplExpected, "got", airVaultImpl);
                revert("Incorrect AirVault implementation address");
            }
        }

        if(airVault == address(0)) {
            console.log("Deploying AirVault proxy");
            // Prepare initializer data
            bytes memory initializer = abi.encodeWithSelector(
                AirVault.initialize.selector,
                devOwner,  // owner
                Authority(superusdRolesAuthority),  // authority
                "katSuperUSD", // name
                "katSuperUSD",  // symbol
                6  // decimals
            );

            // Deploy proxy
            bytes memory proxyCreationCode = abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(airVaultImpl, initializer)
            );
            airVault = deployer.deployContract(
                airVaultName,
                proxyCreationCode,
                hex"",
                0
            );
            console.log("Deployed AirVault at ", airVault);
            if(airVaultExpected != address(0) && airVault != airVaultExpected) {
                console.log("Incorrect AirVault address. Expected", airVaultExpected, "got", airVault);
                revert("Incorrect AirVault address");
            }
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

    function _isDeployed(address addr) internal view returns (bool) {
        if(addr == address(0)) return false;
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}