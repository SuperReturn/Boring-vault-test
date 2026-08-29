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
 * @title BoringVault Check State
 * @notice This script checks the contract state and makes any necessary changes
 * @dev Run with: forge script script/minato/Upgrade.s.sol --rpc-url $MINATO_RPC_URL
 */
contract CheckStateScript is Script, EthereumAddresses, ContractNames, MerkleTreeHelper {

    uint8 public constant OWNER_ROLE = 8;

    // Contract instances
    Deployer public deployer;
    
    BoringVault public superusd;
    RolesAuthority public superusdRolesAuthority;

    BoringVault public ssuperusd;
    RolesAuthority public ssuperusdRolesAuthority;

    function setUp() public {
        vm.createSelectFork("mainnet");
        setSourceChainName("mainnet");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        superusd = BoringVault(payable(previoussuperUSD));
        ssuperusd = BoringVault(payable(previoussSuperUSD));

        superusdRolesAuthority = RolesAuthority(deployer.getAddress(UsdaiVaultRolesAuthorityName));
        ssuperusdRolesAuthority = RolesAuthority(deployer.getAddress(sUsdaiVaultRolesAuthorityName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        checkSuperUsdNameAndSymbol();
        checkSSuperUsdNameAndSymbol();

        //checkSuperUsdAuthority();
        //checkSSuperUsdAuthority();

        //checkSuperUsdMaxTotalSupply();
        //checkSSuperUsdMaxTotalSupply();

        //checkSSuperUsdAccountantRate();

        vm.stopBroadcast();
    }

    function checkSuperUsdNameAndSymbol() internal {
        string memory expectedName = "SuperUSD";
        string memory expectedSymbol = "SuperUSD";
        string memory name = superusd.name();
        string memory symbol = superusd.symbol();
        if(!strCmp(name, expectedName) || !strCmp(symbol, expectedSymbol)) {
            console.log("SuperUSD name and/or symbol differs");
            checkSuperUSDCanCallSetName();
            console.log("Setting SuperUSD name and symbol");
            superusd.setNameAndSymbol(expectedName, expectedSymbol);
        }
    }

    function checkSSuperUsdNameAndSymbol() internal {
        string memory expectedName = "Staked SuperUSD";
        string memory expectedSymbol = "sSuperUSD";
        string memory name = ssuperusd.name();
        string memory symbol = ssuperusd.symbol();
        if(!strCmp(name, expectedName) || !strCmp(symbol, expectedSymbol)) {
            console.log("SuperUSD name and/or symbol differs");
            checkSSuperUSDCanCallSetName();
            console.log("Setting sSuperUSD name and symbol");
            ssuperusd.setNameAndSymbol(expectedName, expectedSymbol);
        }
    }

    function checkSuperUSDCanCallSetName() internal {
        bytes4 selector = bytes4(abi.encodeWithSignature("setNameAndSymbol(string,string)"));
        if (
            !superusdRolesAuthority.doesRoleHaveCapability(
                OWNER_ROLE, address(superusd), selector
            )
        ) {
            console.log("Setting SuperUSD authority role capacity setNameAndSymbol");
            superusdRolesAuthority.setRoleCapability(
                OWNER_ROLE,
                address(superusd),
                selector,
                true
            );
        }
    }

    function checkSSuperUSDCanCallSetName() internal {
        bytes4 selector = bytes4(abi.encodeWithSignature("setNameAndSymbol(string,string)"));
        if (
            !ssuperusdRolesAuthority.doesRoleHaveCapability(
                OWNER_ROLE, address(ssuperusd), selector
            )
        ) {
            console.log("Setting sSuperUSD authority role capacity setNameAndSymbol");
            ssuperusdRolesAuthority.setRoleCapability(
                OWNER_ROLE,
                address(ssuperusd),
                selector,
                true
            );
        }
    }

    // returns true if two strings are equal
    function strCmp(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}