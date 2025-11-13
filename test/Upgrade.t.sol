// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {AccountantWithRateProviders2} from "src/base/Roles/AccountantWithRateProviders2.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {AtomicSolverV4} from "src/atomic-queue/AtomicSolverV4.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";

import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UpgradeTest is Test, MainnetAddresses {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    BoringVault public boringVault;
    AccountantWithRateProviders2 public accountant;
    RolesAuthority public rolesAuthority;
    TellerWithMultiAssetSupport public teller;
    AtomicQueue public atomicQueue;
    AtomicSolverV4 public atomicSolverV4;
    address public payoutAddress = vm.addr(7777777);
    
    uint8 public constant MINTER_ROLE = 1;
    uint8 public constant BURNER_ROLE = 2;
    uint8 public constant SOLVER_ROLE = 3;
    uint8 public constant QUEUE_ROLE = 4;
    uint8 public constant ADMIN_ROLE = 5;
    uint8 public constant WITHDRAW_ROLE = 6;
    uint8 public constant UPGRADER_ROLE = 7;

    address public constant superusd                    = address(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB);
    //address public constant oldSuperusdImpl           = address(0xd00fb475cd68cd99e711fd395bc185758e84ba40);
    address public constant oldSuperusdImpl             = address(0x2656d4453a1B0ce9C213F18CA34A77b66c90640d);
    address public constant oldSuperusdRolesAuthority   = address(0x4FA024546d245f617dAAe796470721bC5D95E856);
    address public constant oldSuperusdAccountant       = address(0xF4a5555C5716bb61DC9C9124257e92683f98415B);
    address public constant oldSuperusdLens             = address(0x4a05CbB107E9964fa61D04cBF60c049F96eBBf56);
    address public constant oldSuperusdManager          = address(0x65EA811bA829dC166B7FCF25369bBF6BC33DA14d);
    address public constant oldSuperusdTeller           = address(0xB08efd111caf0b45a038Eb07c370D068E55cc233);
    address public constant oldSuperusdSolver           = address(0x630f595A5aA09ff1b5c11FAd8Cf78a8109776ABc);
    address public constant oldSuperusdQueue            = address(0xDB6C5dC3e4802243f0c40e1883eA833Aa7a93588);
    address public constant oldSuperusdQueueAuthority   = address(0xAE35B87121B2Ae2e8013DF2B6D35CEB76E110D33);
    address public constant oldSuperusdLzTeller         = address(0x91c6Ea9Cdb919523Fd4B3027db90EeB0A9f9D66C);

    address public constant ssuperusd                   = address(0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd);
    //address public constant oldSSuperusdImpl          = address(0xC9076fE64A20D446Cb1ab11c91828C9054005327);
    address public constant oldSSuperusdImpl            = address(0xB1916C00CEDdBfD5B8aF1B4f16BFCe84A0D0909f);
    address public constant oldSSuperusdRolesAuthority  = address(0x31e311b75E753A961eB090dc29AfC1A23c57FF34);
    address public constant oldSSuperusdAccountant      = address(0xFec60259f315287252c495C5921A30209Dd1FA4e);
    address public constant oldSSuperusdLens            = address(0xc43827a38AC3C495547bF466a90f4ec36f13AB66);
    address public constant oldSSuperusdManager         = address(0x8E3c0Be2847999D63Ce8FeCd3368aaaC33572Ecd);
    address public constant oldSSuperusdTeller          = address(0xefCAEA1163cc9F328f303E3B49BCB9a54108938a);
    address public constant oldSSuperusdSolver          = address(0xD755943d933526913F8dDa807f38650038856f1f);
    address public constant oldSSuperusdQueue           = address(0x37a25d6B8118434b7513FEd84cbfde106D196107);
    address public constant oldSSuperusdQueueAuthority  = address(0x0087C7545A9dc0761cC05BC835Ee6F7776F76924);
    address public constant oldSSuperusdLzTeller        = address(0x1D43214f63EcDf8C3C0f9c22540cb158ADAb3cE8);

    address public constant oldDeployer                 = address(0x1f082348a1f3C9eDfc31374913E0817055BA5F88);

    bytes4 public constant upgradeToAndCallSelector = 0x4f1ef286;
    bytes4 public constant setNameAndSymbolSelector = 0x5a446215;
    //address public constant signerAddress               = address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496); // address(this), the one used in the test

    Deployer public deployer;
    address public implementation;
    address public authorityOwner                       = address(0x1B05602fd89674dB6385c8188d57BD1015882F42);
    address public usdc                                 = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public usdcMasterMinter                     = address(0xE982615d461DD5cD06575BbeA87624fda4e3de17);

    uint256 userUSDCInitialBalance = 1000e6;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 23779300;
        _startFork(rpcKey, blockNumber);

        boringVault = BoringVault(payable(superusd));
        rolesAuthority = RolesAuthority(oldSuperusdRolesAuthority);

        // 0: test state before upgrade
        //console.log("here 0");
        _testBalances();
        _testMetadataBefore();
        _testOtherViews();

        // 1: Deploy deployer
        //console.log("here 1");
        deployer = new Deployer(address(this), Authority(address(0)));

        // 2: Deploy implementation
        //console.log("here 2");
        implementation = deployer.deployContract(
            "BoringVault-Implementation",
            type(BoringVault).creationCode,
            hex"",
            0
        );

        // 3: test upgrade roles and capabilities not yet set
        //console.log("here 3");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).canCall(address(this), superusd, upgradeToAndCallSelector), false, "Should not be able to call upgradeToAndCall yet");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).canCall(address(this), superusd, setNameAndSymbolSelector), false, "Should not be able to call setNameAndSymbol yet");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).doesRoleHaveCapability(ADMIN_ROLE, superusd, upgradeToAndCallSelector), false, "Admin role should not start with the upgradeToAndCall capability");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).doesRoleHaveCapability(UPGRADER_ROLE, superusd, upgradeToAndCallSelector), false, "Upgrader role should not start with the upgradeToAndCall capability");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).doesRoleHaveCapability(ADMIN_ROLE, superusd, setNameAndSymbolSelector), false, "Admin role should not start with the setNameAndSymbol capability");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).doesRoleHaveCapability(UPGRADER_ROLE, superusd, setNameAndSymbolSelector), false, "Upgrader role should not start with the setNameAndSymbol capability");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).doesUserHaveRole(address(this), ADMIN_ROLE), false, "Script should not start with the admin role");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).doesUserHaveRole(address(this), UPGRADER_ROLE), false, "Script should not start with the upgrader role");

        // 4: test upgrade fails without auth
        //console.log("here 4");
        bytes memory data = abi.encodeWithSelector(setNameAndSymbolSelector, "SuperUSD", "SuperUSD");
        vm.expectRevert("UNAUTHORIZED");
        BoringVault(payable(superusd)).upgradeToAndCall(implementation, data);

        // 5: Set role capability
        //console.log("here 5");
        vm.startPrank(authorityOwner);
        RolesAuthority(oldSuperusdRolesAuthority).setRoleCapability(UPGRADER_ROLE, superusd, upgradeToAndCallSelector, true);
        RolesAuthority(oldSuperusdRolesAuthority).setRoleCapability(UPGRADER_ROLE, superusd, setNameAndSymbolSelector, true);
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).doesRoleHaveCapability(UPGRADER_ROLE, superusd, upgradeToAndCallSelector), true, "Upgrader role should now have the upgradeToAndCall capability");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).doesRoleHaveCapability(UPGRADER_ROLE, superusd, setNameAndSymbolSelector), true, "Upgrader role should now have the setNameAndSymbol capability");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).canCall(address(this), superusd, upgradeToAndCallSelector), false, "Should not be able to call upgradeToAndCall yet");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).canCall(address(this), superusd, setNameAndSymbolSelector), false, "Should not be able to call setNameAndSymbol yet");
        
        // 6: Set user role
        //console.log("here 6");
        RolesAuthority(oldSuperusdRolesAuthority).setUserRole(address(this), UPGRADER_ROLE, true);
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).doesUserHaveRole(address(this), UPGRADER_ROLE), true, "Script should now have the upgrader role");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).canCall(address(this), superusd, upgradeToAndCallSelector), true, "Should be able to call upgradeToAndCall");
        assertEq(RolesAuthority(oldSuperusdRolesAuthority).canCall(address(this), superusd, setNameAndSymbolSelector), true, "Should be able to call setNameAndSymbol");
        vm.stopPrank();

        // 7: test upgrade
        //console.log("here 7");
        BoringVault(payable(superusd)).upgradeToAndCall(implementation, data);


        // 8: Deploy new accountant
        //console.log("here 8");
        accountant = new AccountantWithRateProviders2(
            address(this),
            superusd,
            payoutAddress,
            1e6, // USDC decimals
            usdc,
            1.005e4,
            0.995e4,
            1 days / 4,
            0,
            0
        );

        // 9: Deploy new teller
        //console.log("here 9");
        teller = new TellerWithMultiAssetSupport(address(this), superusd, address(accountant), usdc);

        // 10: Deploy new atomic solver
        //console.log("here 10");
        atomicSolverV4 = new AtomicSolverV4(address(this), rolesAuthority);

        // 11: Deploy new atomic queue
        //console.log("here 11");
        atomicQueue = new AtomicQueue(address(this), rolesAuthority, address(accountant), address(atomicSolverV4));

        // 12: Set authority on new contracts
        //console.log("here 12");
        //boringVault.setAuthority(rolesAuthority); // already set
        accountant.setAuthority(rolesAuthority);
        teller.setAuthority(rolesAuthority);

        //console.log("here 13");

        // 13: Set roles and role capabilities
        vm.startPrank(authorityOwner);
        // already added
        //rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(boringVault), BoringVault.exit.selector, true);
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkDeposit.selector, true
        );
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(QUEUE_ROLE, address(atomicSolverV4), AtomicSolverV4.finishSolve.selector, true);
        rolesAuthority.setRoleCapability(QUEUE_ROLE, address(atomicSolverV4), AtomicSolverV4.approveOfferForQueue.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.setMaturityTime.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.setDiscount.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.addToWhitelist.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.removeFromWhitelist.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.updateWhitelistMaturityDivisor.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.setSolver.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.cancelAtomicRequestByAdmin.selector, true);
        rolesAuthority.setRoleCapability(WITHDRAW_ROLE, address(atomicQueue), AtomicQueue.instantWithdraw.selector, true);
        rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(accountant), AccountantWithRateProviders.updateExchangeRate.selector, true);
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.updateAtomicRequest.selector, true);
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.solve.selector, true);
        rolesAuthority.setPublicCapability(address(atomicSolverV4), AtomicSolverV4.redeemSolve.selector, true);
        
        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicSolverV4), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), QUEUE_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(address(this), WITHDRAW_ROLE, true);

        vm.stopPrank();

        atomicQueue.setDiscount(0); // ignore the discount for testing

        // 14: Mint USDC for testing
        teller.addAsset(ERC20(usdc));
        assertEq(ERC20(usdc).balanceOf(address(this)), 0, "Script should not start with any USDC");
        vm.prank(usdcMasterMinter);
        IUsdcMintable(usdc).configureMinter(address(this), userUSDCInitialBalance);
        IUsdcMintable(usdc).mint(address(this), userUSDCInitialBalance);
        assertEq(ERC20(usdc).balanceOf(address(this)), userUSDCInitialBalance, "Script should now have USDC");
    }

    function test01ContractsAreDeployed() external view {
        assertNotEq(address(deployer), address(0), "Deployer should be deployed");
        assertNotEq(address(implementation), address(0), "Implementation should be deployed");
    }

    function test02BalancesAfterUpgrade() external view {
        _testBalances();
    }

    function test03MetadataAfterUpgrade() external view {
        _testMetadataAfter();
    }

    function test04OtherViews() external view {
        _testOtherViews();
    }

    function test05CanDeposit() external {
        _testDeposit();
    }

    function test06CanWithdraw() external {
        _testDeposit();
        _testWithdraw();
    }

    // ========================================= TEST HELPERS =========================================

    function _testBalances() internal view {
        _testUserBalance(address(0xDB6C5dC3e4802243f0c40e1883eA833Aa7a93588), 264635864342, 1);
        _testUserBalance(address(0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd), 234646657746, 2);
        _testUserBalance(address(0x8Ab8aEEf444AeE718A275a8325795FE90CF162c4),     44477087, 3);
        _testUserBalance(address(0xcF372762FE08682528Cba6BfA367A768d7b0afB4),     20000000, 4);
        _testUserBalance(address(this),                                                  0, 5);
        assertEq(ERC20(superusd).totalSupply(), 499416121473, "SuperUSD total supply is incorrect");
    }
    
    function _testUserBalance(address user, uint256 expectedBalance, uint256 userIndex) internal view {
        uint256 balance = ERC20(superusd).balanceOf(user);
        if(balance != expectedBalance) {
            console.log("Balance mismatch for user", userIndex, user);
            console.log("Expected", expectedBalance, "got", balance);
        }
        assertEq(balance, expectedBalance, "User balance is incorrect");
    }

    function _testMetadataBefore() internal view {
        assertEq(ERC20(superusd).name(), "SuperUSD boring vault", "SuperUSD name is incorrect");
        assertEq(ERC20(superusd).symbol(), "SuperUSD", "SuperUSD symbol is incorrect");
        assertEq(ERC20(superusd).decimals(), 6, "SuperUSD decimals is incorrect");
    }
    
    function _testMetadataAfter() internal view {
        assertEq(ERC20(superusd).name(), "SuperUSD", "SuperUSD name is incorrect");
        assertEq(ERC20(superusd).symbol(), "SuperUSD", "SuperUSD symbol is incorrect");
        assertEq(ERC20(superusd).decimals(), 6, "SuperUSD decimals is incorrect");
    }
    
    function _testOtherViews() internal view {
        assertEq(BoringVault(payable(superusd)).maxTotalSupply(), 100000000000000, "SuperUSD max total supply is incorrect");
        assertEq(BoringVault(payable(superusd)).UPGRADE_INTERFACE_VERSION(), "5.0.0", "SuperUSD upgrade interface version is incorrect");
        assertEq(address(BoringVault(payable(superusd)).authority()), oldSuperusdRolesAuthority, "SuperUSD authority is incorrect");
        assertEq(address(BoringVault(payable(superusd)).hook()), oldSuperusdTeller, "SuperUSD hook is incorrect");
        assertEq(BoringVault(payable(superusd)).owner(), address(0), "SuperUSD owner is incorrect");
    }

    function _testDeposit() internal {
        //ERC20(usdc).approve(address(teller), type(uint256).max);
        ERC20(usdc).approve(superusd, type(uint256).max);
        uint256 shares0 = teller.deposit(ERC20(usdc), 100e6, 0);
        assertNotEq(shares0, 0, "Deposit should earn shares");
        //console.log("shares  :", shares0);
        assertNotEq(ERC20(superusd).balanceOf(address(this)), 0, "Script should have some shares");
        assertEq(ERC20(superusd).balanceOf(address(this)), shares0, "Script should have exact shares");
        assertEq(ERC20(usdc).balanceOf(address(this)), 900e6, "Script should correct usdc remaining");
    }

    function _testWithdraw() internal {
        uint256 discount = 0;
        // instant withdraw
        uint256 vaultUsdcBalanceBefore = ERC20(usdc).balanceOf(superusd);
        assertEq(vaultUsdcBalanceBefore, 3618196662);
        ERC20(superusd).approve(address(atomicQueue), type(uint256).max);
        uint256 assets = atomicQueue.instantWithdraw(ERC20(superusd), ERC20(usdc), 20e6, 0, teller);
        assertEq(assets, 20000000);
        // Check the usdc and vault share amount
        assertEq(assets, uint256(20e6).mulDivDown(1e6 - discount, 1e6));
        assertEq(ERC20(usdc).balanceOf(address(this)), 900e6 + 20e6);
        assertEq(ERC20(usdc).balanceOf(address(boringVault)), vaultUsdcBalanceBefore - 20e6);
        assertEq(boringVault.balanceOf(address(this)), 100e6 - 20e6);
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}

interface IUsdcMintable {
    function mint(address _to, uint256 _amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
}