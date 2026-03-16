// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Multisend} from "src/helper/Multisend.sol";
import {Test, console} from "@forge-std/Test.sol";

// ========================================= MOCK CONTRACTS =========================================

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC", 6) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Contract that rejects ETH transfers (no receive/fallback).
contract ETHRejecter {}

// ========================================= TEST CONTRACT =========================================

contract MultisendTest is Test {
    MockUSDC public usdc;
    Multisend public multisend;

    address public sender;
    address public receiver1;
    address public receiver2;
    address public receiver3;

    function setUp() public {
        usdc = new MockUSDC();
        multisend = new Multisend(address(this));

        sender = vm.addr(1);
        receiver1 = vm.addr(2);
        receiver2 = vm.addr(3);
        receiver3 = vm.addr(4);

        // Mint tokens to sender and approve Multisend.
        usdc.mint(sender, 100_000e6);
        vm.prank(sender);
        usdc.approve(address(multisend), type(uint256).max);

        // Fund sender with ETH.
        deal(sender, 100 ether);
    }

    // ========================================= HAPPY PATH: ERC20 =========================================

    function testMultisendERC20() public {
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](3);
        receivers[0] = Multisend.ReceiverAndAmount(receiver1, 1_000e6);
        receivers[1] = Multisend.ReceiverAndAmount(receiver2, 2_000e6);
        receivers[2] = Multisend.ReceiverAndAmount(receiver3, 3_000e6);
        uint256 totalAmount = 6_000e6;

        uint256 senderBalBefore = usdc.balanceOf(sender);

        vm.prank(sender);
        multisend.multisend(address(usdc), totalAmount, receivers);

        assertEq(usdc.balanceOf(sender), senderBalBefore - totalAmount, "sender balance");
        assertEq(usdc.balanceOf(address(multisend)), 0, "multisend balance");
        assertEq(usdc.balanceOf(receiver1), 1_000e6, "receiver1 balance");
        assertEq(usdc.balanceOf(receiver2), 2_000e6, "receiver2 balance");
        assertEq(usdc.balanceOf(receiver3), 3_000e6, "receiver3 balance");
    }

    function testMultisendERC20SingleReceiver() public {
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](1);
        receivers[0] = Multisend.ReceiverAndAmount(receiver1, 5_000e6);

        vm.prank(sender);
        multisend.multisend(address(usdc), 5_000e6, receivers);

        assertEq(usdc.balanceOf(receiver1), 5_000e6, "receiver1 balance");
        assertEq(usdc.balanceOf(address(multisend)), 0, "multisend balance");
    }

    // ========================================= HAPPY PATH: ETH =========================================

    function testMultisendETH() public {
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](3);
        receivers[0] = Multisend.ReceiverAndAmount(receiver1, 1 ether);
        receivers[1] = Multisend.ReceiverAndAmount(receiver2, 2 ether);
        receivers[2] = Multisend.ReceiverAndAmount(receiver3, 3 ether);
        uint256 totalAmount = 6 ether;

        uint256 senderBalBefore = sender.balance;

        vm.prank(sender);
        multisend.multisendETH{value: totalAmount}(receivers);

        assertEq(sender.balance, senderBalBefore - totalAmount, "sender ETH balance");
        assertEq(address(multisend).balance, 0, "multisend ETH balance");
        assertEq(receiver1.balance, 1 ether, "receiver1 ETH balance");
        assertEq(receiver2.balance, 2 ether, "receiver2 ETH balance");
        assertEq(receiver3.balance, 3 ether, "receiver3 ETH balance");
    }

    function testMultisendETHSingleReceiver() public {
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](1);
        receivers[0] = Multisend.ReceiverAndAmount(receiver1, 4 ether);

        vm.prank(sender);
        multisend.multisendETH{value: 4 ether}(receivers);

        assertEq(receiver1.balance, 4 ether, "receiver1 ETH balance");
        assertEq(address(multisend).balance, 0, "multisend ETH balance");
    }

    // ========================================= UNHAPPY PATH: ERC20 =========================================

    function testMultisendERC20_RevertAmountMismatch_TotalTooHigh() public {
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](2);
        receivers[0] = Multisend.ReceiverAndAmount(receiver1, 1_000e6);
        receivers[1] = Multisend.ReceiverAndAmount(receiver2, 2_000e6);

        // totalAmount (5_000e6) > sum of receivers (3_000e6)
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Multisend.AmountMismatch.selector, 5_000e6, 3_000e6));
        multisend.multisend(address(usdc), 5_000e6, receivers);
    }

    function testMultisendERC20_RevertAmountMismatch_TotalTooLow() public {
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](2);
        receivers[0] = Multisend.ReceiverAndAmount(receiver1, 1_000e6);
        receivers[1] = Multisend.ReceiverAndAmount(receiver2, 2_000e6);

        // totalAmount (1_000e6) < sum of receivers (3_000e6) — safeTransfer will revert on insufficient balance.
        vm.prank(sender);
        vm.expectRevert();
        multisend.multisend(address(usdc), 1_000e6, receivers);
    }

    function testMultisendERC20_RevertNoApproval() public {
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](1);
        receivers[0] = Multisend.ReceiverAndAmount(receiver1, 1_000e6);

        // receiver2 has no approval set.
        usdc.mint(receiver2, 1_000e6);
        vm.prank(receiver2);
        vm.expectRevert();
        multisend.multisend(address(usdc), 1_000e6, receivers);
    }

    function testMultisendERC20_RevertInsufficientBalance() public {
        address poorSender = vm.addr(10);
        usdc.mint(poorSender, 100e6);

        vm.startPrank(poorSender);
        usdc.approve(address(multisend), type(uint256).max);

        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](1);
        receivers[0] = Multisend.ReceiverAndAmount(receiver1, 1_000e6);

        vm.expectRevert();
        multisend.multisend(address(usdc), 1_000e6, receivers);
        vm.stopPrank();
    }

    // ========================================= UNHAPPY PATH: ETH =========================================

    function testMultisendETH_RevertAmountMismatch() public {
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](2);
        receivers[0] = Multisend.ReceiverAndAmount(receiver1, 1 ether);
        receivers[1] = Multisend.ReceiverAndAmount(receiver2, 2 ether);

        // msg.value (5 ether) != sum of receivers (3 ether)
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Multisend.AmountMismatch.selector, 5 ether, 3 ether));
        multisend.multisendETH{value: 5 ether}(receivers);
    }

    function testMultisendETH_RevertETHTransferFailed() public {
        ETHRejecter rejecter = new ETHRejecter();

        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](2);
        receivers[0] = Multisend.ReceiverAndAmount(receiver1, 1 ether);
        receivers[1] = Multisend.ReceiverAndAmount(address(rejecter), 1 ether);

        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Multisend.ETHTransferFailed.selector, address(rejecter)));
        multisend.multisendETH{value: 2 ether}(receivers);
    }

    // ========================================= EDGE CASES =========================================

    function testMultisendERC20EmptyReceivers() public {
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](0);

        // Empty receivers with totalAmount = 0 should succeed.
        vm.prank(sender);
        multisend.multisend(address(usdc), 0, receivers);

        // Empty receivers with totalAmount > 0 should revert.
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Multisend.AmountMismatch.selector, 1_000e6, 0));
        multisend.multisend(address(usdc), 1_000e6, receivers);
    }

    function testMultisendETHEmptyReceivers() public {
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](0);

        // Empty receivers with msg.value = 0 should succeed.
        vm.prank(sender);
        multisend.multisendETH{value: 0}(receivers);

        // Empty receivers with msg.value > 0 should revert.
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Multisend.AmountMismatch.selector, 1 ether, 0));
        multisend.multisendETH{value: 1 ether}(receivers);
    }

    function testMultisendERC20ZeroAmountReceiver() public {
        Multisend.ReceiverAndAmount[] memory receivers = new Multisend.ReceiverAndAmount[](3);
        receivers[0] = Multisend.ReceiverAndAmount(receiver1, 1_000e6);
        receivers[1] = Multisend.ReceiverAndAmount(receiver2, 0);
        receivers[2] = Multisend.ReceiverAndAmount(receiver3, 2_000e6);

        vm.prank(sender);
        multisend.multisend(address(usdc), 3_000e6, receivers);

        assertEq(usdc.balanceOf(receiver1), 1_000e6, "receiver1 balance");
        assertEq(usdc.balanceOf(receiver2), 0, "receiver2 balance");
        assertEq(usdc.balanceOf(receiver3), 2_000e6, "receiver3 balance");
        assertEq(usdc.balanceOf(address(multisend)), 0, "multisend balance");
    }
}
