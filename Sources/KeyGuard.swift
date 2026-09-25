//
//  KeyGuard.swift
//  HoldOn — the event tap that swallows ⌘Q / ⌘W and replays it after the hold.
//
//  Copyright (C) 2026 qarge
//  Portions Copyright (c) 2025 dudukee, from SlowQuit, under the MIT License (see NOTICE)
//  SPDX-License-Identifier: GPL-3.0-or-later AND MIT
//

import AppKit
import Carbon.HIToolbox

enum Guarded {
    case quit, close

    var key: String { self == .quit ? "q" : "w" }
    var label: String { self == .quit ? "⌘Q" : "⌘W" }
    var prompt: String {
        self == .quit
            ? NSLocalizedString("Hold %@ to quit", comment: "")
            : NSLocalizedString("Hold %@ to close", comment: "")
    }
}

/// Which key-downs this tap held back. The app must never see half a stroke: a key-up is held
/// back only while its own key-down was, and a key-down that goes through settles the debt,
/// because from then on the app has seen the press and is owed the release.
struct PressLedger {
    private var owed: Set<CGKeyCode> = []

    var isEmpty: Bool { owed.isEmpty }

    mutating func heldBack(_ code: CGKeyCode) { owed.insert(code) }

    mutating func letThrough(_ code: CGKeyCode) { owed.remove(code) }

    /// True when this key-up has to be held back too. Either way the debt is settled.
    mutating func owesRelease(of code: CGKeyCode) -> Bool { owed.remove(code) != nil }

    mutating func forgetAll() { owed.removeAll() }
}

@MainActor
final class KeyGuard {
    /// Stamped on the keystroke we replay so the tap ignores its own event.
    private static let marker: Int64 = 0x484F4C_444F4E

    private let store = Store.shared
    private let overlay = Overlay()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var pending: (action: Guarded, keyCode: CGKeyCode, app: NSRunningApplication)?
    private var didFire = false
    private var cmdDown = false
    private var ledger = PressLedger()

    /// The tap exists and the system still has it switched on. A tap can go quiet without
    /// sending a disable event, and then nothing is guarded while the menu bar still says
    /// everything is fine.
    var isHealthy: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Starts the tap if it is not up, brings it back if the system switched it off without
    /// saying so, and reports whether the keyboard is actually being watched. Callers should
    /// not have to know the order of any of that.
    @discardableResult
    func ensureRunning() -> Bool {
        start()                     // a no-op while it already runs
        guard let tap else { return false }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            forgetPress()           // the key-ups during the outage were never seen here
            if !CGEvent.tapIsEnabled(tap: tap) {
                stop()              // it refused to come back: build a new one
                start()
            }
        }
        return isHealthy
    }

    /// Forgets the press that was in flight. Whenever the tap has been out of the loop, the
    /// key-ups that happened meanwhile were never delivered: a pending hold would otherwise
    /// fire for a key the user released long ago, and a stale `didFire` would swallow the
    /// next ⌘Q with nothing to show for it.
    private func forgetPress() {
        cancel()
        didFire = false
        // ⌘ may well still be held. Assuming it is up would break the escape hatch: releasing
        // it has to call a hold off, and that only works while this mirrors the hardware.
        cmdDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
        // The ledger survives: a key held back still owes its key-up.
    }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let guardian = Unmanaged<KeyGuard>.fromOpaque(refcon).takeUnretainedValue()
                // The tap is attached to the main run loop, so this callback is always on main.
                return MainActor.assumeIsolated { guardian.handle(type, event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("HoldOn: could not create the event tap (accessibility permission?)")
            return
        }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        overlay.prewarm()
    }

    func stop() {
        forgetPress()
        ledger.forgetAll()      // with no tap, the key-ups it is waiting for will never arrive
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    // MARK: - Tap

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Self-heal: the system disables a slow tap instead of removing it.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            forgetPress()
            return pass

        case .flagsChanged:
            let down = event.flags.contains(.maskCommand)
            if cmdDown && !down {
                cancel()
                didFire = false
                // The ledger is deliberately kept: a key held back while ⌘ was down still owes
                // the app its key-up, even when ⌘ comes up first. An auto-repeat key-down that
                // now goes through settles that debt on its own.
            }
            cmdDown = down
            return pass

        case .keyDown:
            return keyDown(event, pass)

        case .keyUp:
            guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return pass }
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if let pending, pending.keyCode == code {
                cancel()          // released early, the action is called off
                _ = ledger.owesRelease(of: code)
                return nil
            }
            // Key-up of a press this tap held back; anything it let through passes through.
            return ledger.owesRelease(of: code) ? nil : pass

        default:
            return pass
        }
    }

    private func keyDown(_ event: CGEvent, _ pass: Unmanaged<CGEvent>) -> Unmanaged<CGEvent>? {
        // Our own replay: it is the app's press to keep, and none of the ledger's business.
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return pass }

        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        func letThrough() -> Unmanaged<CGEvent> {
            ledger.letThrough(code)
            return pass
        }

        guard Self.isPlainCommand(event.flags), let action = guarded(event) else { return letThrough() }

        if action == .close && !store.guardClose { return letThrough() }

        let front = NSWorkspace.shared.frontmostApplication
        guard store.applies(to: front), let app = front else { return letThrough() }

        // One action per ⌘ press: swallow auto-repeat and re-presses until ⌘ is released.
        guard !didFire, pending == nil else {
            ledger.heldBack(code)
            return nil
        }

        ledger.heldBack(code)
        pending = (action, code, app)
        overlay.show(
            title: app.localizedName ?? "",
            subtitle: String(format: action.prompt, action.label),
            icon: app.icon,
            duration: store.delay
        )
        // .common so the hold still completes while a menu or a resize owns the run loop.
        let tick = Timer(timeInterval: store.delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        return nil
    }

    private func cancel() {
        timer?.invalidate()
        timer = nil
        pending = nil
        overlay.hide()
    }

    private func fire() {
        guard let (action, keyCode, app) = pending else { return }
        cancel()
        didFire = true

        // The timer lives on the main run loop, not on the tap. If the tap has gone quiet in
        // the meantime, the key-up was delivered to the app and never seen here: the user let
        // go long ago, and replaying the shortcut now would quit the app this exists to guard.
        guard isHealthy else { return }
        guard !app.isTerminated else { return }
        // The keystroke is replayed to whatever is frontmost, so the target has to be frontmost.
        let moved = NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier
        if moved {
            // ⌘W belongs to a window of the app that was in front; ⌘Q can pull it back.
            guard action == .quit else { return }
            app.activate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (moved ? 0.25 : 0.05)) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            let source = CGEventSource(stateID: .hidSystemState)
            source?.userData = Self.marker
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Keyboard layout

    /// Which guarded shortcut this key is. Uses the ASCII-capable layout, the same one AppKit
    /// resolves menu shortcuts with, so ⌘Q stays guarded while typing in Russian, Greek, …
    private func guarded(_ event: CGEvent) -> Guarded? {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        return Self.action(character: character(for: code), keyCode: code)
    }

    /// The decision itself, without a keyboard: what the layout types decides, and a layout
    /// that reports nothing or something outside ASCII falls back to the US key positions,
    /// which is where ⌘Q and ⌘W sit on every Latin layout.
    nonisolated static func action(character: String?, keyCode: Int64) -> Guarded? {
        var typed = character?.lowercased()
        if typed == nil || typed?.allSatisfy(\.isASCII) == false { typed = fallback(keyCode) }
        switch typed {
        case Guarded.quit.key: return .quit
        case Guarded.close.key: return .close
        default: return nil
        }
    }

    /// ⌘ and nothing else. ⇧⌘Q or ⌥⌘W are other shortcuts and are none of our business.
    nonisolated static func isPlainCommand(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand)
            && !flags.contains(.maskShift)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskControl)
    }

    nonisolated static func fallback(_ code: Int64) -> String? {
        switch code {
        case 12: return "q"
        case 13: return "w"
        default: return nil
        }
    }

    private func character(for code: Int64) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = unsafeBitCast(pointer, to: CFData.self)
        guard let layout = CFDataGetBytePtr(data) else { return nil }

        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
