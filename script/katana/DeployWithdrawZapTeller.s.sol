// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Deployer} from "src/helper/Deployer.sol";
import {WithdrawZapTeller} from "src/zaps/WithdrawZapTeller.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {KatanaAddresses} from "test/resources/KatanaAddresses.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/DeployZapTellers.s.sol:DeployZapTellers --with-gas-price 70000000 --evm-version london --broadcast --etherscan-api-key $OPTIMISMSCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployWithdrawZapTeller is Script, ContractNames, KatanaAddresses {
    uint256 public privateKey;

    Deployer public deployer = Deployer(deployerAddress);
    address public owner = dev1Address;

    // already deployed contracts
    address public superUSD;
    address public sSuperUSD;
    address public superUSDAtomicQueue;
    address public sSuperUSDAtomicQueue;
    address public superUSDTeller;
    address public sSuperUSDTeller;
    address public superUSDSolver;

    // Contracts to deploy
    address public withdrawZapTeller;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("katana");

        superUSD = address(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);
        sSuperUSD = address(0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd);
        superUSDAtomicQueue = address(0xf3aA6324Aa5C9Ded16Eb7ED651152aC30588BAc1);
        sSuperUSDAtomicQueue = address(0xd484d2991D168b33cC61e25f80af0145883Bc465);
        superUSDTeller = address(0xF62D61F304C9c65C96a94c2b0b93c8f93C96e91D);
        sSuperUSDTeller = address(0xa8aA5c00d6c3f7A77FC5769770f6bC7b9244699b);
        superUSDSolver = address(0x1DB629316B3fB6B026f9ebD5c379a72235a4d5E9);
    }

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.startBroadcast(privateKey);

        withdrawZapTeller = _getAddressIfDeployed(WithdrawZapTellerName);
        console.log("Withdraw Zap Teller  :", withdrawZapTeller);
        if(withdrawZapTeller == address(0)) {
            creationCode = type(WithdrawZapTeller).creationCode;
            constructorArgs = abi.encode(owner, superUSD, sSuperUSD, superUSDAtomicQueue, sSuperUSDAtomicQueue, superUSDTeller, sSuperUSDTeller, superUSDSolver);
            withdrawZapTeller = deployer.deployContract(WithdrawZapTellerName, creationCode, constructorArgs, 0);
        } else {
            withdrawZapTeller = deployer.getAddress(WithdrawZapTellerName);
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