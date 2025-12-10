// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {AccountantWithRateProviders2} from "src/base/Roles/AccountantWithRateProviders2.sol";
import {KatanaAddresses} from "test/resources/KatanaAddresses.sol";
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
contract CheckStateScript is Script, KatanaAddresses, ContractNames, MerkleTreeHelper {

    // Roles
    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant MINTER_ROLE = 2;
    uint8 public constant BURNER_ROLE = 3;
    uint8 public constant MANAGER_INTERNAL_ROLE = 4;
    uint8 public constant SOLVER_ROLE = 12;
    uint8 public constant OWNER_ROLE = 8;
    uint8 public constant MULTISIG_ROLE = 9;
    uint8 public constant STRATEGIST_MULTISIG_ROLE = 10;
    uint8 public constant STRATEGIST_ROLE = 7;
    uint8 public constant UPDATE_EXCHANGE_RATE_ROLE = 11;

    // Contract instances
    Deployer public deployer;
    
    BoringVault public superusd;
    RolesAuthority public superusdRolesAuthority;
    AccountantWithRateProviders2 public superusdAccountant;

    BoringVault public ssuperusd;
    RolesAuthority public ssuperusdRolesAuthority;
    AccountantWithRateProviders public ssuperusdAccountant;

    function setUp() public {
        vm.createSelectFork("katana");
        setSourceChainName("katana");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        superusd = BoringVault(payable(previoussuperUSD));
        ssuperusd = BoringVault(payable(previoussSuperUSD));

        superusdRolesAuthority = RolesAuthority(deployer.getAddress(UsdaiVaultRolesAuthorityName));
        ssuperusdRolesAuthority = RolesAuthority(deployer.getAddress(sUsdaiVaultRolesAuthorityName));

        superusdAccountant = AccountantWithRateProviders2(deployer.getAddress(UsdaiVaultAccountantName));
        ssuperusdAccountant = AccountantWithRateProviders(deployer.getAddress(sUsdaiVaultAccountantName));

        if(address(superusd) == address(0)) revert ("Error getting SuperUSD address");
        if(address(ssuperusd) == address(0)) revert ("Error getting sSuperUSD address");

        if(address(superusdRolesAuthority) == address(0)) revert ("Error getting SuperUSD RolesAuthority address");
        if(address(ssuperusdRolesAuthority) == address(0)) revert ("Error getting sSuperUSD RolesAuthority address");

        if(address(superusdAccountant) == address(0)) revert ("Error getting SuperUSD Accountant address");
        if(address(ssuperusdAccountant) == address(0)) revert ("Error getting sSuperUSD Accountant address");
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        //checkSuperUsdNameAndSymbol();
        //checkSSuperUsdNameAndSymbol();

        //checkSuperUsdAuthority();
        //checkSSuperUsdAuthority();

        //checkSuperUsdMaxTotalSupply();
        //checkSSuperUsdMaxTotalSupply();

        //checkSSuperUsdAccountantRate();

        //checkSuperUsdAccountantYieldDistributor();

        //checkSuperUsdAccountantUpdateExchangeRateRole();
        //checkSSuperUsdAccountantUpdateExchangeRateRole();

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

    function checkSuperUsdAccountantYieldDistributor() internal {
        (, address yieldDistributor) = superusdAccountant.fixedRateAccountantState();
        address expectedYieldDistributor = address(0xbc6d5867635f1c87bbD64e8Ab3E1cFd18B0f3201);
        if (yieldDistributor != expectedYieldDistributor) {
            console.log("Setting SuperUSD accountant yield distributor");
            superusdAccountant.setYieldDistributor(expectedYieldDistributor);
        }
    }

    function checkSuperUsdAccountantUpdateExchangeRateRole() internal {
        address updater = address(0x1A7fEA39D94de24df87B35853ed3b6AF82CF22E7);
        bytes32 userRoles = superusdRolesAuthority.getUserRoles(updater);
        bool hasUpdaterRole = (userRoles & bytes32(1 << UPDATE_EXCHANGE_RATE_ROLE)) != 0;
        if(!hasUpdaterRole) {
            console.log("Setting SuperUSD accountant update exchange rate role");
            superusdRolesAuthority.setUserRole(updater, UPDATE_EXCHANGE_RATE_ROLE, true);
        }

        bytes4 selector = bytes4(abi.encodeWithSignature("updateExchangeRate(uint96)"));
        bool canCall = superusdRolesAuthority.canCall(updater, address(superusdAccountant), selector);
        if(!canCall) {
            console.log("Updater still cannot call superusdAccountant.updateExchangeRate(uint96)");
        }
    }

    function checkSSuperUsdAccountantUpdateExchangeRateRole() internal {
        address updater = address(0x1A7fEA39D94de24df87B35853ed3b6AF82CF22E7);
        bytes32 userRoles = ssuperusdRolesAuthority.getUserRoles(updater);
        bool hasUpdaterRole = (userRoles & bytes32(1 << UPDATE_EXCHANGE_RATE_ROLE)) != 0;
        if(!hasUpdaterRole) {
            console.log("Setting sSuperUSD accountant update exchange rate role");
            ssuperusdRolesAuthority.setUserRole(updater, UPDATE_EXCHANGE_RATE_ROLE, true);
        }

        bytes4 selector = bytes4(abi.encodeWithSignature("updateExchangeRate(uint96)"));
        bool canCall = ssuperusdRolesAuthority.canCall(updater, address(ssuperusdAccountant), selector);
        if(!canCall) {
            console.log("Updater still cannot call ssuperusdAccountant.updateExchangeRate(uint96)");
        }
    }
}