// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {KatanaBokutoAddresses} from "test/resources/KatanaBokutoAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";

/**
 * @title BoringVault Upgrade
 * @notice This script demonstrates how to upgrade the BoringVault contract on Minato
 * @dev Run with: forge script script/minato/Upgrade.s.sol --rpc-url $KATANA_BOKUTO_RPC_URL
 */
contract UpgradeScript is Script, KatanaBokutoAddresses, ContractNames, MerkleTreeHelper {
    // Contract instances
    Deployer public deployer;
    BoringVault vault;

    function setUp() public {
        vm.createSelectFork("katanabokuto");
        setSourceChainName("katanabokuto");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        vault = BoringVault(payable(previoussuperUSD));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        RolesAuthority rolesAuthority = RolesAuthority(deployer.getAddress(UsdaiVaultRolesAuthorityName));
        rolesAuthority.setRoleCapability(
            1,
            address(vault),
            bytes4(abi.encodeWithSignature("upgradeToAndCall(address,bytes)")),
            true
        );
        
        address newImplementation = deployer.deployContract(
            string.concat(UsdaiVaultName, "-SCVersion-Implementation"),
            type(BoringVault).creationCode,
            hex"",
            0
        );
        console.log("Deployed new vault impl at ", newImplementation);
        if(newImplementation != 0xe9460F59824a047cCCd794af254c8A467c6D05fa) {
            console.log("Incorrect SuperUSD vault implementation address. Expected", 0xe9460F59824a047cCCd794af254c8A467c6D05fa, "got", newImplementation);
            revert("Incorrect SuperUSD vault implementation address");
        }

        vault.upgradeToAndCall(newImplementation, "");

        vm.stopBroadcast();
    }
}