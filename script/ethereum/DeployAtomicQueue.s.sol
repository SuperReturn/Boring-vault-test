// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {AtomicQueue} from "src/atomic-queue/AtomicQueue.sol";
import {AtomicSolverV4} from "src/atomic-queue/AtomicSolverV4.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {EthereumAddresses} from "test/resources/EthereumAddresses.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/DeployAtomicQueue.s.sol:DeployAtomicQueueScript --with-gas-price 70000000 --evm-version london --broadcast --etherscan-api-key $OPTIMISMSCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployAtomicQueueScript is Script, ContractNames, EthereumAddresses {
    uint256 public privateKey;

    address public devOwner = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public canSolve = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public admin = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;
    address public globalOwner = 0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4;

    // Contracts to deploy
    Deployer public deployer = Deployer(deployerAddress);
    RolesAuthority public rolesAuthority;
    AtomicQueue public atomicQueue;
    AtomicSolverV4 public atomicSolver;
    address public owner = dev1Address;

    // Roles
    uint8 public constant CAN_SOLVE_ROLE = 31;
    uint8 public constant ONLY_QUEUE_ROLE = 32;
    uint8 public constant ADMIN_ROLE = 33;
    uint8 public constant INSTANT_WITHDRAW_ROLE = 34;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("mainnet");
    }

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.startBroadcast(privateKey);

        address deployedAddress = _getAddressIfDeployed(UsdaiBoringOnChainQueuesRolesAuthorityName);
        if (deployedAddress == address(0)) {
            creationCode = type(RolesAuthority).creationCode;
            constructorArgs = abi.encode(owner, Authority(address(0)));
            rolesAuthority =
                RolesAuthority(deployer.deployContract(UsdaiBoringOnChainQueuesRolesAuthorityName, creationCode, constructorArgs, 0));
        } else {
            rolesAuthority = RolesAuthority(deployer.getAddress(UsdaiBoringOnChainQueuesRolesAuthorityName));
        }
        creationCode = type(AtomicSolverV4).creationCode;
        constructorArgs = abi.encode(owner, rolesAuthority);
        atomicSolver = AtomicSolverV4(deployer.deployContract(UsdaiVaultQueueSolverName, creationCode, constructorArgs, 0));

        creationCode = type(AtomicQueue).creationCode;
        address accountant = _getAddressIfDeployed(UsdaiVaultAccountantName);
        constructorArgs = abi.encode(owner, rolesAuthority, accountant, address(atomicSolver));
        atomicQueue = AtomicQueue(deployer.deployContract(UsdaiVaultQueueName, creationCode, constructorArgs, 0));

        // set RolesAuthority
        rolesAuthority.setUserRole(canSolve, CAN_SOLVE_ROLE, true);
        rolesAuthority.setUserRole(admin, ADMIN_ROLE, true);
        rolesAuthority.transferOwnership(globalOwner);
        
        // Give Queue the OnlyQueue role.
        rolesAuthority.setUserRole(address(atomicQueue), ONLY_QUEUE_ROLE, true);
        rolesAuthority.setUserRole(address(atomicSolver), CAN_SOLVE_ROLE, true);

        rolesAuthority.setRoleCapability(ONLY_QUEUE_ROLE, address(atomicQueue), AtomicQueue.setMaturityTime.selector, true);
        rolesAuthority.setRoleCapability(ONLY_QUEUE_ROLE, address(atomicQueue), AtomicQueue.setDiscount.selector, true);
        rolesAuthority.setRoleCapability(ONLY_QUEUE_ROLE, address(atomicQueue), AtomicQueue.addToWhitelist.selector, true);
        rolesAuthority.setRoleCapability(ONLY_QUEUE_ROLE, address(atomicQueue), AtomicQueue.removeFromWhitelist.selector, true);
        rolesAuthority.setRoleCapability(ONLY_QUEUE_ROLE, address(atomicQueue), AtomicQueue.updateWhitelistMaturityDivisor.selector, true);
        rolesAuthority.setRoleCapability(INSTANT_WITHDRAW_ROLE, address(atomicQueue), AtomicQueue.instantWithdraw.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.setSolver.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.cancelAtomicRequestByAdmin.selector, true);
        rolesAuthority.setRoleCapability(ONLY_QUEUE_ROLE, address(atomicSolver), AtomicSolverV4.finishSolve.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicSolver), AtomicSolverV4.rescueTokens.selector, true);
        rolesAuthority.setRoleCapability(ONLY_QUEUE_ROLE, address(atomicSolver), AtomicSolverV4.approveOfferForQueue.selector, true);
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.updateAtomicRequest.selector, true);
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.cancelAtomicRequest.selector, true);
        rolesAuthority.setPublicCapability(address(atomicSolver), AtomicSolverV4.redeemSolve.selector, true);

        // extra setting
        // atomicQueue.setMaturityTime(3 minutes);

        // extra role setting for other contracts
        RolesAuthority vaultRolesAuthority = RolesAuthority(deployer.getAddress(UsdaiVaultRolesAuthorityName));
        vaultRolesAuthority.setUserRole(address(atomicSolver), 12, true); // 12: solver role
        vaultRolesAuthority.setUserRole(address(atomicQueue), 12, true); // 12: solver role
        vaultRolesAuthority.setUserRole(deployer.getAddress(UsdaiVaultTellerName), 3, true); // 3: buy role
        // vaultRolesAuthority.setUserRole(deployer.getAddress(UsdaiLayerZeroTellerName), 3, true); // 3: buy role
        // vaultRolesAuthority.setUserRole(deployer.getAddress(UsdaiChainlinkCCIPTellerName), 3, true); // 3: buy role
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