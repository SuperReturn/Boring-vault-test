// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
import {AirVault} from "src/base/AirVault.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {ILiquidityPool} from "src/interfaces/IStaking.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {AtomicSolverV4, AtomicQueue} from "src/atomic-queue/AtomicSolverV4.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {AtomicQueue, AtomicRequest} from "src/atomic-queue/AtomicQueue.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";

contract AirVaultTest is Test, MainnetAddresses {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    AirVault public airVault;
    
    Deployer public deployer;
    BoringVault public superusd;
    BoringVault public ssuperusd;
    TellerWithMultiAssetSupport public superusdTeller;
    TellerWithMultiAssetSupport public ssuperusdTeller;
    AtomicQueue public ssuperusdAtomicQueue;

    ERC20 public usdc;
    ERC20 public weth;

    address public user1 = vm.addr(1);
    address public user2 = vm.addr(2);
    address public user3 = vm.addr(3);

    uint256 public constant WeiPerUsdc = 1e6; // 6 decimals
    uint256 public constant WeiPerEther = 1e18; // 18 decimals

    event Deposit(address indexed from, address indexed to, address indexed asset, uint256 depositAmount, uint256 amountMinted);
    event Withdraw(address indexed from, address indexed to, uint256 amountShares, uint256 amountSSuperUSD);

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "KATANA_RPC_URL";
        uint256 blockNumber = 18611000;
        _startFork(rpcKey, blockNumber);

        // get current contracts
        superusd = BoringVault(payable(address(0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB)));
        ssuperusd = BoringVault(payable(address(0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd)));
        superusdTeller = TellerWithMultiAssetSupport(address(0xF62D61F304C9c65C96a94c2b0b93c8f93C96e91D));
        ssuperusdTeller = TellerWithMultiAssetSupport(address(0xa8aA5c00d6c3f7A77FC5769770f6bC7b9244699b));
        ssuperusdAtomicQueue = AtomicQueue(address(0xd484d2991D168b33cC61e25f80af0145883Bc465));
        usdc = ERC20(address(0x203A662b0BD271A6ed5a60EdFbd04bFce608FD36)); // vbusdc
        weth = ERC20(address(0xEE7D8BCFb72bC1880D0Cf19822eB0A2e6577aB62)); // vbweth

        // deploy deployer
        deployer = new Deployer(address(this), Authority(address(0)));

        // Deploy implementation
        address implementation = deployer.deployContract(
            "AirVault-Implementation",
            type(AirVault).creationCode,
            abi.encode(address(superusd), address(ssuperusd), address(superusdTeller), address(ssuperusdTeller), address(ssuperusdAtomicQueue)),
            0
        );

        // Prepare initializer data
        bytes memory initializer = abi.encodeWithSelector(
            AirVault.initialize.selector,
            address(this),  // owner
            Authority(address(0)),  // authority
            "katSuperUSD", // name
            "katSuperUSD",  // symbol
            6  // decimals
        );

        // Deploy proxy
        bytes memory proxyCreationCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initializer)
        );
        address proxy = deployer.deployContract(
            "AirVault",
            proxyCreationCode,
            hex"",
            0
        );

        airVault = AirVault(payable(proxy));

        // Fund test users
        deal(address(usdc), user1, WeiPerUsdc * 1000);
        deal(address(usdc), user2, WeiPerUsdc * 1000);
    }

    function testDeployReverts() external {
        // reverts with string "INITIALIZATION_FAILED"

        vm.expectRevert();
        deployer.deployContract(
            "AirVault-Implementation-2",
            type(AirVault).creationCode,
            abi.encode(address(0), address(ssuperusd), address(superusdTeller), address(ssuperusdTeller), address(ssuperusdAtomicQueue)),
            0
        );

        vm.expectRevert();
        deployer.deployContract(
            "AirVault-Implementation-2",
            type(AirVault).creationCode,
            abi.encode(address(superusd), address(0), address(superusdTeller), address(ssuperusdTeller), address(ssuperusdAtomicQueue)),
            0
        );

        vm.expectRevert();
        deployer.deployContract(
            "AirVault-Implementation-2",
            type(AirVault).creationCode,
            abi.encode(address(superusd), address(ssuperusd), address(0), address(ssuperusdTeller), address(ssuperusdAtomicQueue)),
            0
        );

        vm.expectRevert();
        deployer.deployContract(
            "AirVault-Implementation-2",
            type(AirVault).creationCode,
            abi.encode(address(superusd), address(ssuperusd), address(superusdTeller), address(ssuperusdTeller), address(0)),
            0
        );

        vm.expectRevert();
        deployer.deployContract(
            "AirVault-Implementation-2",
            type(AirVault).creationCode,
            abi.encode(address(superusd), address(ssuperusd), address(superusdTeller), address(ssuperusdTeller), address(0)),
            0
        );
    }

    function testMetadata() external view {
        assertEq(airVault.name(), "katSuperUSD", "Name is incorrect");
        assertEq(airVault.symbol(), "katSuperUSD", "Symbol is incorrect");
        assertEq(airVault.decimals(), 6, "Decimals is incorrect");
    }

    function testViews() external view {
        assertEq(airVault.superusd(), address(superusd), "view superusd() is incorrect");
        assertEq(airVault.ssuperusd(), address(ssuperusd), "view ssuperusd() is incorrect");
        assertEq(airVault.superusdTeller(), address(superusdTeller), "view superusdTeller() is incorrect");
        assertEq(airVault.ssuperusdTeller(), address(ssuperusdTeller), "view ssuperusdTeller() is incorrect");
        assertEq(airVault.ssuperusdAtomicQueue(), address(ssuperusdAtomicQueue), "view ssuperusdAtomicQueue() is incorrect");
    }

    function testInitialBalances() external {
        assertEq(usdc.balanceOf(address(airVault)), 0, "initial usdc.balanceOf(vault) is incorrect");
        assertEq(superusd.balanceOf(address(airVault)), 0, "initial superusd.balanceOf(vault) is incorrect");
        assertEq(ssuperusd.balanceOf(address(airVault)), 0, "initial ssuperusd.balanceOf(vault) is incorrect");
        assertEq(usdc.balanceOf(user1), WeiPerUsdc*1000, "initial usdc.balanceOf(user1) is incorrect");
        assertEq(airVault.totalSupply(), 0, "initial vault.totalSupply() is incorrect");
        assertEq(airVault.balanceOf(user1), 0, "initial vault.balanceOf(user1) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user1), 0, "initial vault.getAccountTokenSeconds(user1) is incorrect");
        assertEq(airVault.getNumberOfHolders(), 0, "initial vault.getNumberOfHolders() is incorrect");
        vm.expectRevert();
        airVault.getHolderAtIndex(0);
        vm.expectRevert();
        airVault.getHolderAtIndex(1);
    }

    function testDepositInsufficientUsdcAllowance() external {
        vm.startPrank(user1);
        vm.expectRevert();
        airVault.deposit(address(usdc), 1, 0, user1);
        vm.stopPrank();
    }

    function testDepositInsufficientUsdcBalance() external {
        vm.startPrank(user1);
        usdc.approve(address(airVault), type(uint256).max);
        vm.expectRevert();
        airVault.deposit(address(usdc), WeiPerUsdc*1000 + 1, 0, user1);
        vm.stopPrank();
    }

    function testDepositInsufficientUsdcMint() external {
        vm.startPrank(user1);
        usdc.approve(address(airVault), type(uint256).max);
        vm.expectRevert();
        airVault.deposit(address(usdc), WeiPerUsdc*100, WeiPerUsdc*100+1, user1);
        vm.stopPrank();
    }

    // asset not supported
    function testDepositWeth() external {
        deal(address(weth), user1, WeiPerEther * 1000);
        vm.startPrank(user1);
        weth.approve(address(airVault), type(uint256).max);
        vm.expectRevert(); // TellerWithMultiAssetSupport__AssetNotSupported
        airVault.deposit(address(weth), WeiPerEther, WeiPerEther, user1);
        vm.stopPrank();
    }

    function testFlow1() external {
        _depositUsdc_1_1();
        _passTime_1_1();
        _transfer_1_1();
        _passTime_1_2();
        _transfer_1_2();
        _passTime_1_3();
        _depositSuperUSD_1_1();
        _passTime_1_4();
        _depositSSuperUSD_1_1();
        _withdraw_1_1();
        _testOverWithdraw_1_1();
        _testOverTransfer_1_1();
    }

    function _depositUsdc_1_1() internal {
        uint256 depositAmount = WeiPerUsdc*100;
        uint256 minimumMint = WeiPerUsdc*100;
        vm.startPrank(user1);
        usdc.approve(address(airVault), type(uint256).max);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user1, user1, address(usdc), depositAmount, minimumMint);
        airVault.deposit(address(usdc), depositAmount, minimumMint, user1);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(airVault)), 0, "updated usdc.balanceOf(vault) is incorrect");
        assertEq(superusd.balanceOf(address(airVault)), depositAmount, "updated superusd.balanceOf(vault) is incorrect");
        assertEq(ssuperusd.balanceOf(address(airVault)), 0, "updated ssuperusd.balanceOf(vault) is incorrect");
        assertEq(usdc.balanceOf(user1), WeiPerUsdc*900, "updated usdc.balanceOf(user1) is incorrect");
        assertEq(airVault.totalSupply(), depositAmount, "updated vault.totalSupply() is incorrect");
        assertEq(airVault.balanceOf(user1), depositAmount, "updated vault.balanceOf(user1) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user1), 0, "updated vault.getAccountTokenSeconds(user1) is incorrect"); // no time elapsed
        assertEq(airVault.getNumberOfHolders(), 1, "updated vault.getNumberOfHolders() is incorrect");
        assertEq(airVault.getHolderAtIndex(0), user1, "updated vault.getHolderAtIndex(0) is incorrect");
        vm.expectRevert();
        airVault.getHolderAtIndex(1);
    }

    function _passTime_1_1() internal {
        skip(10); // pass 10 seconds

        assertEq(usdc.balanceOf(address(airVault)), 0, "updated usdc.balanceOf(vault) is incorrect");
        assertEq(superusd.balanceOf(address(airVault)), WeiPerUsdc*100, "updated superusd.balanceOf(vault) is incorrect");
        assertEq(ssuperusd.balanceOf(address(airVault)), 0, "updated ssuperusd.balanceOf(vault) is incorrect");
        assertEq(usdc.balanceOf(user1), WeiPerUsdc*900, "updated usdc.balanceOf(user1) is incorrect");
        assertEq(airVault.totalSupply(), WeiPerUsdc*100, "updated vault.totalSupply() is incorrect");
        assertEq(airVault.balanceOf(user1), WeiPerUsdc*100, "updated vault.balanceOf(user1) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user1), WeiPerUsdc*1000, "updated vault.getAccountTokenSeconds(user1) is incorrect"); // 10 seconds elapsed
        assertEq(airVault.getNumberOfHolders(), 1, "updated vault.getNumberOfHolders() is incorrect");
        assertEq(airVault.getHolderAtIndex(0), user1, "updated vault.getHolderAtIndex(0) is incorrect");
        vm.expectRevert();
        airVault.getHolderAtIndex(1);
    }

    function _transfer_1_1() internal {
        vm.startPrank(user1);
        airVault.transfer(user2, WeiPerUsdc*25);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(airVault)), 0, "updated usdc.balanceOf(vault) is incorrect");
        assertEq(superusd.balanceOf(address(airVault)), WeiPerUsdc*100, "updated superusd.balanceOf(vault) is incorrect");
        assertEq(ssuperusd.balanceOf(address(airVault)), 0, "updated ssuperusd.balanceOf(vault) is incorrect");
        assertEq(usdc.balanceOf(user1), WeiPerUsdc*900, "updated usdc.balanceOf(user1) is incorrect");
        assertEq(usdc.balanceOf(user2), WeiPerUsdc*1000, "updated usdc.balanceOf(user2) is incorrect");
        assertEq(airVault.totalSupply(), WeiPerUsdc*100, "updated vault.totalSupply() is incorrect");
        assertEq(airVault.balanceOf(user1), WeiPerUsdc*75, "updated vault.balanceOf(user1) is incorrect");
        assertEq(airVault.balanceOf(user2), WeiPerUsdc*25, "updated vault.balanceOf(user2) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user1), WeiPerUsdc*1000, "updated vault.getAccountTokenSeconds(user1) is incorrect"); // 10 seconds elapsed
        assertEq(airVault.getAccountTokenSeconds(user2), 0, "updated vault.getAccountTokenSeconds(user2) is incorrect");
        assertEq(airVault.getNumberOfHolders(), 2, "updated vault.getNumberOfHolders() is incorrect");
        assertEq(airVault.getHolderAtIndex(0), user1, "updated vault.getHolderAtIndex(0) is incorrect");
        assertEq(airVault.getHolderAtIndex(1), user2, "updated vault.getHolderAtIndex(1) is incorrect");
        vm.expectRevert();
        airVault.getHolderAtIndex(2);
    }

    function _passTime_1_2() internal {
        skip(20); // pass 20 seconds

        assertEq(usdc.balanceOf(address(airVault)), 0, "updated usdc.balanceOf(vault) is incorrect");
        assertEq(superusd.balanceOf(address(airVault)), WeiPerUsdc*100, "updated superusd.balanceOf(vault) is incorrect");
        assertEq(ssuperusd.balanceOf(address(airVault)), 0, "updated ssuperusd.balanceOf(vault) is incorrect");
        assertEq(usdc.balanceOf(user1), WeiPerUsdc*900, "updated usdc.balanceOf(user1) is incorrect");
        assertEq(usdc.balanceOf(user2), WeiPerUsdc*1000, "updated usdc.balanceOf(user2) is incorrect");
        assertEq(airVault.totalSupply(), WeiPerUsdc*100, "updated vault.totalSupply() is incorrect");
        assertEq(airVault.balanceOf(user1), WeiPerUsdc*75, "updated vault.balanceOf(user1) is incorrect");
        assertEq(airVault.balanceOf(user2), WeiPerUsdc*25, "updated vault.balanceOf(user2) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user1), (WeiPerUsdc*100*10) + (WeiPerUsdc*75*20), "updated vault.getAccountTokenSeconds(user1) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user2), WeiPerUsdc*25*20, "updated vault.getAccountTokenSeconds(user2) is incorrect");
        assertEq(airVault.getNumberOfHolders(), 2, "updated vault.getNumberOfHolders() is incorrect");
        assertEq(airVault.getHolderAtIndex(0), user1, "updated vault.getHolderAtIndex(0) is incorrect");
        assertEq(airVault.getHolderAtIndex(1), user2, "updated vault.getHolderAtIndex(1) is incorrect");
        vm.expectRevert();
        airVault.getHolderAtIndex(2);
    }

    function _transfer_1_2() internal {
        vm.startPrank(user2);
        airVault.transfer(user1, WeiPerUsdc*10);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(airVault)), 0, "updated usdc.balanceOf(vault) is incorrect");
        assertEq(superusd.balanceOf(address(airVault)), WeiPerUsdc*100, "updated superusd.balanceOf(vault) is incorrect");
        assertEq(ssuperusd.balanceOf(address(airVault)), 0, "updated ssuperusd.balanceOf(vault) is incorrect");
        assertEq(usdc.balanceOf(user1), WeiPerUsdc*900, "updated usdc.balanceOf(user1) is incorrect");
        assertEq(usdc.balanceOf(user2), WeiPerUsdc*1000, "updated usdc.balanceOf(user2) is incorrect");
        assertEq(airVault.totalSupply(), WeiPerUsdc*100, "updated vault.totalSupply() is incorrect");
        assertEq(airVault.balanceOf(user1), WeiPerUsdc*85, "updated vault.balanceOf(user1) is incorrect");
        assertEq(airVault.balanceOf(user2), WeiPerUsdc*15, "updated vault.balanceOf(user2) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user1), (WeiPerUsdc*100*10) + (WeiPerUsdc*75*20), "updated vault.getAccountTokenSeconds(user1) is incorrect"); // 10 seconds elapsed
        assertEq(airVault.getAccountTokenSeconds(user2), (WeiPerUsdc*25*20), "updated vault.getAccountTokenSeconds(user2) is incorrect");
        assertEq(airVault.getNumberOfHolders(), 2, "updated vault.getNumberOfHolders() is incorrect");
        assertEq(airVault.getHolderAtIndex(0), user1, "updated vault.getHolderAtIndex(0) is incorrect");
        assertEq(airVault.getHolderAtIndex(1), user2, "updated vault.getHolderAtIndex(1) is incorrect");
        vm.expectRevert();
        airVault.getHolderAtIndex(2);
    }

    function _passTime_1_3() internal {
        skip(50); // pass 50 seconds

        assertEq(usdc.balanceOf(address(airVault)), 0, "updated usdc.balanceOf(vault) is incorrect");
        assertEq(superusd.balanceOf(address(airVault)), WeiPerUsdc*100, "updated superusd.balanceOf(vault) is incorrect");
        assertEq(ssuperusd.balanceOf(address(airVault)), 0, "updated ssuperusd.balanceOf(vault) is incorrect");
        assertEq(usdc.balanceOf(user1), WeiPerUsdc*900, "updated usdc.balanceOf(user1) is incorrect");
        assertEq(usdc.balanceOf(user2), WeiPerUsdc*1000, "updated usdc.balanceOf(user2) is incorrect");
        assertEq(airVault.totalSupply(), WeiPerUsdc*100, "updated vault.totalSupply() is incorrect");
        assertEq(airVault.balanceOf(user1), WeiPerUsdc*85, "updated vault.balanceOf(user1) is incorrect");
        assertEq(airVault.balanceOf(user2), WeiPerUsdc*15, "updated vault.balanceOf(user2) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user1), (WeiPerUsdc*100*10) + (WeiPerUsdc*75*20) + (WeiPerUsdc*85*50), "updated vault.getAccountTokenSeconds(user1) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user2), (WeiPerUsdc*25*20) + (WeiPerUsdc*15*50), "updated vault.getAccountTokenSeconds(user2) is incorrect");
        assertEq(airVault.getNumberOfHolders(), 2, "updated vault.getNumberOfHolders() is incorrect");
        assertEq(airVault.getHolderAtIndex(0), user1, "updated vault.getHolderAtIndex(0) is incorrect");
        assertEq(airVault.getHolderAtIndex(1), user2, "updated vault.getHolderAtIndex(1) is incorrect");
        vm.expectRevert();
        airVault.getHolderAtIndex(2);
    }

    function _depositSuperUSD_1_1() internal {
        vm.startPrank(user2);
        //usdc.approve(address(airVault), type(uint256).max);
        usdc.approve(address(superusd), type(uint256).max);
        superusdTeller.deposit(ERC20(address(usdc)), WeiPerUsdc*300, WeiPerUsdc*300);
        superusd.approve(address(airVault), type(uint256).max);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user2, user2, address(superusd), WeiPerUsdc*200, WeiPerUsdc*200);
        airVault.deposit(address(superusd), WeiPerUsdc*200, WeiPerUsdc*200, user2);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(airVault)), 0, "updated usdc.balanceOf(vault) is incorrect");
        assertEq(superusd.balanceOf(address(airVault)), WeiPerUsdc*300, "updated superusd.balanceOf(vault) is incorrect");
        assertEq(ssuperusd.balanceOf(address(airVault)), 0, "updated ssuperusd.balanceOf(vault) is incorrect");
        assertEq(usdc.balanceOf(user1), WeiPerUsdc*900, "updated usdc.balanceOf(user1) is incorrect");
        assertEq(usdc.balanceOf(user2), WeiPerUsdc*700, "updated usdc.balanceOf(user2) is incorrect");
        assertEq(superusd.balanceOf(user1), 0, "updated superusd.balanceOf(user1) is incorrect");
        assertEq(superusd.balanceOf(user2), WeiPerUsdc*100, "updated superusd.balanceOf(user2) is incorrect");
        assertEq(airVault.totalSupply(), WeiPerUsdc*300, "updated vault.totalSupply() is incorrect");
        assertEq(airVault.balanceOf(user1), WeiPerUsdc*85, "updated vault.balanceOf(user1) is incorrect");
        assertEq(airVault.balanceOf(user2), WeiPerUsdc*215, "updated vault.balanceOf(user2) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user1), (WeiPerUsdc*100*10) + (WeiPerUsdc*75*20) + (WeiPerUsdc*85*50), "updated vault.getAccountTokenSeconds(user1) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user2), (WeiPerUsdc*25*20) + (WeiPerUsdc*15*50), "updated vault.getAccountTokenSeconds(user2) is incorrect");
        assertEq(airVault.getNumberOfHolders(), 2, "updated vault.getNumberOfHolders() is incorrect");
        assertEq(airVault.getHolderAtIndex(0), user1, "updated vault.getHolderAtIndex(0) is incorrect");
        assertEq(airVault.getHolderAtIndex(1), user2, "updated vault.getHolderAtIndex(1) is incorrect");
        vm.expectRevert();
        airVault.getHolderAtIndex(2);
    }

    function _passTime_1_4() internal {
        skip(200); // pass 200 seconds

        assertEq(usdc.balanceOf(address(airVault)), 0, "updated usdc.balanceOf(vault) is incorrect");
        assertEq(superusd.balanceOf(address(airVault)), WeiPerUsdc*300, "updated superusd.balanceOf(vault) is incorrect");
        assertEq(ssuperusd.balanceOf(address(airVault)), 0, "updated ssuperusd.balanceOf(vault) is incorrect");
        assertEq(usdc.balanceOf(user1), WeiPerUsdc*900, "updated usdc.balanceOf(user1) is incorrect");
        assertEq(usdc.balanceOf(user2), WeiPerUsdc*700, "updated usdc.balanceOf(user2) is incorrect");
        assertEq(superusd.balanceOf(user1), 0, "updated superusd.balanceOf(user1) is incorrect");
        assertEq(superusd.balanceOf(user2), WeiPerUsdc*100, "updated superusd.balanceOf(user2) is incorrect");
        assertEq(airVault.totalSupply(), WeiPerUsdc*300, "updated vault.totalSupply() is incorrect");
        assertEq(airVault.balanceOf(user1), WeiPerUsdc*85, "updated vault.balanceOf(user1) is incorrect");
        assertEq(airVault.balanceOf(user2), WeiPerUsdc*215, "updated vault.balanceOf(user2) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user1), (WeiPerUsdc*100*10) + (WeiPerUsdc*75*20) + (WeiPerUsdc*85*50) + (WeiPerUsdc*85*200), "updated vault.getAccountTokenSeconds(user1) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user2), (WeiPerUsdc*25*20) + (WeiPerUsdc*15*50) + (WeiPerUsdc*215*200), "updated vault.getAccountTokenSeconds(user2) is incorrect");
        assertEq(airVault.getNumberOfHolders(), 2, "updated vault.getNumberOfHolders() is incorrect");
        assertEq(airVault.getHolderAtIndex(0), user1, "updated vault.getHolderAtIndex(0) is incorrect");
        assertEq(airVault.getHolderAtIndex(1), user2, "updated vault.getHolderAtIndex(1) is incorrect");
        vm.expectRevert();
        airVault.getHolderAtIndex(2);
    }

    function _depositSSuperUSD_1_1() internal {
        vm.startPrank(user2);
        superusd.approve(address(ssuperusd), type(uint256).max);
        ssuperusdTeller.deposit(ERC20(address(superusd)), WeiPerUsdc*100, 0);
        ssuperusd.approve(address(airVault), type(uint256).max);
        //console.log("deposited superusd    :", WeiPerUsdc * 100);
        //console.log("received ssuperusd    :", ERC20(address(ssuperusd)).balanceOf(user2));
        uint256 ssuperusdBalance1 = ERC20(address(ssuperusd)).balanceOf(user2);
        uint256 depositAmount = WeiPerUsdc*10;
        uint256 expectedMintAmount = 10524860;
        vm.expectEmit(true, true, true, true);
        emit Deposit(user2, user3, address(ssuperusd), depositAmount, expectedMintAmount);
        airVault.deposit(address(ssuperusd), depositAmount, expectedMintAmount, user3);
        uint256 mintAmount = ERC20(address(airVault)).balanceOf(user3);
        assertEq(mintAmount, expectedMintAmount, "mintAmount is incorrect");
        //console.log("deposited ssuperusd   :", depositAmount);
        //console.log("received katsuperusd  :", mintAmount);
        uint256 totalSupply2 = WeiPerUsdc*300 + mintAmount;
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(airVault)), 0, "updated usdc.balanceOf(vault) is incorrect");
        assertEq(superusd.balanceOf(address(airVault)), totalSupply2, "updated superusd.balanceOf(vault) is incorrect");
        assertEq(ssuperusd.balanceOf(address(airVault)), 0, "updated ssuperusd.balanceOf(vault) is incorrect");
        assertEq(usdc.balanceOf(user1), WeiPerUsdc*900, "updated usdc.balanceOf(user1) is incorrect");
        assertEq(usdc.balanceOf(user2), WeiPerUsdc*700, "updated usdc.balanceOf(user2) is incorrect");
        assertEq(usdc.balanceOf(user3), 0, "updated usdc.balanceOf(user3) is incorrect");
        assertEq(superusd.balanceOf(user1), 0, "updated superusd.balanceOf(user1) is incorrect");
        assertEq(superusd.balanceOf(user2), 0, "updated superusd.balanceOf(user2) is incorrect");
        assertEq(superusd.balanceOf(user3), 0, "updated superusd.balanceOf(user3) is incorrect");
        assertEq(airVault.totalSupply(), totalSupply2, "updated vault.totalSupply() is incorrect");
        assertEq(airVault.balanceOf(user1), WeiPerUsdc*85, "updated vault.balanceOf(user1) is incorrect");
        assertEq(airVault.balanceOf(user2), WeiPerUsdc*215, "updated vault.balanceOf(user2) is incorrect");
        assertEq(airVault.balanceOf(user3), mintAmount, "updated vault.balanceOf(user3) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user1), (WeiPerUsdc*100*10) + (WeiPerUsdc*75*20) + (WeiPerUsdc*85*50) + (WeiPerUsdc*85*200), "updated vault.getAccountTokenSeconds(user1) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user2), (WeiPerUsdc*25*20) + (WeiPerUsdc*15*50) + (WeiPerUsdc*215*200), "updated vault.getAccountTokenSeconds(user2) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user3), 0, "updated vault.getAccountTokenSeconds(user2) is incorrect");
        assertEq(airVault.getNumberOfHolders(), 3, "updated vault.getNumberOfHolders() is incorrect");
        assertEq(airVault.getHolderAtIndex(0), user1, "updated vault.getHolderAtIndex(0) is incorrect");
        assertEq(airVault.getHolderAtIndex(1), user2, "updated vault.getHolderAtIndex(1) is incorrect");
        assertEq(airVault.getHolderAtIndex(2), user3, "updated vault.getHolderAtIndex(2) is incorrect");
        vm.expectRevert();
        airVault.getHolderAtIndex(3);
    }

    function _withdraw_1_1() internal {
        uint256 totalSupply1 = airVault.totalSupply();
        uint256 balance13 = airVault.balanceOf(user3);
        uint256 withdrawAmountShares = WeiPerUsdc * 20;
        uint256 totalSupply2 = totalSupply1 - withdrawAmountShares;
        uint256 withdrawAmountSSuperUSD = 19002628;

        assertEq(ssuperusd.balanceOf(user1), 0, "start ssuperusd.balanceOf(user1) is incorrect");
        assertEq(ssuperusd.balanceOf(user2), 85013140, "start ssuperusd.balanceOf(user2) is incorrect");
        assertEq(ssuperusd.balanceOf(user3), 0, "start ssuperusd.balanceOf(user3) is incorrect");

        vm.startPrank(user2);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(user2, user3, withdrawAmountShares, withdrawAmountSSuperUSD);
        airVault.withdraw(withdrawAmountShares, user3);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(airVault)), 0, "updated usdc.balanceOf(vault) is incorrect");
        assertEq(superusd.balanceOf(address(airVault)), totalSupply2, "updated superusd.balanceOf(vault) is incorrect");
        assertEq(ssuperusd.balanceOf(address(airVault)), 0, "updated ssuperusd.balanceOf(vault) is incorrect");
        assertEq(usdc.balanceOf(user1), WeiPerUsdc*900, "updated usdc.balanceOf(user1) is incorrect");
        assertEq(usdc.balanceOf(user2), WeiPerUsdc*700, "updated usdc.balanceOf(user2) is incorrect");
        assertEq(usdc.balanceOf(user3), 0, "updated usdc.balanceOf(user3) is incorrect");
        assertEq(superusd.balanceOf(user1), 0, "updated superusd.balanceOf(user1) is incorrect");
        assertEq(superusd.balanceOf(user2), 0, "updated superusd.balanceOf(user2) is incorrect");
        assertEq(superusd.balanceOf(user3), 0, "updated superusd.balanceOf(user3) is incorrect");
        assertEq(ssuperusd.balanceOf(user1), 0, "updated ssuperusd.balanceOf(user1) is incorrect");
        assertEq(ssuperusd.balanceOf(user2), 85013140, "updated ssuperusd.balanceOf(user2) is incorrect");
        assertEq(ssuperusd.balanceOf(user3), withdrawAmountSSuperUSD, "updated ssuperusd.balanceOf(user3) is incorrect");
        assertEq(airVault.totalSupply(), totalSupply2, "updated vault.totalSupply() is incorrect");
        assertEq(airVault.balanceOf(user1), WeiPerUsdc*85, "updated vault.balanceOf(user1) is incorrect");
        assertEq(airVault.balanceOf(user2), WeiPerUsdc*195, "updated vault.balanceOf(user2) is incorrect");
        assertEq(airVault.balanceOf(user3), balance13, "updated vault.balanceOf(user3) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user1), (WeiPerUsdc*100*10) + (WeiPerUsdc*75*20) + (WeiPerUsdc*85*50) + (WeiPerUsdc*85*200), "updated vault.getAccountTokenSeconds(user1) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user2), (WeiPerUsdc*25*20) + (WeiPerUsdc*15*50) + (WeiPerUsdc*215*200), "updated vault.getAccountTokenSeconds(user2) is incorrect");
        assertEq(airVault.getAccountTokenSeconds(user3), 0, "updated vault.getAccountTokenSeconds(user2) is incorrect");
        assertEq(airVault.getNumberOfHolders(), 3, "updated vault.getNumberOfHolders() is incorrect");
        assertEq(airVault.getHolderAtIndex(0), user1, "updated vault.getHolderAtIndex(0) is incorrect");
        assertEq(airVault.getHolderAtIndex(1), user2, "updated vault.getHolderAtIndex(1) is incorrect");
        assertEq(airVault.getHolderAtIndex(2), user3, "updated vault.getHolderAtIndex(2) is incorrect");
        vm.expectRevert();
        airVault.getHolderAtIndex(3);
    }

    function _testOverWithdraw_1_1() internal {
        uint256 bal = airVault.balanceOf(user1);
        vm.startPrank(user1);
        vm.expectRevert();
        airVault.withdraw(bal+1, user1);
        vm.stopPrank();
    }

    function _testOverTransfer_1_1() internal {
        uint256 bal = airVault.balanceOf(user1);
        vm.startPrank(user1);
        vm.expectRevert();
        airVault.transfer(user1, bal+1);
        vm.stopPrank();
    }


    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}