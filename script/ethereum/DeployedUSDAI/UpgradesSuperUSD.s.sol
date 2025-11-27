// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {EthereumAddresses} from "test/resources/EthereumAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";

/**
 * @title BoringVault Upgrade
 * @notice This script demonstrates how to upgrade the BoringVault contract on Minato
 * @dev Run with: forge script script/minato/Upgrade.s.sol --rpc-url $MINATO_RPC_URL
 */
contract UpgradesSuperUSDScript is Script, EthereumAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    BoringVault vault;

    function setUp() public {
        vm.createSelectFork("mainnet");
        setSourceChainName("mainnet");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        vault = BoringVault(payable(previoussSuperUSD));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        RolesAuthority rolesAuthority = RolesAuthority(deployer.getAddress(sUsdaiVaultRolesAuthorityName));
        rolesAuthority.setRoleCapability(
            1,
            address(vault),
            bytes4(abi.encodeWithSignature("upgradeToAndCall(address,bytes)")),
            true
        );
        
        address newImplementation = deployer.deployContract(
            string.concat(sUsdaiVaultName, "-SCVersion-Implementation"),
            type(BoringVault).creationCode,
            hex"",
            0
        );

        vault.upgradeToAndCall(newImplementation, "");

        vm.stopBroadcast();
    }
}