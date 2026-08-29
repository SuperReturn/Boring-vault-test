// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ChainValues} from "test/resources/ChainValues.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {OPAddresses} from "test/resources/OPAddresses.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerklDropDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/MerklDropDecoderAndSanitizer.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/DeployDecoderAndSanitizer.s.sol:DeployDecoderAndSanitizerScript --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify --with-gas-price 30000000000
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */

contract DeployMerklDropDecoderAndSanitizerScript is Script, ContractNames, OPAddresses, MerkleTreeHelper {
    uint256 public privateKey;
    Deployer public deployer = Deployer(deployerAddress);
    //Deployer public bobDeployer = Deployer(0xF3d0672a91Fd56C9ef04C79ec67d60c34c6148a0); 

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("optimism");
        setSourceChainName("optimism"); 
    }

    function run() external {
        bytes memory creationCode; bytes memory constructorArgs;
        vm.startBroadcast(privateKey);
    

        //creationCode = type(EtherFiLiquidEthDecoderAndSanitizer).creationCode;
        //constructorArgs = abi.encode(getAddress(sourceChain, "uniswapV3NonFungiblePositionManager"), getAddress(sourceChain, "odosRouterV2"));
        //deployer.deployContract("EtherFi Liquid ETH Decoder And Sanitizer V0.9", creationCode, constructorArgs, 0);


        creationCode = type(MerklDropDecoderAndSanitizer).creationCode;
        constructorArgs = abi.encode(
            deployer.getAddress(UsdaiVaultName)
        );
        deployer.deployContract(UsdaiMerklDropDecoderAndSanitizerName, creationCode, constructorArgs, 0);

        vm.stopBroadcast();
    }
}
