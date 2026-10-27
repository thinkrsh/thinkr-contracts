// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ClaimDeposit} from "../src/ClaimDeposit.sol";
import {ClaimDepositFactory} from "../src/ClaimDepositFactory.sol";

/// A plain ERC-20 with a mint for the tests, as THKR is one.
contract TestToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external virtual returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// A token that answers false to a transfer instead of reverting.
contract FalseToken is TestToken {
    function transfer(address, uint256) external pure override returns (bool) {
        return false;
    }
}

/// A token whose transfer returns nothing, as some old tokens do.
contract SilentToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}

contract ClaimDepositFactoryTest is Test {
    address constant BURN = 0x000000000000000000000000000000000000dEaD;
    uint256 constant BURN_AMOUNT = 1_000e18;
    address owner = makeAddr("owner");
    address operator = makeAddr("operator");
    address wallet = makeAddr("wallet");
    address stranger = makeAddr("stranger");
    bytes32 claimId = keccak256("claim 1");
    TestToken thkr;
    ClaimDepositFactory factory;

    event Settled(
        address indexed wallet, bytes32 indexed claimId, uint256 burned, uint256 returned
    );
    event Refunded(
        address indexed wallet, bytes32 indexed claimId, address indexed asset, uint256 amount
    );

    function setUp() public {
        thkr = new TestToken();
        factory = new ClaimDepositFactory(address(thkr), BURN, BURN_AMOUNT, owner, operator);
    }

    /// THKR sent to the deposit address before the deposit exists, as a wallet app sends it.
    function sendToDeposit(address from, uint256 amount) internal returns (address deposit) {
        deposit = factory.depositAddress(wallet, claimId);
        thkr.mint(from, amount);
        vm.prank(from);
        thkr.transfer(deposit, amount);
    }

    function test_DeploysTheDepositAtTheAddressItNamed() public {
        address named = factory.depositAddress(wallet, claimId);
        assertEq(named.code.length, 0);
        vm.prank(operator);
        factory.settle(wallet, claimId);
        assertGt(named.code.length, 0);
        assertEq(ClaimDeposit(named).wallet(), wallet);
        assertEq(ClaimDeposit(named).factory(), address(factory));
    }

    function test_SettleBurnsTheAmountAndReturnsTheRest() public {
        address deposit = sendToDeposit(wallet, 1_500e18);
        vm.expectEmit(address(factory));
        emit Settled(wallet, claimId, 1_000e18, 500e18);
        vm.prank(operator);
        (uint256 burned, uint256 returned) = factory.settle(wallet, claimId);
        assertEq(burned, 1_000e18);
        assertEq(returned, 500e18);
        assertEq(thkr.balanceOf(BURN), 1_000e18);
        assertEq(thkr.balanceOf(wallet), 500e18);
        assertEq(thkr.balanceOf(deposit), 0);
        assertTrue(factory.settled(deposit));
    }

    function test_SettleBurnsNoMoreThanTheDepositHolds() public {
        sendToDeposit(wallet, 400e18);
        vm.prank(operator);
        (uint256 burned, uint256 returned) = factory.settle(wallet, claimId);
        assertEq(burned, 400e18);
        assertEq(returned, 0);
    }

    function test_AClaimSettlesOnceAndLaterTHKROnlyGoesBack() public {
        sendToDeposit(wallet, 1_000e18);
        vm.prank(operator);
        factory.settle(wallet, claimId);
        sendToDeposit(wallet, 2_000e18);
        vm.prank(operator);
        vm.expectRevert(ClaimDepositFactory.AlreadySettled.selector);
        factory.settle(wallet, claimId);
        vm.prank(operator);
        factory.refund(wallet, claimId, address(thkr));
        assertEq(thkr.balanceOf(BURN), 1_000e18);
        assertEq(thkr.balanceOf(wallet), 2_000e18);
    }

    function test_TheOperatorRefundsAllOfADepositToItsWallet() public {
        address deposit = sendToDeposit(wallet, 4_821e18);
        vm.expectEmit(address(factory));
        emit Refunded(wallet, claimId, address(thkr), 4_821e18);
        vm.prank(operator);
        assertEq(factory.refund(wallet, claimId, address(thkr)), 4_821e18);
        assertEq(thkr.balanceOf(wallet), 4_821e18);
        assertEq(thkr.balanceOf(BURN), 0);
        assertEq(thkr.balanceOf(deposit), 0);
    }

    function test_TheWalletRefundsItselfWithoutTheOperator() public {
        sendToDeposit(wallet, 1_200e18);
        vm.prank(wallet);
        factory.refund(wallet, claimId, address(thkr));
        assertEq(thkr.balanceOf(wallet), 1_200e18);
    }

    function test_THKRFromAnotherWalletGoesBackToTheWalletOfTheClaim() public {
        sendToDeposit(stranger, 1_000e18);
        vm.prank(operator);
        factory.refund(wallet, claimId, address(thkr));
        assertEq(thkr.balanceOf(wallet), 1_000e18);
        assertEq(thkr.balanceOf(stranger), 0);
    }

    function test_OnlyTheOperatorSettles() public {
        sendToDeposit(wallet, 1_000e18);
        for (uint256 i = 0; i < 3; i++) {
            address caller = [owner, wallet, stranger][i];
            vm.prank(caller);
            vm.expectRevert(ClaimDepositFactory.NotOperator.selector);
            factory.settle(wallet, claimId);
        }
    }

    function test_OnlyTheOperatorOrTheWalletRefunds() public {
        sendToDeposit(wallet, 1_000e18);
        vm.prank(stranger);
        vm.expectRevert(ClaimDepositFactory.NotAllowed.selector);
        factory.refund(wallet, claimId, address(thkr));
        vm.prank(owner);
        vm.expectRevert(ClaimDepositFactory.NotAllowed.selector);
        factory.refund(wallet, claimId, address(thkr));
    }

    function test_AnotherTokenSentByMistakeGoesBackWhole() public {
        TestToken other = new TestToken();
        address deposit = factory.depositAddress(wallet, claimId);
        other.mint(deposit, 77e18);
        vm.prank(operator);
        factory.refund(wallet, claimId, address(other));
        assertEq(other.balanceOf(wallet), 77e18);
    }

    function test_TheWalletIsPartOfTheAddress() public {
        address other = factory.depositAddress(stranger, claimId);
        assertTrue(other != factory.depositAddress(wallet, claimId));
        sendToDeposit(wallet, 1_000e18);
        // The claim of another wallet with the same id reaches another deposit, an empty one.
        vm.prank(operator);
        (uint256 burned,) = factory.settle(stranger, claimId);
        assertEq(burned, 0);
        assertEq(thkr.balanceOf(factory.depositAddress(wallet, claimId)), 1_000e18);
    }

    function test_OnlyTheFactoryReleasesADeposit() public {
        sendToDeposit(wallet, 1_000e18);
        vm.prank(operator);
        factory.settle(wallet, claimId);
        ClaimDeposit deposit = ClaimDeposit(factory.depositAddress(wallet, claimId));
        vm.prank(operator);
        vm.expectRevert(ClaimDeposit.NotFactory.selector);
        deposit.release(address(thkr), stranger, 1);
    }

    function test_ATokenThatAnswersFalseFailsLoudly() public {
        FalseToken bad = new FalseToken();
        bad.mint(factory.depositAddress(wallet, claimId), 5e18);
        vm.prank(operator);
        vm.expectRevert(ClaimDeposit.TransferFailed.selector);
        factory.refund(wallet, claimId, address(bad));
    }

    function test_ATokenThatReturnsNothingStillMoves() public {
        SilentToken silent = new SilentToken();
        silent.mint(factory.depositAddress(wallet, claimId), 9e18);
        vm.prank(operator);
        factory.refund(wallet, claimId, address(silent));
        assertEq(silent.balanceOf(wallet), 9e18);
    }

    function test_TheOwnerNamesTheOperatorAndTheOwner() public {
        address next = makeAddr("next operator");
        vm.prank(stranger);
        vm.expectRevert(ClaimDepositFactory.NotOwner.selector);
        factory.setOperator(next);
        vm.prank(owner);
        factory.setOperator(next);
        assertEq(factory.operator(), next);
        vm.prank(owner);
        vm.expectRevert(ClaimDepositFactory.ZeroAddress.selector);
        factory.setOperator(address(0));
        vm.prank(owner);
        factory.setOwner(stranger);
        assertEq(factory.owner(), stranger);
        vm.prank(owner);
        vm.expectRevert(ClaimDepositFactory.NotOwner.selector);
        factory.setOwner(owner);
    }

    function test_RefusesAFactoryWithoutTokenOwnerOrOperator() public {
        vm.expectRevert(ClaimDepositFactory.ZeroAddress.selector);
        new ClaimDepositFactory(address(0), BURN, BURN_AMOUNT, owner, operator);
        vm.expectRevert(ClaimDepositFactory.ZeroAddress.selector);
        new ClaimDepositFactory(address(thkr), BURN, BURN_AMOUNT, address(0), operator);
        vm.expectRevert(ClaimDepositFactory.ZeroAddress.selector);
        new ClaimDepositFactory(address(thkr), BURN, BURN_AMOUNT, owner, address(0));
    }

    /// Whatever reaches a deposit is either burned, up to the amount, or back at the wallet.
    function testFuzz_SettleKeepsEveryToken(uint256 amount) public {
        amount = bound(amount, 0, 1e9 * 1e18);
        sendToDeposit(wallet, amount);
        vm.prank(operator);
        (uint256 burned, uint256 returned) = factory.settle(wallet, claimId);
        assertEq(burned, amount < BURN_AMOUNT ? amount : BURN_AMOUNT);
        assertEq(burned + returned, amount);
        assertEq(thkr.balanceOf(BURN), burned);
        assertEq(thkr.balanceOf(wallet), returned);
    }
}
