# Changelog

All notable changes to HoldOn. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

- A hold never replays through a tap that is no longer alive, so a tap that dies quietly
  during a press can no longer quit the app for a key you already released (HO-19).
- Auto-repeat after releasing ⌘ leaves the app with balanced presses and releases (HO-20),
  and releasing ⌘ still calls a hold off after the tap has been interrupted (HO-21).
- A hold that was pending when macOS switched the tap off is called off instead of firing
  later and quitting the app for a key you had already released (HO-13). The same paths clear
  the press state, so the next ⌘Q is not swallowed silently (HO-14).
- The clamped hold time is written back to preferences, and an unusable value already stored
  is repaired at launch (HO-15).
- A stalled tap now shows as a warning triangle in the menu bar and is named in the settings
  header, instead of looking exactly like a healthy one (HO-17).
- A key held back while ⌘ was down still gets its key-up, even when ⌘ is released first
  (HO-12).
- The hold time read from preferences is clamped to 0.3–3.0 seconds. An unusable value, such
  as the 0 a wrongly typed entry reads back as, used to end the hold at once and wave ⌘Q
  straight through; a large one swallowed the shortcut for minutes (HO-01).
- A tap the system switches off without sending a disable event is now noticed on the app's
  five second tick and switched back on, or rebuilt if it refuses. Protection could otherwise
  be off while the menu bar still showed the filled hand (HO-02).
- Only the key-ups whose key-downs were actually held back are swallowed. After a hold fired,
  the key-up of any guarded key used to be dropped, which could leave an app believing ⌘W was
  still held (HO-04).
- Pausing and resuming protection clears the press state, so a stale hold can no longer
  swallow the next ⌘Q until ⌘ is released once (HO-06).
- The settings header no longer claims a green "Holding ⌘Q in 0 apps" when "Only these apps"
  is picked with an empty list, which guards nothing; it says so instead (HO-11).
- The running-apps picker no longer offers a process that has neither a bundle identifier nor
  an executable path, which would have added a list entry that can never match (HO-10).

### Changed

- The guard switch moved to the menu bar as a single Enable/Disable item, and the settings
  window lost its duplicate toggle.
- Settings open on the first launch, and on any later launch or Launchpad click. A launch at
  login stays silent. The first launch also points a popover at the menu bar icon.
- The settings window was redesigned: a status header, the hold-time slider, scope rows with
  icons, and the app list inline.
- The status icon is a filled hand while the guard runs and an outlined one while it is off,
  two variants of one symbol, so it never shifts.
- Nothing on the keystroke path touches the filesystem any more: a target matches on the path
  as given, and its symlink-free form is worked out in the background. Matching a two-entry
  list went from 26 µs with filesystem lookups to 0.14 µs with none (HO-03, HO-16).
- A layout that reports a character outside ASCII now falls back to the US key positions, so
  an unusual layout still guards ⌘Q.
- The README states the privacy promises exactly, including what the tap does with a guarded
  shortcut, the single diagnostic log line, and that secure input hides keystrokes from every
  tap (HO-05). It also documents again that Accessibility access is keyed to the code
  signature, so ad-hoc builds need re-approval after each install (HO-07).

### Added

- `docs/audit/AUDIT-2026-09-24.md`, a full security and quality audit with measurements.
- Tests for the hold-time clamp, the shortcut decision, the fallback to key positions, the
  modifier test, path resolution and the key-stroke ledger: 14 in total, up from 3.
- `make dev` builds for the host architecture only, for a faster local loop.
- `Package.swift`, so editors resolve the sources through SourceKit-LSP.

## [1.0.0] — 2026-09-16

First public release. Hold-to-quit for ⌘Q with an adjustable delay, an optional ⌘W guard,
per-app scope with support for programs that ship no bundle, a menu bar item and a settings
window. Universal build for Apple silicon and Intel, macOS 14 or later.

[1.0.0]: https://github.com/qarge/HoldOn/releases/tag/v1.0.0
