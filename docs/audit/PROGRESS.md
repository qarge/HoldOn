# Audit progress, 2026-09-24

Branch `audit/opus-5.5`, baseline tag `pre-audit-baseline`. Nothing pushed.

- Audit written to `docs/audit/AUDIT-2026-09-24.md`: 10 findings, 1 critical, 1 high,
  4 medium, 4 low, plus 5 questions for the owner.
- Baseline recorded: release and debug builds warn-free, 3 tests pass, universal binary,
  hardened runtime, no entitlements.
- Privacy promises checked against both the sources and the built binary. No network code
  or linkage, no keystroke logging, only the five documented preference keys are written.
- Next: fix in order, one commit per finding, `make` and `make test` after each.

## HO-01 fixed (critical)

The hold time now passes through `HoldTime.clamped` on the way out of preferences and on
every write, so 0, a negative, a NaN or 3600 can no longer reach the timer. The helper lives
outside the main-actor class, which is what makes it testable; three tests cover junk,
out-of-range and in-range values. 6 tests pass, build warning-free.

## HO-02 fixed (high)

`KeyGuard` gained `isHealthy` and `revive()`, and the app's existing 5 s tick now calls
`revive()` whenever protection should be running: a tap the system switched off without
sending a disable event is turned back on, and one that refuses is rebuilt. `isRunning`
is no longer dead (HO-08 closed with it). Build warning-free, 6 tests pass.

## HO-03 fixed (medium)

Target paths are resolved into `ResolvedTarget` when the list changes, and a running app's
executable is resolved at most once per process, warmed when the app comes forward rather
than when a key is pressed. Matching a two-entry list went from 26 µs with filesystem I/O
to 0.14 µs with none. Behaviour is unchanged; a symlink repointed while the app runs is now
picked up on the next list edit or launch rather than instantly. 7 tests pass.

## HO-04 and HO-06 fixed (medium)

The tap now remembers exactly which key codes it held back during the current ⌘ press and
releases the matching key-ups, instead of dropping the key-up of any guarded key once a hold
had fired. `stop()` clears the press state, so a pause and resume, or a permission cycle,
cannot leave a stale `didFire` swallowing the next ⌘Q. 7 tests pass, build warning-free.

## HO-09 fixed (low)

The shortcut decision and the modifier test moved into pure `nonisolated` helpers on
`KeyGuard`, and are now covered by tests: what the layout types decides, a missing layout
falls back to the US key positions, Dvorak's key 12 is correctly not ⌘Q, and only a plain ⌘
counts. The fallback also triggers when a layout reports a character outside ASCII, which
guards against a layout that is not really ASCII-capable. 10 tests pass.
