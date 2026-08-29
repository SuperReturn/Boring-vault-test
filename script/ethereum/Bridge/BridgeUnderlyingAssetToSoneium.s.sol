// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {LayerZeroTeller} from "src/base/Roles/CrossChain/Bridges/LayerZero/LayerZeroTeller.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {EthereumAddresses} from "test/resources/EthereumAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {IStargatePool} from "src/interfaces/IStargatePool.sol";
import {console} from "forge-std/console.sol";

/**
 * @title USDAI Deposit Integration Test
 * @notice This script demonstrates how to deposit USDC and ASTR into the USDAI vault on Minato
 * @dev Run with: forge script script/USDAIIntegrationTest/Deposit.sol --rpc-url $MINATO_RPC_URL
 */
contract BridgeUnderlyingAssetToSoneiumScript is Script, EthereumAddresses, ContractNames, MerkleTreeHelper {
    Deployer public deployer;
    BoringVault vault;
    address stargatePoolUSDC = address(0xc026395860Db2d07ee33e05fE50ed7bD583189C7);

    uint256 public sharesToBridge = 1e3;
    ERC20 internal constant NATIVE_ERC20 = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    function setUp() public {
        vm.createSelectFork("mainnet");
        setSourceChainName("mainnet");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        vault = BoringVault(payable(previoussuperUSD));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        IStargatePool.SendParam memory sendParam = IStargatePool.SendParam({
            dstEid: uint32(layerZeroSoneiumEndpointId),
            to: bytes32(uint256(uint160(address(vault)))),
            amountLD: sharesToBridge,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        IStargatePool.MessagingFee memory fee = IStargatePool(stargatePoolUSDC).quoteSend(
            sendParam,
            false
        );

        //  IStargatePool(stargatePoolUSDC).send{value: fee.nativeFee}(
        //     sendParam,
        //     fee,
        //     vm.addr(privateKey)
        // );

        uint256 opsAmt = 2;
        address[] memory targets = new address[](opsAmt);
        targets[0] = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        targets[1] = address(stargatePoolUSDC);

        bytes[] memory targetData = new bytes[](opsAmt);
        targetData[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(stargatePoolUSDC),
            sharesToBridge
        );
        targetData[1] = abi.encodeWithSignature(
            "send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)",
            sendParam,
            fee,
            address(vault)  
        );       

        uint256[] memory values = new uint256[](opsAmt);  
        values[0] = 0;    
        values[1] = fee.nativeFee;    

        console.log("fee.nativeFee", fee.nativeFee);

        (bool sent, ) = address(vault).call{value: fee.nativeFee}("");
        require(sent, "Failed to fund vault");

        vault.manage(targets, targetData, values);

        vm.stopBroadcast();
    }
}