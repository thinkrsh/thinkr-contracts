# Thinkr contracts

The contracts behind the claim of holder vouchers by transfer on Robinhood Chain (chain 4663), and
behind the top-ups in USDG of the chat app. A wallet that holds THKR earns holder vouchers each day.
A wallet app that cannot sign messages claims them with a transfer of THKR instead of a signature.
This repository holds the contracts that keep that THKR, and the USDG of a top-up on its way.

## How a claim by transfer works

1. The dashboard asks the issuer of Thinkr for a claim. The issuer draws a random claim id and
   asks the factory for the deposit address of that claim.
2. The wallet sends at least `burnAmount` of THKR from itself to the deposit address. Only the
   wallet can send from itself, so the transfer proves the wallet as a signature does.
3. The issuer reads the transfer on the chain. Its claim wallet, the operator of the factory,
   calls `settle`. The factory deploys the deposit at its address, which burns `burnAmount` and
   sends the rest back to the wallet.
4. The issuer then fills the claim ticket of the chat of the user with blind holder vouchers,
   which it cannot link to the wallet when they are spent.

When a claim does not go through, the operator calls `refund`, and all of the THKR goes back to
the wallet. That covers a transfer under `burnAmount`, a transfer after the time of the claim, and
THKR that reaches a deposit after its claim settled.

## What the contracts allow

THKR at a deposit address can leave it two ways only:

- `settle(wallet, claimId)`, by the operator, once per deposit: at most `burnAmount` goes to the
  burn address, and the rest goes to the wallet.
- `refund(wallet, claimId, asset)`, by the operator or by the wallet itself, at any time: all of
  `asset` goes to the wallet.

The wallet is part of the address of its deposit, so a deposit pays out to that wallet alone.
Neither the operator nor the owner can send THKR anywhere else. The owner can name another
operator or another owner, and nothing more. The worst that a stolen operator key can do is burn
`burnAmount` of each deposit that never settled.

## How a top-up in USDG uses them

Since 31 Oct 2026, a top-up in USDG in the chat app pays to a deposit of the same factory, whose
wallet is the wallet of Thinkr that receives top-ups, `0x9EA1C6e2032a6F4Af2b358b64467A823c3e39eE2`.

1. The issuer draws a random id and asks the factory for the deposit address of that wallet and id.
2. Any wallet sends USDG to that address, with a plain transfer. The issuer reads the transfer on
   the chain, and the credit joins a ticket of the chat of the user as blind notes.
3. The claim wallet calls `refund(wallet, claimId, USDG)`, and the deposit sends all of its USDG to
   the wallet of top-ups.

The wallet is part of the address of its deposit, so what reaches that address can go nowhere else.

## The contracts

| Contract | File | Job |
|---|---|---|
| `ClaimDepositFactory` | `src/ClaimDepositFactory.sol` | Names deposit addresses, deploys each deposit when it is first used, and settles or refunds it. |
| `ClaimDeposit` | `src/ClaimDeposit.sol` | Holds the tokens of one claim. Only the factory can release them, to the burn address or to the wallet. |

## Test

The tests use forge-std, a git submodule in `lib/`. Clone with `--recurse-submodules`, or fetch it
in a clone:

```sh
git submodule update --init
```

Run the unit tests:

```sh
forge test
```

Run the tests against the real THKR on a fork of Robinhood Chain:

```sh
FORK_RPC_URL=https://rpc.mainnet.chain.robinhood.com forge test --match-contract Fork
```

## Deploy

The key of `DEPLOYER_KEY` pays the gas of the deploy. Thinkr deployed the factory from its claim
wallet. Keep the key in a file outside the repository, and never in `.env`. The other values come
from the environment, as `.env.example` lists them:

```sh
DEPLOYER_KEY="$(cat /path/to/deployer-key.txt)" \
TOKEN=0xbd095fb55F55d59F1e16115dabe3b81D5ce035Dc \
BURN_ADDRESS=0x000000000000000000000000000000000000dEaD \
BURN_AMOUNT=100000000000000000000 \
OWNER=<owner address> \
OPERATOR=<claim wallet address> \
forge script script/Deploy.s.sol --rpc-url https://rpc.mainnet.chain.robinhood.com --broadcast
```

`BURN_AMOUNT` is in the smallest unit of THKR (18 decimals). It must match the burn of one claim in
the issuer of Thinkr, `HOLD.transferClaim.burnThkr` of
[thinkrsh/thinkr-issuer](https://github.com/thinkrsh/thinkr-issuer). The issuer then takes the
address of the factory as `CLAIM_FACTORY`.

## Deployed

| Contract | Address on Robinhood Chain (4663) | Burn of one claim, at most |
|---|---|---|
| `ClaimDepositFactory` | `0x92A3350d512CE175A3a2623958b7420F60C7aD72` | 100 THKR |
| `ClaimDepositFactory`, retired | `0xa638F6bB5314e9F3Be61A67E49Bea2732c11cd09` | 1,000 THKR |

The factory went live on 31 Oct 2026 in block 102269404, in transaction
`0xf1b161b5377206c3ff6ccfdf188216244cef17b8bb8d739a8b452721643ea147`. Its owner is the THKR treasury
of Thinkr, `0x55180D0E6ebaA620Bd4533ac0F13324802B972cA`. Its operator is the claim wallet,
`0x22e5Ab4a1505fB1381aE31E2385B54efC355bdFF`.

The retired factory went live on 27 Oct 2026 in block 99292118, in transaction
`0x9911573c5d772d4858cf24637c7c7a73d3985abde01a41efbf98a51a73c55827`, with the same owner and
operator. It takes no new claim, and its operator still settles and refunds the deposits of its
claims.

Sourcify holds the source of both factories as an exact match of both the creation code and the
runtime code:
[0x92A3350d512CE175A3a2623958b7420F60C7aD72](https://repo.sourcify.dev/4663/0x92A3350d512CE175A3a2623958b7420F60C7aD72)
and [0xa638F6bB5314e9F3Be61A67E49Bea2732c11cd09](https://repo.sourcify.dev/4663/0xa638F6bB5314e9F3Be61A67E49Bea2732c11cd09).
To verify one again from a clone:

```sh
forge verify-contract 0x92A3350d512CE175A3a2623958b7420F60C7aD72 \
  src/ClaimDepositFactory.sol:ClaimDepositFactory --chain 4663 --verifier sourcify
```

## License

Apache License 2.0.
