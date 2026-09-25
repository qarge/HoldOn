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

## HO-10, HO-05, HO-07 fixed (low, medium, low)

The running-apps picker skips processes that cannot be matched. The README's privacy
paragraph now says exactly what the tap does with a guarded shortcut, names the one
diagnostic log line, and adds the secure-input limit; the build section documents again that
Accessibility is keyed to the code signature. A CHANGELOG was added, covering everything
unreleased since 1.0.0.

Remaining: verification pass and the report.

## HO-11 fixed (low), found during verification

"Only these apps" with an empty list guards nothing, but the settings header reported a green
"Holding ⌘Q in 0 apps". It now shows an amber "Nothing is guarded yet" and says what to do.
Verified on screen against the owner's live settings, which are in exactly that state.

## Verification

Fresh run: release and debug builds warning-free, 11 tests pass, universal binary, signature
valid under `--deep --strict`, no entitlements, no networking linked, one diagnostic log call
in the sources. Red-green checked: removing the clamp fails 6 tests, removing the ASCII
fallback fails 2, restoring makes all 11 pass. Live: a quick ⌘Q tap is held, a 1.4 s hold
quits, three taps in a row leave the app alone. The installed app is byte-identical to the
audited build. Nothing pushed; origin/main is still at the baseline commit.

## A review of the audit's own diff, and seven more fixes

`/code-review pre-audit-baseline...HEAD` found that three of the fixes were incomplete or
wrong. Each was checked before being accepted, and the two most serious were confirmed by
experiment.

- **HO-13, critical.** A hold pending when the tap went quiet was never called off. The timer
  lives on the main run loop, so it fired and replayed ⌘Q for a key already released: the
  guard causing the quit it exists to prevent. Both re-enable paths now forget the press.
- **HO-14, high.** Those same paths left `didFire` stale, so the first ⌘Q after an outage
  could vanish. Same fix.
- **HO-15, medium.** Swift does not re-enter `didSet` for an assignment made inside it, so
  the clamped hold time was never written back. Confirmed with a standalone probe printing
  `value in memory: 3.0, values persisted: []`. The safe value is always stored now, and a
  bad value already on disk is repaired at launch: verified live, a string became 1.0 and
  3600 became 3.0 in the plist.
- **HO-16, medium.** HO-03 had moved the filesystem work, not removed it. A target now
  carries the path as given, which needs no lookup, and gains its resolved form from a
  background task. One `resolvingSymlinksInPath` is left in the sources and it is inside that
  task.
- **HO-17, medium.** `isHealthy` was never read. The tick now publishes it: a stalled tap
  turns the menu bar icon into a warning triangle and the settings header says so.
- **HO-18, low.** `HoldTime.min`/`max` shadowed `Swift.min`/`max`; `Store.minDelay`/`maxDelay`
  forwarded constants for one caller; the picker built a `Target` only to throw it away; a
  test relied on an unsupported `NSRunningApplication()`.

## Session limit hit, resumed 2026-09-25

The previous session stopped during the second `/code-review`, which is a read-only step, so
nothing was left half-written: the working tree was clean at `e26774c`, 18 commits on
`audit/opus-5.5`, and nothing was pushed. No rollback was needed.

State on resuming, all verified fresh: release and debug builds warning-free, 11 tests pass,
universal binary, signature valid under `--deep --strict`, and the installed app holds a
quick ⌘Q and quits on a 1.4 s hold. The owner's settings were put back exactly as they were
after each live test: scope `only`, delay 1.0.

Remaining: the second review pass over `pre-audit-baseline...HEAD`, then the report.

## A second review, and more fixes

The second `/code-review` pass found that HO-13 was still open and that HO-12's fix had
created a worse case. Each finding was worked through before being accepted.

- **HO-19, critical.** `fire()` never checked that the tap was still alive. HO-13 only called
  a pending hold off from the disable event, which the silent case does not send, and from the
  5 s tick, which a hold of at most 3 s always beats. So the silent death of a tap still ended
  in a replayed ⌘Q for a key long released. `fire()` now refuses to replay through a tap that
  is not alive.
- **HO-20, high.** HO-12's kept ledger let auto-repeat key-downs through while still eating
  the key-up. A key-down that goes through now settles the debt; the bookkeeping moved into
  `PressLedger` with three tests, red-green checked.
- **HO-21, high.** Forgetting a press assumed ⌘ was up, which disabled the release-⌘ escape
  hatch after any outage. The modifier state is read from the hardware now.
- **HO-22, medium.** `ensureRunning()` folds start, revive and health into one call, and the
  health flag publishes only on a change instead of every five seconds.
- **HO-23, HO-24, HO-25, low.** One gate for what can become a target, a grammatical status
  line, and the audit's own stale claims corrected.

Live after all of it: quick tap held, releasing ⌘ first cancels, a 1.4 s hold quits. 14 tests
pass. The owner's settings are back to scope `only`, delay 1.0.

## A third review, and ten more fixes

The third `/code-review` pass caught two of the second round's fixes going wrong in their own
way, which is why the code changed again rather than the documents.

- **HO-26, high.** The pending hold's key-up was held back even when its key-down had gone
  through, so adding ⇧ mid-hold left the app with a key it thought was still down.
- **HO-27, high.** Keeping the ledger across a tap outage charged an old debt to some later
  unrelated key-up. Debts are dropped on an outage; an unexpected release is the lesser harm.
- **HO-28, high.** HO-19's check ran up to 250 ms before the replay was posted. It is now made
  inside the block that posts.
- **HO-29, HO-34, medium and low.** An app with no bundle identifier falls back to the
  executable inside it instead of becoming an entry that matches nothing, and several files
  picked at once are added in one assignment.
- **HO-30, medium.** The running-apps list offers only rows it can actually add.
- **HO-31, HO-32, HO-33, low.** Room for the stalled-tap line, one log line per failure
  instead of one every five seconds, and no work on the paused tick.
- **HO-35, low.** The README's linkage claim, the changelog's test count, and a test-only
  property on the ledger.

Two of the review's points were deliberately not taken, with reasons written into the audit:
cancelling a hold on a tap timeout, and not resolving the running process's path again.

Fresh verification: builds warning-free, 14 tests pass, universal, signature valid.

## Final verification, 2026-09-25

Fresh, on the build now installed: release and debug builds warning-free, 14 tests pass,
universal binary, signature valid under `--deep --strict`, no entitlements, no networking
linked directly, one diagnostic log call in the sources.

Live on the installed app: a quick ⌘Q tap is held, three taps in a row leave the app alone,
releasing ⌘ first calls the hold off, a 1.4 s hold quits. With the ⌘W guard on, a quick ⌘W
leaves the window open and a held ⌘W closes it. The owner's settings were put back exactly:
scope `only`, delay 1.0, ⌘W guard off.

Nothing pushed. `origin/main` is still the baseline commit; the work is 34 commits on
`audit/opus-5.5` with the tag `pre-audit-baseline` marking where it started.
