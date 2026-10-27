// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// The calls of an ERC-20 token that a deposit makes.
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// The deposit address of one claim by transfer of holder vouchers (27 Oct 2026). Tokens reach it
/// before it exists: its factory names the address first and deploys it here when the claim
/// settles. Only the factory can move what it holds, and only to the burn address of the factory or
/// back to the wallet of the claim, which is part of the address of this deposit.
contract ClaimDeposit {
    /// The factory that deployed this deposit, the only caller of `release`.
    address public immutable factory;
    /// The wallet of the claim: everything that is not burned goes back to it.
    address public immutable wallet;

    error NotFactory();
    error TransferFailed();

    constructor(address wallet_) {
        factory = msg.sender;
        wallet = wallet_;
    }

    /// Sends up to `burnAmount` of `token` to `burnAddress`, and the rest of this deposit's balance of
    /// `token` back to the wallet of the claim. Returns what each side took.
    function release(address token, address burnAddress, uint256 burnAmount)
        external
        returns (uint256 burned, uint256 returned)
    {
        if (msg.sender != factory) revert NotFactory();
        uint256 balance = IERC20(token).balanceOf(address(this));
        burned = burnAmount < balance ? burnAmount : balance;
        returned = balance - burned;
        if (burned > 0) send(token, burnAddress, burned);
        if (returned > 0) send(token, wallet, returned);
    }

    /// A transfer of `token` that fails loudly, for tokens that return false as for those that revert.
    function send(address token, address to, uint256 amount) private {
        (bool ok, bytes memory data) = token.call(abi.encodeCall(IERC20.transfer, (to, amount)));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
}
