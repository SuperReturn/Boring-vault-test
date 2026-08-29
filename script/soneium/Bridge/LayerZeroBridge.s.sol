// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {LayerZeroTeller} from "src/base/Roles/CrossChain/Bridges/LayerZero/LayerZeroTeller.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {SoneiumAddresses} from "test/resources/SoneiumAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {console} from "forge-std/console.sol";

/**
 * @title USDAI Deposit Integration Test
 * @notice This script demonstrates how to deposit USDC and ASTR into the USDAI vault on Minato
 * @dev Run with: forge script script/USDAIIntegrationTest/Deposit.sol --rpc-url $MINATO_RPC_URL
 */
contract USDAILayerZeroBridgeScript is Script, SoneiumAddresses, ContractNames, MerkleTreeHelper {
    Deployer public deployer;
    BoringVault vault;
    address public sourceTellerAddress;
    address public destinationTellerAddress = address(0x9c75926BBfAAf2de125438a75269541218211a5F);
    ILayerZeroEndpointV2 endpoint;
    LayerZeroTeller sourceTeller;
    LayerZeroTeller destinationTeller;
    AccountantWithRateProviders accountant;
    RolesAuthority rolesAuthority;

    uint256 public sharesToBridge = 1e3;
    ERC20 internal constant NATIVE_ERC20 = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 public expectedFee = 1e18;
    uint8 public constant MINTER_ROLE = 2;
    uint8 public constant BURNER_ROLE = 3;

    function setUp() public {
        vm.createSelectFork("soneium");
        setSourceChainName("soneium");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        endpoint = ILayerZeroEndpointV2(0x4bCb6A963a9563C33569D7A512D35754221F3A19);
        vault = BoringVault(payable(previoussSuperUSD));
        sourceTellerAddress = deployer.getAddress(UsdaiLayerZeroTellerName);
        sourceTeller = LayerZeroTeller(sourceTellerAddress);
        accountant = AccountantWithRateProviders(deployer.getAddress(UsdaiVaultAccountantName));
        rolesAuthority = RolesAuthority(deployer.getAddress(UsdaiVaultRolesAuthorityName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        // bridge setup
        // sourceTeller.addChain(layerZeroMainnetEndpointId, true, true, destinationTellerAddress, 1000000);
        // sourceTeller.addChain(layerZeroArbitrumEndpointId, true, true, destinationTellerAddress, 1000000);
        // sourceTeller.allowMessagesFromChain(layerZeroMainnetEndpointId, destinationTellerAddress);
        // sourceTeller.allowMessagesToChain(layerZeroMainnetEndpointId, destinationTellerAddress, 1000000);
        // sourceTeller.allowMessagesFromChain(layerZeroArbitrumEndpointId, destinationTellerAddress);
        // sourceTeller.allowMessagesToChain(layerZeroArbitrumEndpointId, destinationTellerAddress, 1000000);

        // sourceTeller.setAuthority(rolesAuthority);
        // rolesAuthority.setUserRole(address(sourceTeller), MINTER_ROLE, true);
        // rolesAuthority.setUserRole(address(sourceTeller), BURNER_ROLE, true);
        // rolesAuthority.setPublicCapability(
        //     address(sourceTeller), sourceTeller.bridge.selector, true
        // );
        // rolesAuthority.setPublicCapability(
        //     address(sourceTeller), sourceTeller.depositAndBridge.selector, true
        // );

        // sourceTeller.setChainGasLimit(layerZeroMainnetEndpointId, 100000);

        uint256 fee = sourceTeller.previewFee(uint96(sharesToBridge), vm.addr(privateKey), abi.encode(layerZeroMainnetEndpointId), NATIVE_ERC20);

        console.log("fee", fee);
        sourceTeller.bridge{value: fee}(uint96(sharesToBridge), vm.addr(privateKey), abi.encode(layerZeroMainnetEndpointId), NATIVE_ERC20, expectedFee);
        
        // uint8 OWNER_ROLE = 1;
        // rolesAuthority.setRoleCapability(
        //     OWNER_ROLE, address(sourceTeller), sourceTeller.updateAssetData.selector, true
        // );

        // sourceTeller.updateAssetData(USDC, true, true, 0);

        // USDC.approve(address(vault), sharesToBridge);

        sourceTeller.depositAndBridge{value: fee}(
            USDC,                    
            sharesToBridge,                   // Amount to deposit
            0,                              // Minimum shares to receive (0 for no minimum)
            vm.addr(privateKey),            // Address to receive shares on destination chain
            abi.encode(layerZeroMainnetEndpointId), // LayerZero destination chain ID
            NATIVE_ERC20,                   // Pay fee in native token
            fee                             // Maximum fee to pay
        );

        vm.stopBroadcast();
    }
}