# Audit progress, 2026-09-24

Branch `audit/opus-5.5`, baseline tag `pre-audit-baseline`. Nothing pushed.

- Audit written to `docs/audit/AUDIT-2026-09-24.md`: 10 findings, 1 critical, 1 high,
  4 medium, 4 low, plus 5 questions for the owner.
- Baseline recorded: release and debug builds warn-free, 3 tests pass, universal binary,
  hardened runtime, no entitlements.
- Privacy promises checked against both the sources and the built binary. No network code
  or linkage, no keystroke logging, only the five documented preference keys are written.
- Next: fix in order, one commit per finding, `make` and `make test` after each.
