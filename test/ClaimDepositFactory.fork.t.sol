// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../src/ClaimDeposit.sol";
import {ClaimDepositFactory} from "../src/ClaimDepositFactory.sol";

/// The factory against the real THKR of Robinhood Chain, on a fork: a plain transfer of THKR to a
/// deposit address arrives whole, settles, and refunds. Runs only with FORK_RPC_URL set, such as
/// FORK_RPC_URL=https://rpc.mainnet.chain.robinhood.com forge test --match-contract Fork
contract ClaimDepositFactoryForkTest is Test {
    address constant THKR = 0xbd095fb55F55d59F1e16115dabe3b81D5ce035Dc;
    address constant BURN = 0x000000000000000000000000000000000000dEaD;
    /// The PoolManager of Uniswap v4 on the chain, which holds the THKR of its pool: a sender here.
    address constant HOLDER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    uint256 constant BURN_AMOUNT = 1_000e18;
    address wallet = makeAddr("wallet");
    ClaimDepositFactory factory;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC_URL", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc);
        factory = new ClaimDepositFactory(THKR, BURN, BURN_AMOUNT, address(this), address(this));
        vm.prank(HOLDER);
        IERC20(THKR).transfer(wallet, 10_000e18);
    }

    function test_RealTHKRArrivesWholeAndSettles() public {
        bytes32 claimId = keccak256("fork claim");
        address deposit = factory.depositAddress(wallet, claimId);
        uint256 burnedBefore = IERC20(THKR).balanceOf(BURN);
        vm.prank(wallet);
        IERC20(THKR).transfer(deposit, 1_250e18);
        assertEq(IERC20(THKR).balanceOf(deposit), 1_250e18);
        (uint256 burned, uint256 returned) = factory.settle(wallet, claimId);
        assertEq(burned, BURN_AMOUNT);
        assertEq(returned, 250e18);
        assertEq(IERC20(THKR).balanceOf(BURN) - burnedBefore, BURN_AMOUNT);
        assertEq(IERC20(THKR).balanceOf(wallet), 10_000e18 - 1_250e18 + 250e18);
    }

    function test_RealTHKRRefundsWhole() public {
        bytes32 claimId = keccak256("fork refund");
        address deposit = factory.depositAddress(wallet, claimId);
        vm.prank(wallet);
        IERC20(THKR).transfer(deposit, 4_821e18);
        factory.refund(wallet, claimId, THKR);
        assertEq(IERC20(THKR).balanceOf(wallet), 10_000e18);
    }
}
