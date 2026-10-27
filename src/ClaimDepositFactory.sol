// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {ClaimDeposit} from "./ClaimDeposit.sol";

/// The deposit addresses of the claims by transfer of Thinkr's holder vouchers (27 Oct 2026).
///
/// A wallet in an app that signs no message proves that it holds its THKR with a transfer: it sends
/// THKR from itself to the deposit address of its claim, which this factory names before anything
/// is sent. What reaches a deposit can leave it two ways only. When the claim goes through, the
/// operator settles it: at most `burnAmount` goes to the burn address, and the rest goes back to the
/// wallet. A claim settles once, so at most `burnAmount` of it is ever burned. When it does not go
/// through, the operator, or the wallet itself, refunds it: all of it goes back to the wallet.
/// Nobody, Thinkr included, can send it anywhere else.
contract ClaimDepositFactory {
    /// THKR, the token that a claim burns.
    address public immutable token;
    /// Where the THKR of a claim that went through goes.
    address public immutable burnAddress;
    /// The most THKR that one claim burns, in the smallest unit of THKR.
    uint256 public immutable burnAmount;
    /// May name another operator, or another owner.
    address public owner;
    /// Settles and refunds the claims: the key of the issuer of Thinkr.
    address public operator;
    /// The deposits whose claim settled: each burns once.
    mapping(address deposit => bool) public settled;

    event Settled(
        address indexed wallet, bytes32 indexed claimId, uint256 burned, uint256 returned
    );
    event Refunded(
        address indexed wallet, bytes32 indexed claimId, address indexed asset, uint256 amount
    );
    event OperatorChanged(address operator);
    event OwnerChanged(address owner);

    error NotOwner();
    error NotOperator();
    error NotAllowed();
    error AlreadySettled();
    error ZeroAddress();

    constructor(
        address token_,
        address burnAddress_,
        uint256 burnAmount_,
        address owner_,
        address operator_
    ) {
        if (token_ == address(0) || owner_ == address(0) || operator_ == address(0)) {
            revert ZeroAddress();
        }
        token = token_;
        burnAddress = burnAddress_;
        burnAmount = burnAmount_;
        owner = owner_;
        operator = operator_;
    }

    /// The deposit address of the claim `claimId` of `wallet`, whether it is deployed yet or not.
    function depositAddress(address wallet, bytes32 claimId) public view returns (address) {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(ClaimDeposit).creationCode, abi.encode(wallet)));
        bytes32 hash =
            keccak256(abi.encodePacked(bytes1(0xff), address(this), claimId, initCodeHash));
        return address(uint160(uint256(hash)));
    }

    /// The claim went through: burns up to `burnAmount` of the THKR of its deposit and sends the
    /// rest back to the wallet. A deposit settles once; THKR that reaches it later can only go back.
    function settle(address wallet, bytes32 claimId)
        external
        returns (uint256 burned, uint256 returned)
    {
        if (msg.sender != operator) revert NotOperator();
        ClaimDeposit deposit = depositOf(wallet, claimId);
        if (settled[address(deposit)]) revert AlreadySettled();
        settled[address(deposit)] = true;
        (burned, returned) = deposit.release(token, burnAddress, burnAmount);
        emit Settled(wallet, claimId, burned, returned);
    }

    /// Sends all of `asset` in a deposit back to its wallet: the operator does so for a claim that
    /// did not go through, and the wallet may do so itself at any time.
    function refund(address wallet, bytes32 claimId, address asset)
        external
        returns (uint256 amount)
    {
        if (msg.sender != operator && msg.sender != wallet) revert NotAllowed();
        (, amount) = depositOf(wallet, claimId).release(asset, burnAddress, 0);
        emit Refunded(wallet, claimId, asset, amount);
    }

    function setOperator(address operator_) external {
        if (msg.sender != owner) revert NotOwner();
        if (operator_ == address(0)) revert ZeroAddress();
        operator = operator_;
        emit OperatorChanged(operator_);
    }

    function setOwner(address owner_) external {
        if (msg.sender != owner) revert NotOwner();
        if (owner_ == address(0)) revert ZeroAddress();
        owner = owner_;
        emit OwnerChanged(owner_);
    }

    /// The deposit of a claim, deployed at its address the first time it is used.
    function depositOf(address wallet, bytes32 claimId) private returns (ClaimDeposit) {
        address at = depositAddress(wallet, claimId);
        if (at.code.length > 0) return ClaimDeposit(at);
        return new ClaimDeposit{salt: claimId}(wallet);
    }
}
