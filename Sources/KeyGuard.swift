//
//  KeyGuard.swift
//  HoldOn — the event tap that swallows ⌘Q / ⌘W and replays it after the hold.
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

    var isRunning: Bool { tap != nil }

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
        cancel()
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
            return pass

        case .flagsChanged:
            let down = event.flags.contains(.maskCommand)
            if cmdDown && !down {
                cancel()
                didFire = false
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
                return nil
            }
            // Key-up of a press we already swallowed: the app must not see half a stroke.
            if didFire, guarded(event) != nil { return nil }
            return pass

        default:
            return pass
        }
    }

    private func keyDown(_ event: CGEvent, _ pass: Unmanaged<CGEvent>) -> Unmanaged<CGEvent>? {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return pass }

        let flags = event.flags
        guard flags.contains(.maskCommand),
              !flags.contains(.maskShift), !flags.contains(.maskAlternate), !flags.contains(.maskControl),
              let action = guarded(event) else { return pass }

        if action == .close && !store.guardClose { return pass }

        let front = NSWorkspace.shared.frontmostApplication
        guard store.applies(to: front), let app = front else { return pass }

        // One action per ⌘ press: swallow auto-repeat and re-presses until ⌘ is released.
        guard !didFire, pending == nil else { return nil }

        pending = (action, CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)), app)
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
        let typed = character(for: code)?.lowercased() ?? fallback(code)
        switch typed {
        case Guarded.quit.key: return .quit
        case Guarded.close.key: return .close
        default: return nil
        }
    }

    private func fallback(_ code: Int64) -> String? {
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
