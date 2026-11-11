# H-MOR-04 — BuildersV4 subnet-name squatting (Morpheus Bug Bounty PoC)

**DRAFT — prepared for publication. NOT YET SUBMITTED. Do not treat this repo as a submitted report.**

An unprivileged address registers an unregistered builder-style subnet name on
BuildersV4 (Base, `0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9`), becomes
`admin = claimAdmin` of that subnet, and then `claim()`s **100% of the subnet's
`pendingRewards`** — rewards generated entirely by third-party depositors, while
the attacker deposited 0 MOR.

## Run

```bash
forge test -vvvv
```

Expected result: **6 tests passed, 0 failed.**

- Foundry (tested with v1.9.0), solc 0.8.26, no external dependencies (minimal
  cheatcode interface, no forge-std).
- The tests run against a **Base mainnet fork pinned at block 56,040,152**.
  Fork-only: no live transactions, no interaction with live contracts outside
  fork simulation (programme §6).
- The default RPC is a public Base archive endpoint
  (`https://base-mainnet.public.blastapi.io`). To use another public Base
  archive endpoint, set `BASE_RPC_URL` (e.g. `BASE_RPC_URL=https://base.drpc.org
  forge test -vvvv`). No API key is required.

## What the PoC proves

| Test | Result |
|---|---|
| Main squat end-to-end (register → 2 × 100,000 MOR third-party deposits → +30 days → claim) | Attacker receives exactly `pendingRewards − claimFee` = **4,349.356514 MOR**; `pendingRewards` zeroed; treasury outflow = gross pending |
| Negative control (stranger + actual depositor claim attempts) | Both revert; pending untouched; squatted admin then claims in full |
| Baseline control (same flow, subnet owned by a legitimate registrant) | Attacker receives exactly **0** |
| claimAdmin-only variation, second name (attacker is claimAdmin but not admin) | Full payout again: **525.336081 MOR** over 7 days on 100,000 MOR of deposits |
| Duplicate registration of the squatted name | Reverts — uniqueness protects the *first* registrant (the squatter) |

- Creation fee and claim fee read on-fork at the pin: **0**.
- Capture fraction: **100% of a subnet's `pendingRewards` per claim**, repeatable
  every accrual period. Demonstrated extraction: 4,349.356514 MOR ≈ **$3,435.99**
  (MOR ≈ $0.79) per 200,000 MOR staked per 30 days (≈ 144.98 MOR/day at the
  fork's parameters), bounded by the Builders treasury balance.

## What the PoC does NOT prove

- **Live amount at risk today is $0.** On-chain recon (Base, 2026-11-12) found
  192 registered subnets and no unregistered name currently holding rewards —
  the squat surface is real, marketed builder names that remain unregistered
  (e.g. "Venice AI", "Mordiem"), not funds already at risk. The fork numbers
  above are demonstrated loss against deployed bytecode on a fork, **not**
  funds currently at risk.
- Depositors in the PoC are simulated (fresh EOAs funded via storage-slot deal,
  the way forge-std's ERC20 deal works). Real-world loss additionally requires
  the squatted name to be one real depositors actually use.
- State after the pin block (56,040,152) is not covered; the claim fee is
  owner-settable and was read at the pin only.

## Severity claimed

**Low** — quantified demonstrated loss below $10,000 with a working PoC
(programme §3: Low = $500–$2,500). The 100% capture fraction is the
protocol-level fact; the absolute amount scales with the squatted subnet's
third-party deposits, which were simulated. Claiming High/Critical on the
demonstrated numbers would be an overclaim.
