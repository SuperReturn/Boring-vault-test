// // SPDX-License-Identifier: Apache-2.0
// pragma solidity 0.8.21;

// import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
// import {BoringVaultWithERC4626} from "src/base/BoringVaultWithERC4626.sol";
// import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
// import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
// import {ERC20} from "@solmate/tokens/ERC20.sol";
// import {IRateProvider} from "src/interfaces/IRateProvider.sol";
// import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
// import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
// import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
// import {AtomicSolverV4, AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicSolverV4.sol";

// import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";
// import {Deployer} from "src/helper/Deployer.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// /// @title MockUSDC
// /// @notice Mock USDC token for testing
// contract MockUSDC is ERC20 {
//     constructor() ERC20("USD Coin", "USDC", 6) {}

//     function mint(address to, uint256 amount) external {
//         _mint(to, amount);
//     }
// }

// contract BoringVaultWithERC4626Test is Test, MainnetAddresses {
//     using SafeTransferLib for ERC20;
//     using FixedPointMathLib for uint256;
//     using stdStorage for StdStorage;

//     TellerWithMultiAssetSupport public teller;
//     AccountantWithRateProviders public accountant;
//     AtomicQueue public atomicQueue;
//     AtomicSolverV4 public atomicSolverV4;
//     address public payoutAddress = vm.addr(7777777);
//     address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
//     ERC20 internal constant NATIVE_ERC20 = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
//     RolesAuthority public rolesAuthority;
//     MockUSDC public mockUSDC;

//     BoringVaultWithERC4626 public boringVault;

//     uint8 public constant MINTER_ROLE = 1;
//     uint8 public constant BURNER_ROLE = 2;
//     uint8 public constant SOLVER_ROLE = 3;
//     uint8 public constant QUEUE_ROLE = 4;
//     uint8 public constant ADMIN_ROLE = 5;

//     uint256 constant USER_USDC_INITIAL_BALANCE = 1_000_000_000e6;

//     address internal user = vm.addr(1);

//     uint256 constant DEFAULT_MATURITY_TIME = 1 hours;

//     function setUp() external {
//         // Setup forked environment.
//         string memory rpcKey = "MAINNET_RPC_URL";
//         uint256 blockNumber = 19363419;
//         _startFork(rpcKey, blockNumber);

//         mockUSDC = new MockUSDC();

//         Deployer deployer = new Deployer(address(this), Authority(address(0)));

//         // Deploy implementation
//         address implementation =
//             deployer.deployContract("BoringVaultWithERC4626-Implementation", type(BoringVaultWithERC4626).creationCode, hex"", 0);

//         // Prepare initializer data
//         bytes memory initializer = abi.encodeWithSelector(
//             BoringVaultWithERC4626.initialize.selector,
//             address(this), // owner
//             Authority(address(0)), // authority
//             "Boring Vault", // name
//             "BV", // symbol
//             6, // decimals
//             address(mockUSDC)
//         );

//         // Deploy proxy
//         bytes memory proxyCreationCode =
//             abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializer));
//         address proxy = deployer.deployContract("BoringVault", proxyCreationCode, hex"", 0);

//         boringVault = BoringVaultWithERC4626(payable(proxy));
//         boringVault.setMaxTotalSupply(1000000000000000000000000000000000000000);

//         accountant = new AccountantWithRateProviders(
//             address(this),
//             address(boringVault),
//             payoutAddress,
//             1e6, // USDC decimals
//             address(mockUSDC),
//             1.005e4,
//             0.995e4,
//             1 days / 4,
//             0,
//             0
//         );

//         boringVault.setAccountant(address(accountant));

//         teller =
//             new TellerWithMultiAssetSupport(address(this), address(boringVault), address(accountant), address(mockUSDC));

//         rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));

//         atomicQueue = new AtomicQueue(address(this), rolesAuthority);
//         atomicSolverV4 = new AtomicSolverV4(address(this), rolesAuthority);

//         boringVault.setAuthority(rolesAuthority);
//         accountant.setAuthority(rolesAuthority);
//         teller.setAuthority(rolesAuthority);

//         rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVaultWithERC4626.enter.selector, true);
//         rolesAuthority.setRoleCapability(BURNER_ROLE, address(boringVault), BoringVaultWithERC4626.exit.selector, true);
//         rolesAuthority.setRoleCapability(
//             SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkDeposit.selector, true
//         );
//         rolesAuthority.setRoleCapability(
//             SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
//         );
//         rolesAuthority.setRoleCapability(QUEUE_ROLE, address(atomicSolverV4), AtomicSolverV4.finishSolve.selector, true);
//         rolesAuthority.setRoleCapability(ADMIN_ROLE, address(atomicQueue), AtomicQueue.addToWhitelist.selector, true);
//         rolesAuthority.setRoleCapability(
//             ADMIN_ROLE, address(atomicQueue), AtomicQueue.removeFromWhitelist.selector, true
//         );
//         rolesAuthority.setRoleCapability(
//             ADMIN_ROLE, address(atomicQueue), AtomicQueue.updateWhitelistMaturityDivisor.selector, true
//         );
    
//         rolesAuthority.setPublicCapability(address(accountant), AccountantWithRateProviders.updateExchangeRate.selector, true);
//         rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);
//         rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.updateAtomicRequest.selector, true);
//         rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.solve.selector, true);
//         rolesAuthority.setPublicCapability(address(atomicSolverV4), AtomicSolverV4.redeemSelfSolve.selector, true);
//         rolesAuthority.setPublicCapability(address(boringVault), BoringVaultWithERC4626.deposit.selector, true);
//         rolesAuthority.setPublicCapability(address(boringVault), BoringVaultWithERC4626.withdraw.selector, true);
//         rolesAuthority.setPublicCapability(address(boringVault), BoringVaultWithERC4626.mint.selector, true);
//         rolesAuthority.setPublicCapability(address(boringVault), BoringVaultWithERC4626.redeem.selector, true);

//         rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
//         rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
//         rolesAuthority.setUserRole(address(atomicSolverV4), SOLVER_ROLE, true);
//         rolesAuthority.setUserRole(address(atomicQueue), QUEUE_ROLE, true);
//         rolesAuthority.setUserRole(user, ADMIN_ROLE, true);

//         teller.addAsset(mockUSDC);

//         mockUSDC.mint(address(user), USER_USDC_INITIAL_BALANCE);

//         vm.startPrank(user);
//         mockUSDC.approve(address(boringVault), type(uint256).max);
//         boringVault.approve(address(atomicQueue), type(uint256).max);

//         vm.stopPrank();
//     }

//     function testViewFunctions() external {
//         assertEq(boringVault.asset(), address(mockUSDC));
//         assertEq(boringVault.totalAssets(), 0);
//         assertEq(boringVault.convertToShares(1_000_000e6), 1_000_000e6);
//         assertEq(boringVault.convertToAssets(1_000_000e6), 1_000_000e6);
//         assertEq(boringVault.previewDeposit(1_000_000e6), 1_000_000e6);
//         assertEq(boringVault.previewMint(1_000_000e6), 1_000_000e6);
//     }
    
//     function testDeposit() external {
//         // test erc4626 deposit after the underlying asset increase
//         vm.startPrank(user);

//         uint256 userDepositAmount = 1_000_000e6;

//         // 1. normal deposit
//         boringVault.deposit(userDepositAmount, user);
//         // check the USDC balance
//         assertEq(mockUSDC.balanceOf(address(boringVault)), 1_000_000e6);
//         assertEq(mockUSDC.balanceOf(address(user)), USER_USDC_INITIAL_BALANCE - userDepositAmount);
//         // check shares of the user
//         // should get the 1:1 ratio
//         assertEq(boringVault.balanceOf(address(user)), userDepositAmount);

//         // 2. change fund amount of the vault
//         mockUSDC.mint(address(boringVault), 5_000_000e6);

//         // 3. deposit again
//         // should still get the 1:1 ratio(haven't changed the rate)
//         boringVault.deposit(userDepositAmount, user);
//         assertEq(mockUSDC.balanceOf(address(boringVault)), userDepositAmount + 5_000_000e6 + userDepositAmount);
//         assertEq(mockUSDC.balanceOf(address(user)), USER_USDC_INITIAL_BALANCE - userDepositAmount - userDepositAmount);
//         assertEq(boringVault.balanceOf(address(user)), userDepositAmount + userDepositAmount);

//         // 4. update the accountant exchange rate
//         skip(1 days);
//         accountant.updateExchangeRate(1.001e6);
//         console.log("the rate is: ", accountant.getRateSafe());

//         // 5. deposit again
//         boringVault.deposit(userDepositAmount, user);
//         assertEq(mockUSDC.balanceOf(address(boringVault)), userDepositAmount + 5_000_000e6 + userDepositAmount + userDepositAmount);
//         assertEq(mockUSDC.balanceOf(address(user)), USER_USDC_INITIAL_BALANCE - userDepositAmount - userDepositAmount - userDepositAmount);
//         // should get the new ratio since the accountant exchange rate has changed
//         assertLt(boringVault.balanceOf(address(user)), userDepositAmount + userDepositAmount + userDepositAmount);

//         vm.stopPrank();
//     }

//     function testWithdraw() external {
//         // test withdraw after the underlying asset increase
//         vm.startPrank(user);

//         uint256 userDepositAmount = 4_000_000e6;
//         uint256 userWithdrawAmount = 1_000_000e6;
//         boringVault.deposit(userDepositAmount, user);

//         // 1. normal withdraw
//         boringVault.withdraw(userWithdrawAmount, user, user);
//         assertEq(mockUSDC.balanceOf(address(user)), USER_USDC_INITIAL_BALANCE - userDepositAmount + userWithdrawAmount);
//         assertEq(mockUSDC.balanceOf(address(boringVault)), userDepositAmount - userWithdrawAmount);
//         assertEq(boringVault.balanceOf(address(user)), userDepositAmount - userWithdrawAmount);

//         // 2. change fund amount of the vault
//         mockUSDC.mint(address(boringVault), 5_000_000e6);

//         // 3. withdraw again
//         // should still get the 1:1 ratio(haven't changed the rate)
//         boringVault.withdraw(userWithdrawAmount, user, user);
//         assertEq(mockUSDC.balanceOf(address(user)), USER_USDC_INITIAL_BALANCE - userDepositAmount + userWithdrawAmount + userWithdrawAmount);
//         assertEq(mockUSDC.balanceOf(address(boringVault)), userDepositAmount - userWithdrawAmount + 5_000_000e6 - userWithdrawAmount);
//         assertEq(boringVault.balanceOf(address(user)), userDepositAmount - userWithdrawAmount - userWithdrawAmount);

//         // 4. update the accountant exchange rate
//         skip(1 days);
//         accountant.updateExchangeRate(1.001e6);
//         console.log("the rate is: ", accountant.getRateSafe());

//         // 5. withdraw again
//         boringVault.withdraw(userWithdrawAmount, user, user);
//         assertEq(mockUSDC.balanceOf(address(user)), USER_USDC_INITIAL_BALANCE - userDepositAmount + userWithdrawAmount + userWithdrawAmount + userWithdrawAmount);
//         assertEq(mockUSDC.balanceOf(address(boringVault)), userDepositAmount - userWithdrawAmount + 5_000_000e6 - userWithdrawAmount - userWithdrawAmount);
//         // should get the new ratio since the accountant exchange rate has changed
//         assertGt(boringVault.balanceOf(address(user)), userDepositAmount - userWithdrawAmount - userWithdrawAmount - userWithdrawAmount);

//         vm.stopPrank();
//     }

//     function testDepositCompare() external {
//         // erc4626 deposit should get the same result as the teller deposit
//         vm.startPrank(user);

//         // 1. update the accountant rate
//         skip(1 days);
//         accountant.updateExchangeRate(1.001e6);
//         console.log("the rate is: ", accountant.getRateSafe());

//         // 2. get the result of the teller deposit and erc4626 deposit
//         uint256 tellerDepositAmount = teller.deposit(mockUSDC, 1_000_000e6, 0);

//         // use previewDeposit to get the result of the erc4626 deposit
//         uint256 erc4626DepositAmount = boringVault.previewDeposit(1_000_000e6);
//         assertEq(tellerDepositAmount, erc4626DepositAmount);
//         console.log("teller deposit amount: ", tellerDepositAmount);

//         vm.stopPrank();
//     }

//     function testWithdrawCompare() external {
//         // erc4626 withdraw should get the same result as the boring queue withdraw
//         vm.startPrank(user);

//         boringVault.deposit(5_000_000e6, user);

//         // 1. update the accountant rate
//         skip(1 days);
//         accountant.updateExchangeRate(1.001e6);
//         console.log("the rate is: ", accountant.getRateSafe());

//         // 2. get the result of the boring queue withdraw and erc4626 withdraw
//         uint256 boringQueueWithdrawShares = 1_000_000e6; // shares amount
//         uint256 USDCBefore = mockUSDC.balanceOf(address(user));
//         AtomicRequest memory req = AtomicRequest({
//             deadline: uint64(block.timestamp + atomicQueue.maturityTime() * 2),
//             creationTime: uint64(block.timestamp),
//             atomicPrice: uint88(1.001e6),
//             offerAmount: uint96(boringQueueWithdrawShares)
//         });

//         atomicQueue.updateAtomicRequest(ERC20(address(boringVault)), mockUSDC, req);

//         // Approve solver
//         mockUSDC.approve(address(atomicSolverV4), type(uint256).max);
//         boringVault.approve(address(atomicSolverV4), type(uint256).max);

//         // Warp past maturity time
//         vm.warp(block.timestamp + atomicQueue.maturityTime() + 1);

//         atomicSolverV4.redeemSelfSolve(
//             atomicQueue, ERC20(address(boringVault)), mockUSDC, user, 0, type(uint256).max, teller, req
//         );
//         uint256 USDCIncrease = mockUSDC.balanceOf(address(user)) - USDCBefore;
        
//         uint256 erc4626WithdrawAmount = boringVault.withdraw(boringQueueWithdrawShares * uint256(1001) / uint256(1000), user, user);

//         // increase same USDC amount: 1_000_000e6 * rate
//         assertEq(USDCIncrease, boringQueueWithdrawShares * uint256(1001) / uint256(1000));
//         // decrease same shares amount: 1_000_000e6
//         assertEq(boringQueueWithdrawShares, erc4626WithdrawAmount);

//         vm.stopPrank();
//     }

//     // function testUpgrade() external {
//     // }

//     // function testAuth() external {
//     // }

//     // function testReverts() external {
//     //     }

//     // ========================================= HELPER FUNCTIONS =========================================

//     function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
//         forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
//         vm.selectFork(forkId);
//     }
// }
