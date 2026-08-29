// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ArcticArchitectureLens} from "src/helper/ArcticArchitectureLens.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {ArbitrumAddresses} from "test/resources/ArbitrumAddresses.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {SuperUSDWrapper} from "src/wrappers.sol";

/**
 * @title USDAI Deposit Integration Test
 * @notice This script demonstrates how to deposit USDC into the USDAI vault on Sepolia
 * @dev Run with: forge script script/USDAIIntegrationTest/Deposit.sol --rpc-url $MINATO_RPC_URL
 */
contract USDAIDepositScript is Script, ArbitrumAddresses, ContractNames, MerkleTreeHelper{
    // Test parameters
    uint256 public constant USDC_DEPOSIT_AMOUNT = 5 * 1e3; 
    // Contract instances
    Deployer public deployer;
    BoringVault boringVault;
    TellerWithMultiAssetSupport teller;
    ArcticArchitectureLens lens;
    AccountantWithRateProviders accountant;
    SuperUSDWrapper superUSDWrapper;

    function setUp() public {
        vm.createSelectFork("arbitrum");
        setSourceChainName("arbitrum");
        deployer = Deployer(getAddress(sourceChain, "deployerAddress"));
        
        // Initialize contract instances
        boringVault = BoringVault(payable(previoussuperUSD));
        teller = TellerWithMultiAssetSupport(deployer.getAddress(UsdaiVaultTellerName));
        lens = ArcticArchitectureLens(deployer.getAddress(UsdaiArcticArchitectureLensName));
        accountant = AccountantWithRateProviders(deployer.getAddress(UsdaiVaultAccountantName));
        superUSDWrapper = SuperUSDWrapper(deployer.getAddress(SuperUSDWrapperName));
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        
        vm.startBroadcast(privateKey);
        
        if (USDC.balanceOf(user) >= USDC_DEPOSIT_AMOUNT) {
            console.log("\n=== Depositing USDC ===");

            uint256 sharesBefore = boringVault.balanceOf(user);
            USDC.approve(address(boringVault), USDC_DEPOSIT_AMOUNT);
            teller.deposit(USDC, USDC_DEPOSIT_AMOUNT, 0);
            uint256 sharesReceived = boringVault.balanceOf(user) - sharesBefore;
            console.log("Shares received:", sharesReceived);

            uint256 sharesForA = sharesReceived / 2;
            uint256 sharesForB = sharesReceived - sharesForA;

            // 1. Withdraw via wrapper function A:
            //    Shares are pulled from caller into wrapper, redeemed via instantWithdraw,
            //    and USDC proceeds are forwarded to `recipient` (here: the caller).
            //    Pass `superUSDWrapper.aeonPay()` as recipient to forward directly to Aeon Pay.
            console.log("\n=== Withdraw via Wrapper A ===");
            ERC20(address(boringVault)).approve(address(superUSDWrapper), sharesForA);
            uint256 assetsOutA = superUSDWrapper.withdrawA(
                ERC20(address(boringVault)),
                USDC,
                sharesForA,
                0,
                teller,
                user
            );
            console.log("Assets out (A):", assetsOutA);

            // 2. Withdraw via wrapper function B:
            //    Shares are pulled from caller, redeemed, and USDC sent back to caller.
            //    The wrapper then pulls that USDC from the caller to Aeon Pay via transferFrom,
            //    so the caller must pre-approve the wrapper for USDC as well.
            console.log("\n=== Withdraw via Wrapper B ===");
            ERC20(address(boringVault)).approve(address(superUSDWrapper), sharesForB);
            USDC.approve(address(superUSDWrapper), type(uint256).max);
            uint256 assetsOutB = superUSDWrapper.withdrawB(
                ERC20(address(boringVault)),
                USDC,
                sharesForB,
                0,
                teller
            );
            console.log("Assets out (B):", assetsOutB);

        } else {
            console.log("Insufficient USDC balance for deposit");
        }

        vm.stopBroadcast();
    }
}