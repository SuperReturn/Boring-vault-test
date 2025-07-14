// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {DeployArcticArchitecture, ERC20, Deployer} from "script/ArchitectureDeployments/DeployArcticArchitecture.sol";
import {AddressToBytes32Lib} from "src/helper/AddressToBytes32Lib.sol";

// Import Decoder and Sanitizer to deploy.
import {ITBPositionDecoderAndSanitizer} from
    "src/base/DecodersAndSanitizers/Protocols/ITB/ITBPositionDecoderAndSanitizer.sol";

/**
 *  source .env && forge script script/ArchitectureDeployments/DeployTestVault.s.sol:DeployTestVaultScript --with-gas-price 30000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployTestVaultScript is DeployArcticArchitecture {
    using AddressToBytes32Lib for address;

    uint256 public privateKey;

    // Deployment parameters
    string public boringVaultName = "sSuperUSD boring vault";
    string public boringVaultSymbol = "sSuperUSD";
    uint8 public boringVaultDecimals = 6;
    address public owner = dev0Address;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("mainnet");
    }

    function run() external {
        // Define names to determine where contracts are deployed.
        names.rolesAuthority = sUsdaiVaultRolesAuthorityName;
        names.lens = sUsdaiArcticArchitectureLensName;
        names.boringVault = sUsdaiVaultName;
        names.manager = sUsdaiVaultManagerName;
        names.accountant = sUsdaiVaultAccountantName;
        names.teller = sUsdaiVaultTellerName;
        names.rawDataDecoderAndSanitizer = sUsdaiVaultDecoderAndSanitizerName;
        names.delayedWithdrawer = sUsdaiVaultDelayedWithdrawer;

        configureDeployment.deployContracts = true;
        configureDeployment.setupRoles = true;
        configureDeployment.setupDepositAssets = true;
        configureDeployment.setupWithdrawAssets = true;
        configureDeployment.finishSetup = true;
        configureDeployment.setupTestUser = true;
        configureDeployment.saveDeploymentDetails = true;
        configureDeployment.deployerAddress = deployerAddress;
        // configureDeployment.balancerVault = balancerVault;
        configureDeployment.WETH = address(WETH);

        // Save deployer.
        deployer = Deployer(configureDeployment.deployerAddress);

        // Define Accountant Parameters.
        accountantParameters.payoutAddress = liquidPayoutAddress;
        accountantParameters.base = USDAI;
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
        bytes memory constructorArgs = abi.encode(previoussSuperUSDVault);

        // Setup extra deposit assets.

        // Setup withdraw assets.

        bool allowPublicDeposits = true;
        bool allowPublicWithdraws = true;
        uint64 shareLockPeriod = 1;
        address delayedWithdrawFeeAddress = liquidPayoutAddress;

        vm.startBroadcast(privateKey);

        _deploy(
            "sSuperUSDMainnetDeployment.json",
            owner,
            boringVaultName,
            boringVaultSymbol,
            boringVaultDecimals,
            creationCode,
            constructorArgs,
            delayedWithdrawFeeAddress,
            allowPublicDeposits,
            allowPublicWithdraws,
            shareLockPeriod,
            dev1Address
        );

        vm.stopBroadcast();
    }
}