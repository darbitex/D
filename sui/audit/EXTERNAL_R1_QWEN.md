# External R1 — Qwen3.6

**Auditor:** Qwen3.6
**Round:** R1
**Date:** 2026-04-28
**Verdict:** GREEN

## Findings

- HIGH: none
- MEDIUM: none
- LOW: none (LOW-1 cliff orphan pre-resolved at lines 543-549, verified correct)
- INFO-1: Indexer migration FeeBurned → SPDonated (matches self-audit, Grok, DeepSeek)
- INFO-2: u64 ceiling at ~180 trillion D, practically unreachable (matches consensus)

## Math invariant verification — ALL PASS

- new total_sp formula correctness ✓ (algebraic proof verified)
- reward_index_d denominator strictly keyed ✓ (guarded by table::length check)
- donation residue sp_pool consistency ✓ (no dilution, scales pro-rata via pool_before)
- cliff path no orphan ✓ (route_fee 90% redirect + sp_coll → reserve_coll, both with events)
- V1 invariants preserved ✓ (sp_settle saturation, MIN_P_THRESHOLD, sender-keyed sp_withdraw, product_factor freeze)

## Attack surface

**New surface:**
- donate_to_sp: pure positive externality (no dilution since bypass total_sp). Donor incurs net loss D + 1% fee.
- donate_to_reserve: oracle-gated redemption prevents manipulation. Donor incurs net loss.

**Modified surface:**
- route_fee 10/90 + agnostic: correct routing, consistent events.
- liquidate pool_before math + cliff redirect: invariant preserved, no orphan.

**Additional vectors:**
- **E.** Gas griefing via repeated small donations → No, single PTB call linear gas, Sui metering mitigates.
- **F.** Donation + withdraw manipulate product_factor → No, reset only triggers on total_sp==0 with keyed deposit, donations alone cannot trigger.

## Optional notes

1. Code well-structured, clear comments, consistent error handling. 26/26 test coverage adequate.
2. Suggested: runtime event emission on E_PRICE_UNCERTAIN / E_STALE for off-chain monitoring (optional, defer).
3. SPDonated/ReserveDonated events sufficient as-is; could add timestamp_ms for indexer ordering (optional).
4. Confirm deploy script bundles `coin_registry::finalize_registration` + `destroy_cap` atomically (operational, already in deploy-scripts).
5. Sync external docs/README to V2 WARNING (operational).

## Recommendation

**Proceed to R2 (or skip R2 if all primary R1 GREEN).**

V2 diff narrowly scoped, mathematically sound, V1 invariants maintained. Self-audit correctly identified + resolved single LOW pre-submission. Donation primitives provide positive protocol externalities with no exploitable surface.

**GREEN — ready for production deployment post-sealing.**
