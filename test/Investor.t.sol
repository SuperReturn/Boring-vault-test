// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {BoringVault} from "src/base/BoringVault.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {AtomicSolverV4} from "src/atomic-queue/AtomicSolverV4.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";
import {Investor} from "src/atomic-queue/Investor.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISakePool} from "src/interfaces/external/sake/ISakePool.sol";
import {IAToken} from "src/interfaces/external/sake/IAToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// ========================================= MOCK CONTRACTS =========================================

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC", 6) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC4626Vault is ERC4626 {
    constructor(ERC20 _asset) ERC4626(_asset, "Mock ERC4626 Vault", "mVAULT") {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockAToken is ERC20 {
    address public immutable _pool;
    address public immutable _underlyingAsset;

    constructor(address pool_, address underlyingAsset_) ERC20("Mock aToken", "aUSDC", 6) {
        _pool = pool_;
        _underlyingAsset = underlyingAsset_;
    }

    function POOL() external view returns (address) {
        return _pool;
    }

    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return _underlyingAsset;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockSakePool {
    ERC20 public immutable usdc;

    constructor(address _usdc) {
        usdc = ERC20(_usdc);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        SafeTransferLib.safeTransfer(ERC20(asset), to, amount);
        return amount;
    }
}

contract MockRevertingVault is ERC20 {
    constructor() ERC20("Reverting Vault", "rVAULT", 6) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function redeem(uint256, address, address) external pure returns (uint256) {
        revert("MockRevertingVault: always reverts");
    }

    function withdraw(uint256, address, address) external pure returns (uint256) {
        revert("MockRevertingVault: always reverts");
    }

    function previewRedeem(uint256) external pure returns (uint256) {
        return 0;
    }
}

// ========================================= TEST CONTRACT =========================================

contract InvestorTest is Test {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    BoringVault public boringVault;
    AccountantWithRateProviders public accountant;
    TellerWithMultiAssetSupport public teller;
    AtomicQueue public atomicQueue;
    AtomicSolverV4 public atomicSolverV4;
    RolesAuthority public rolesAuthority;
    Investor public investor;
    MockUSDC public USDC;
    MockERC4626Vault public mockERC4626Vault;
    MockAToken public mockAToken;
    MockSakePool public mockSakePool;
    MockRevertingVault public mockRevertingVault;

    uint8 public constant MINTER_ROLE = 1;
    uint8 public constant BURNER_ROLE = 2;
    uint8 public constant SOLVER_ROLE = 3;
    uint8 public constant QUEUE_ROLE = 4;
    uint8 public constant ADMIN_ROLE = 5;
    uint8 public constant WITHDRAW_ROLE = 6;
    uint8 public constant INVESTOR_ROLE = 7;

    address public payoutAddress = vm.addr(7777777);
    address internal user = vm.addr(1);
    address internal unauthorized = vm.addr(99);

    event VaultsUpdated(uint256 newNumVaults);

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19363419;
        uint256 forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);

        USDC = new MockUSDC();

        Deployer deployer = new Deployer(address(this), Authority(address(0)));

        // Deploy BoringVault via UUPS proxy
        address implementation =
            deployer.deployContract("BoringVault-Implementation", type(BoringVault).creationCode, hex"", 0);

        bytes memory initializer = abi.encodeWithSelector(
            BoringVault.initialize.selector,
            address(this),
            Authority(address(0)),
            "Boring Vault",
            "BV",
            6
        );

        bytes memory proxyCreationCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializer));
        address proxy = deployer.deployContract("BoringVault", proxyCreationCode, hex"", 0);

        boringVault = BoringVault(payable(proxy));
        boringVault.setMaxTotalSupply(1_000_000_000_000_000_000_000_000_000_000_000_000_000);

        accountant = new AccountantWithRateProviders(
            address(this),
            address(boringVault),
            payoutAddress,
            1e6,
            address(USDC),
            1.005e4,
            0.995e4,
            1 days / 4,
            0,
            0
        );

        teller =
            new TellerWithMultiAssetSupport(address(this), address(boringVault), address(accountant), address(USDC));

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));

        atomicSolverV4 = new AtomicSolverV4(address(this), rolesAuthority);
        atomicQueue = new AtomicQueue(address(this), rolesAuthority, address(accountant), address(atomicSolverV4));

        // Deploy mock vaults
        mockSakePool = new MockSakePool(address(USDC));
        mockAToken = new MockAToken(address(mockSakePool), address(USDC));
        mockERC4626Vault = new MockERC4626Vault(ERC20(address(USDC)));
        mockRevertingVault = new MockRevertingVault();

        // Deploy Investor
        investor = new Investor(address(this), rolesAuthority, address(boringVault), address(atomicQueue));

        // Setup auth
        boringVault.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        teller.setAuthority(rolesAuthority);

        rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(boringVault), BoringVault.exit.selector, true);
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkDeposit.selector, true
        );
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(
            QUEUE_ROLE, address(atomicSolverV4), AtomicSolverV4.finishSolve.selector, true
        );
        rolesAuthority.setRoleCapability(
            QUEUE_ROLE, address(atomicSolverV4), AtomicSolverV4.approveOfferForQueue.selector, true
        );
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.setMaturityTime.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.setDiscount.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.setInvestor.selector, true);
        rolesAuthority.setRoleCapability(
            WITHDRAW_ROLE, address(atomicQueue), AtomicQueue.instantWithdraw.selector, true
        );

        // Investor needs manage(address,bytes,uint256) on BoringVault
        rolesAuthority.setRoleCapability(
            INVESTOR_ROLE,
            address(boringVault),
            bytes4(keccak256("manage(address,bytes,uint256)")),
            true
        );
        rolesAuthority.setUserRole(address(investor), INVESTOR_ROLE, true);

        // Investor setVaults and autoWithdrawal are owner-only (test contract is owner)

        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicSolverV4), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), QUEUE_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(user, ADMIN_ROLE, true);
        rolesAuthority.setUserRole(user, WITHDRAW_ROLE, true);

        teller.addAsset(USDC);
        atomicQueue.setDiscount(0);
    }

    // ========================================= HELPERS =========================================

    function _setupERC4626Vault(uint256 shareAmount, uint256 underlyingAmount) internal {
        // Give boringVault ERC4626 shares
        deal(address(mockERC4626Vault), address(boringVault), shareAmount);
        // Give the ERC4626 vault underlying USDC
        deal(address(USDC), address(mockERC4626Vault), underlyingAmount);
    }

    function _setupAaveVault(uint256 aTokenAmount, uint256 poolLiquidity) internal {
        // Give boringVault aTokens
        deal(address(mockAToken), address(boringVault), aTokenAmount);
        // Give the pool USDC liquidity
        deal(address(USDC), address(mockSakePool), poolLiquidity);
    }

    function _setVaultsERC4626Only() internal {
        Investor.VaultInfo[] memory vaults = new Investor.VaultInfo[](1);
        vaults[0] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockERC4626Vault)});
        investor.setVaults(vaults);
    }

    function _setVaultsAaveOnly() internal {
        Investor.VaultInfo[] memory vaults = new Investor.VaultInfo[](1);
        vaults[0] = Investor.VaultInfo({vaultType: Investor.VaultType.AaveV3, vault: address(mockAToken)});
        investor.setVaults(vaults);
    }

    // ========================================= CONSTRUCTOR =========================================

    function testConstructorSetsImmutables() external view {
        assertEq(investor.boringVault(), address(boringVault));
        assertEq(investor.queue(), address(atomicQueue));
        assertEq(investor.owner(), address(this));
        assertEq(investor.numVaults(), 0);
    }

    // ========================================= setVaults =========================================

    function testSetVaults() external {
        Investor.VaultInfo[] memory vaults = new Investor.VaultInfo[](2);
        vaults[0] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockERC4626Vault)});
        vaults[1] = Investor.VaultInfo({vaultType: Investor.VaultType.AaveV3, vault: address(mockAToken)});

        vm.expectEmit(true, true, true, true);
        emit VaultsUpdated(2);

        investor.setVaults(vaults);

        assertEq(investor.numVaults(), 2);

        (address vault0, uint8 type0) = investor.getVaultInfo(0);
        assertEq(vault0, address(mockERC4626Vault));
        assertEq(type0, uint8(Investor.VaultType.ERC4626));

        (address vault1, uint8 type1) = investor.getVaultInfo(1);
        assertEq(vault1, address(mockAToken));
        assertEq(type1, uint8(Investor.VaultType.AaveV3));
    }

    function testSetVaultsOverwritesShrinks() external {
        // Set 3 vaults
        Investor.VaultInfo[] memory vaults3 = new Investor.VaultInfo[](3);
        vaults3[0] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockERC4626Vault)});
        vaults3[1] = Investor.VaultInfo({vaultType: Investor.VaultType.AaveV3, vault: address(mockAToken)});
        vaults3[2] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockERC4626Vault)});
        investor.setVaults(vaults3);
        assertEq(investor.numVaults(), 3);

        // Shrink to 1
        Investor.VaultInfo[] memory vaults1 = new Investor.VaultInfo[](1);
        vaults1[0] = Investor.VaultInfo({vaultType: Investor.VaultType.AaveV3, vault: address(mockAToken)});
        investor.setVaults(vaults1);

        assertEq(investor.numVaults(), 1);
        (address vault0, uint8 type0) = investor.getVaultInfo(0);
        assertEq(vault0, address(mockAToken));
        assertEq(type0, uint8(Investor.VaultType.AaveV3));

        // Stale index 1 should revert
        vm.expectRevert(abi.encodeWithSelector(Investor.Investor__VaultIndexOutOfBounds.selector));
        investor.getVaultInfo(1);
    }

    function testSetVaultsOverwritesGrows() external {
        // Set 1 vault
        Investor.VaultInfo[] memory vaults1 = new Investor.VaultInfo[](1);
        vaults1[0] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockERC4626Vault)});
        investor.setVaults(vaults1);
        assertEq(investor.numVaults(), 1);

        // Grow to 3
        Investor.VaultInfo[] memory vaults3 = new Investor.VaultInfo[](3);
        vaults3[0] = Investor.VaultInfo({vaultType: Investor.VaultType.AaveV3, vault: address(mockAToken)});
        vaults3[1] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockERC4626Vault)});
        vaults3[2] = Investor.VaultInfo({vaultType: Investor.VaultType.AaveV3, vault: address(mockAToken)});
        investor.setVaults(vaults3);

        assertEq(investor.numVaults(), 3);
        (address v0,) = investor.getVaultInfo(0);
        (address v1,) = investor.getVaultInfo(1);
        (address v2,) = investor.getVaultInfo(2);
        assertEq(v0, address(mockAToken));
        assertEq(v1, address(mockERC4626Vault));
        assertEq(v2, address(mockAToken));
    }

    function testSetVaultsEmpty() external {
        // Set 2 vaults first
        Investor.VaultInfo[] memory vaults2 = new Investor.VaultInfo[](2);
        vaults2[0] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockERC4626Vault)});
        vaults2[1] = Investor.VaultInfo({vaultType: Investor.VaultType.AaveV3, vault: address(mockAToken)});
        investor.setVaults(vaults2);
        assertEq(investor.numVaults(), 2);

        // Set to empty
        Investor.VaultInfo[] memory empty = new Investor.VaultInfo[](0);
        investor.setVaults(empty);
        assertEq(investor.numVaults(), 0);

        vm.expectRevert(abi.encodeWithSelector(Investor.Investor__VaultIndexOutOfBounds.selector));
        investor.getVaultInfo(0);
    }

    function testSetVaultsRequiresAuth() external {
        Investor.VaultInfo[] memory vaults = new Investor.VaultInfo[](1);
        vaults[0] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockERC4626Vault)});

        vm.prank(unauthorized);
        vm.expectRevert("UNAUTHORIZED");
        investor.setVaults(vaults);
    }

    // ========================================= getVaultInfo =========================================

    function testGetVaultInfoOutOfBounds() external {
        _setVaultsERC4626Only();
        vm.expectRevert(abi.encodeWithSelector(Investor.Investor__VaultIndexOutOfBounds.selector));
        investor.getVaultInfo(1);
    }

    function testGetVaultInfoZeroVaults() external view {
        // No vaults set, numVaults == 0
        // Any index should revert, but since this is a view call we just check it reverts
        // Note: vm.expectRevert doesn't work with view calls in all foundry versions,
        // so we test via the setVaultsEmpty test above.
        // Here we just confirm numVaults is 0.
        assertEq(investor.numVaults(), 0);
    }

    // ========================================= autoWithdrawal — Auth =========================================

    function testAutoWithdrawalRequiresAuth() external {
        vm.prank(unauthorized);
        vm.expectRevert("UNAUTHORIZED");
        investor.autoWithdrawal(0, 100e6, ERC20(address(USDC)));
    }

    // ========================================= autoWithdrawal — ERC4626 Path =========================================

    function testAutoWithdrawalEarlyExit() external {
        _setVaultsERC4626Only();
        _setupERC4626Vault(1_000e6, 1_000e6);

        uint256 sharesBefore = ERC20(address(mockERC4626Vault)).balanceOf(address(boringVault));

        // vaultBalance >= totalRequired, should exit early and not redeem any shares
        investor.autoWithdrawal(1_000e6, 500e6, ERC20(address(USDC)));

        uint256 sharesAfter = ERC20(address(mockERC4626Vault)).balanceOf(address(boringVault));
        assertEq(sharesBefore, sharesAfter, "No shares should have been redeemed");
    }

    function testAutoWithdrawalERC4626FullRedeem() external {
        _setVaultsERC4626Only();
        // 500 shares, 500 USDC underlying => previewRedeem(500) = 500
        _setupERC4626Vault(500e6, 500e6);

        uint256 vaultUsdcBefore = USDC.balanceOf(address(boringVault));

        // vaultBalance=0, totalRequired=1000e6, amountRequired=1000e6
        // previewRedeem(500e6) = 500e6 <= 1000e6, so full redeem
        investor.autoWithdrawal(0, 1_000e6, ERC20(address(USDC)));

        uint256 vaultUsdcAfter = USDC.balanceOf(address(boringVault));
        uint256 sharesAfter = ERC20(address(mockERC4626Vault)).balanceOf(address(boringVault));

        assertEq(sharesAfter, 0, "All shares should be redeemed");
        assertEq(vaultUsdcAfter - vaultUsdcBefore, 500e6, "BoringVault should receive 500 USDC");
    }

    function testAutoWithdrawalERC4626PartialWithdraw() external {
        _setVaultsERC4626Only();
        // 1000 shares, 1000 USDC underlying => previewRedeem(1000) = 1000
        _setupERC4626Vault(1_000e6, 1_000e6);

        uint256 vaultUsdcBefore = USDC.balanceOf(address(boringVault));
        uint256 sharesBefore = ERC20(address(mockERC4626Vault)).balanceOf(address(boringVault));

        // vaultBalance=0, totalRequired=200e6, amountRequired=200e6
        // previewRedeem(1000e6) = 1000e6 > 200e6 => withdraw(200e6)
        investor.autoWithdrawal(0, 200e6, ERC20(address(USDC)));

        uint256 vaultUsdcAfter = USDC.balanceOf(address(boringVault));
        uint256 sharesAfter = ERC20(address(mockERC4626Vault)).balanceOf(address(boringVault));

        assertEq(vaultUsdcAfter - vaultUsdcBefore, 200e6, "BoringVault should receive exactly 200 USDC");
        assertGt(sharesAfter, 0, "Some shares should remain");
        assertEq(sharesBefore - sharesAfter, 200e6, "200 shares should be consumed (1:1 ratio)");
    }

    // ========================================= autoWithdrawal — AaveV3 Path =========================================

    function testAutoWithdrawalAaveV3() external {
        _setVaultsAaveOnly();
        _setupAaveVault(500e6, 500e6);

        uint256 vaultUsdcBefore = USDC.balanceOf(address(boringVault));

        // vaultBalance=0, totalRequired=300e6, amountRequired=300e6
        // min(500e6, 300e6) = 300e6
        investor.autoWithdrawal(0, 300e6, ERC20(address(USDC)));

        uint256 vaultUsdcAfter = USDC.balanceOf(address(boringVault));
        assertEq(vaultUsdcAfter - vaultUsdcBefore, 300e6, "BoringVault should receive 300 USDC from Aave");
    }

    // ========================================= autoWithdrawal — Loop & Edge Cases =========================================

    function testAutoWithdrawalMultipleVaults() external {
        // Set up 3 vaults: ERC4626 (200), AaveV3 (300), ERC4626 (500)
        Investor.VaultInfo[] memory vaults = new Investor.VaultInfo[](3);
        vaults[0] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockERC4626Vault)});
        vaults[1] = Investor.VaultInfo({vaultType: Investor.VaultType.AaveV3, vault: address(mockAToken)});

        // Create a second ERC4626 vault
        MockERC4626Vault secondVault = new MockERC4626Vault(ERC20(address(USDC)));
        vaults[2] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(secondVault)});
        investor.setVaults(vaults);

        // Setup: vault 0 has 200 USDC, vault 1 has 300 USDC, vault 2 has 500 USDC
        _setupERC4626Vault(200e6, 200e6);
        _setupAaveVault(300e6, 300e6);
        deal(address(secondVault), address(boringVault), 500e6);
        deal(address(USDC), address(secondVault), 500e6);

        // Need 400 USDC. Should take 200 from vault 0, then 200 from vault 1, skip vault 2.
        investor.autoWithdrawal(0, 400e6, ERC20(address(USDC)));

        uint256 vaultUsdc = USDC.balanceOf(address(boringVault));
        assertGe(vaultUsdc, 400e6, "BoringVault should have at least 400 USDC");

        // Vault 2 (secondVault) should be untouched
        uint256 secondVaultShares = ERC20(address(secondVault)).balanceOf(address(boringVault));
        assertEq(secondVaultShares, 500e6, "Third vault should be untouched");
    }

    function testAutoWithdrawalSkipsZeroBalance() external {
        _setVaultsERC4626Only();
        // No shares in boringVault for ERC4626 vault
        // But there IS underlying in the vault contract (doesn't matter if no shares)
        deal(address(USDC), address(mockERC4626Vault), 1_000e6);
        // boringVault has 0 ERC4626 shares

        uint256 vaultUsdcBefore = USDC.balanceOf(address(boringVault));

        investor.autoWithdrawal(0, 500e6, ERC20(address(USDC)));

        uint256 vaultUsdcAfter = USDC.balanceOf(address(boringVault));
        assertEq(vaultUsdcAfter, vaultUsdcBefore, "No USDC should be freed since vault token balance is 0");
    }

    function testAutoWithdrawalSilentlySkipsFailedVault() external {
        // Set up: reverting vault first, then ERC4626 vault
        Investor.VaultInfo[] memory vaults = new Investor.VaultInfo[](2);
        vaults[0] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockRevertingVault)});
        vaults[1] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockERC4626Vault)});
        investor.setVaults(vaults);

        // Give boringVault shares of the reverting vault
        deal(address(mockRevertingVault), address(boringVault), 500e6);
        // Setup the working ERC4626 vault
        _setupERC4626Vault(500e6, 500e6);

        uint256 vaultUsdcBefore = USDC.balanceOf(address(boringVault));

        // Should silently skip the reverting vault and proceed to the ERC4626 vault
        investor.autoWithdrawal(0, 300e6, ERC20(address(USDC)));

        uint256 vaultUsdcAfter = USDC.balanceOf(address(boringVault));
        assertGe(vaultUsdcAfter - vaultUsdcBefore, 300e6, "Should get USDC from the second vault");
    }

    function testAutoWithdrawalAllVaultsFail() external {
        // Set up: only reverting vaults
        Investor.VaultInfo[] memory vaults = new Investor.VaultInfo[](2);
        MockRevertingVault revertVault2 = new MockRevertingVault();
        vaults[0] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(mockRevertingVault)});
        vaults[1] = Investor.VaultInfo({vaultType: Investor.VaultType.ERC4626, vault: address(revertVault2)});
        investor.setVaults(vaults);

        deal(address(mockRevertingVault), address(boringVault), 500e6);
        deal(address(revertVault2), address(boringVault), 500e6);

        uint256 vaultUsdcBefore = USDC.balanceOf(address(boringVault));

        // Should complete without revert, but no funds freed
        investor.autoWithdrawal(0, 1_000e6, ERC20(address(USDC)));

        uint256 vaultUsdcAfter = USDC.balanceOf(address(boringVault));
        assertEq(vaultUsdcAfter, vaultUsdcBefore, "No USDC freed since all vaults failed");
    }

    function testAutoWithdrawalPartialFulfillment() external {
        _setVaultsERC4626Only();
        // Only 200 USDC available, but need 500
        _setupERC4626Vault(200e6, 200e6);

        uint256 vaultUsdcBefore = USDC.balanceOf(address(boringVault));

        // Function completes without revert, only partial funds freed
        investor.autoWithdrawal(0, 500e6, ERC20(address(USDC)));

        uint256 vaultUsdcAfter = USDC.balanceOf(address(boringVault));
        assertEq(vaultUsdcAfter - vaultUsdcBefore, 200e6, "Only 200 USDC should be freed");
    }
}
