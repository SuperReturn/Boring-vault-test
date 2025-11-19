// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {DeployArcticArchitecture2, ERC20, Deployer} from "script/ArchitectureDeployments/DeployArcticArchitecture2.sol";
import {AddressToBytes32Lib} from "src/helper/AddressToBytes32Lib.sol";
import {PlumeTestnetAddresses} from "test/resources/PlumeTestnetAddresses.sol";

// Import Decoder and Sanitizer to deploy.
import {ITBPositionDecoderAndSanitizer} from
    "src/base/DecodersAndSanitizers/Protocols/ITB/ITBPositionDecoderAndSanitizer.sol";

/**
 *  source .env && forge script script/ArchitectureDeployments/DeployTestVault.s.sol:DeployTestVaultScript --with-gas-price 30000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployTestVaultScript is DeployArcticArchitecture2, PlumeTestnetAddresses {
    using AddressToBytes32Lib for address;

    uint256 public privateKey;

    // Deployment parameters
    string public boringVaultName = "SuperUSD";
    string public boringVaultSymbol = "SuperUSD";
    uint8 public boringVaultDecimals = 6;
    address public owner = dev0Address;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("plume");
    }

    function run() external {
        // Define names to determine where contracts are deployed.
        names.rolesAuthority = UsdaiVaultRolesAuthorityName;
        names.lens = UsdaiArcticArchitectureLensName;
        names.boringVault = UsdaiVaultName;
        names.manager = UsdaiVaultManagerName;
        names.accountant = UsdaiVaultAccountantName;
        names.teller = UsdaiVaultTellerName;
        names.rawDataDecoderAndSanitizer = UsdaiVaultDecoderAndSanitizerName;
        names.delayedWithdrawer = UsdaiVaultDelayedWithdrawer;

        configureDeployment.deployContracts = true;
        configureDeployment.setupRoles = true;
        configureDeployment.setupDepositAssets = true;
        configureDeployment.setupWithdrawAssets = true;
        configureDeployment.finishSetup = true;
        configureDeployment.setupTestUser = true;
        configureDeployment.saveDeploymentDetails = true;
        configureDeployment.deployerAddress = deployerAddress;
        // configureDeployment.balancerVault = balancerVault;
        // configureDeployment.WETH = address(WETH);

        // Save deployer.
        deployer = Deployer(configureDeployment.deployerAddress);

        // Define Accountant Parameters.
        accountantParameters.payoutAddress = liquidPayoutAddress;
        accountantParameters.base = PUSD;
        // Decimals are in terms of `base`.
        accountantParameters.startingExchangeRate = 1e6;
        //  4 decimals
        accountantParameters.managementFee = 0;
        accountantParameters.performanceFee = 0;
        accountantParameters.allowedExchangeRateChangeLower = 0.995e4;
        accountantParameters.allowedExchangeRateChangeUpper = 1.005e4;
        // Minimum time(in seconds) to pass between updated without triggering a pause.
        accountantParameters.minimumUpateDelayInSeconds = 1 days / 4;

        // Define Decoder and Sanitizer deployment details.
        bytes memory creationCode = type(ITBPositionDecoderAndSanitizer).creationCode;
        // bytes memory constructorArgs = abi.encode(previousVault);
        bytes memory constructorArgs =
            abi.encode(deployer.getAddress(names.boringVault));

        // // Setup extra deposit assets.
        // depositAssets.push(
        //     DepositAsset({
        //         asset: USDT,
        //         isPeggedToBase: false,
        //         rateProvider: address(0x2A25aF4dFE77b9CB3C426CDa86baa76c16547CE5),
        //         genericRateProviderName: "USDT",
        //         target: address(0),
        //         selector: bytes4(0),
        //         params: [bytes32(0), bytes32(0), bytes32(0), bytes32(0), bytes32(0), bytes32(0), bytes32(0), bytes32(0)]
        //     })
        // );

        // Setup withdraw assets.
        withdrawAssets.push(
            WithdrawAsset({
                asset: PUSD,
                withdrawDelay: 3 minutes,
                completionWindow: 7 days,
                withdrawFee: 0,
                maxLoss: 0.01e4
            })
        );

        // withdrawAssets.push(
        //     WithdrawAsset({
        //         asset: USDT,
        //         withdrawDelay: 3 minutes,
        //         completionWindow: 7 days,
        //         withdrawFee: 0,
        //         maxLoss: 0.01e4
        //     })
        // );

        bool allowPublicDeposits = true;
        bool allowPublicWithdraws = true;
        uint64 shareLockPeriod = 0;
        address delayedWithdrawFeeAddress = liquidPayoutAddress;

        vm.startBroadcast(privateKey);

        _deploy(DeployParams({
            previousBoringVault: previoussuperUSD,
            deploymentFileName: "SuperUSDPlumeTestnetDeployment.json",
            owner: owner,
            boringVaultName: boringVaultName,
            boringVaultSymbol: boringVaultSymbol,
            boringVaultDecimals: boringVaultDecimals,
            decoderAndSanitizerCreationCode: creationCode,
            decoderAndSanitizerConstructorArgs: constructorArgs,
            delayedWithdrawFeeAddress: delayedWithdrawFeeAddress,
            allowPublicDeposits: allowPublicDeposits,
            allowPublicWithdraws: allowPublicWithdraws,
            shareLockPeriod: shareLockPeriod,
            developmentAddress: dev1Address
        }));

        vm.stopBroadcast();
    }
}