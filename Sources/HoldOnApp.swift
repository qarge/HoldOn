//
//  HoldOnApp.swift
//  HoldOn — menu bar entry point.
//
//  Copyright (C) 2026 qarge
//  Portions Copyright (c) 2025 dudukee, from SlowQuit, under the MIT License (see NOTICE)
//  SPDX-License-Identifier: GPL-3.0-or-later AND MIT
//

import SwiftUI
import Combine
import ServiceManagement
import ApplicationServices

@main
struct HoldOnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The status item and the settings window are AppKit-owned, see MenuBar and
        // SettingsWindow: SwiftUI has no public way to open its own Settings scene from
        // code, and launch and Launchpad clicks both need to. SwiftUI still wants a scene,
        // and this one points ⌘, at our window.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { SettingsWindow.show() }
                        .keyboardShortcut(",")
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let guardian = KeyGuard()
    private var menuBar: MenuBar?
    private var watch: AnyCancellable?
    private var poll: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = Store.shared
        store.refreshTrust()
        menuBar = MenuBar()

        watch = store.$protectionOn.sink { [weak self] on in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.sync(on) } }
        }
        sync(store.protectionOn)

        // ponytail: a 5 s poll is the whole health check. Granting or revoking accessibility
        // access sends no notification, and it costs less than watching for it properly.
        poll = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync(Store.shared.protectionOn) }
        }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "welcomed") {
            defaults.set(true, forKey: "welcomed")
            SettingsWindow.show()
            // The status item takes its place in the menu bar a moment after launch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { self.menuBar?.showWelcome() }
            }
        } else if !launchedAsLoginItem {
            SettingsWindow.show()
        }
    }

    /// A click on the app in Launchpad or Finder while it already runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        guardian.stop()
    }

    /// Opened by macOS at login rather than by a click, which should stay silent.
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    private func sync(_ wanted: Bool) {
        if wanted && Store.shared.refreshTrust() {
            guardian.start()
        } else {
            guardian.stop()
        }
    }
}

enum Permission {
    /// The system prompt, which also lists the app in System Settings.
    static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Prompt and open the settings pane, from the Allow buttons.
    static func request() {
        prompt()
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }
}

/// The login-item registration. The menu reads it on every open, so its checkmark shows what
/// macOS actually did, including changes made in System Settings.
@MainActor
final class LaunchAtLogin {
    static let shared = LaunchAtLogin()

    private(set) var isOn = SMAppService.mainApp.status == .enabled

    private init() {}

    func refresh() {
        isOn = SMAppService.mainApp.status == .enabled
    }

    func set(_ wanted: Bool) {
        let service = SMAppService.mainApp
        do {
            if wanted {
                // A registration left behind by an earlier copy of the bundle makes
                // register() a no-op, so clear it first.
                if service.status == .enabled { try? service.unregister() }
                try service.register()
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            refresh()
            explain(error, wanted: wanted)
            return
        }

        refresh()
        // register() succeeds while macOS still waits for the user in System Settings.
        if wanted && !isOn { explain(nil, wanted: true) }
    }

    private func explain(_ error: Error?, wanted: Bool) {
        let alert = NSAlert()
        alert.messageText = wanted
            ? NSLocalizedString("HoldOn was not added to your login items", comment: "")
            : NSLocalizedString("HoldOn was not removed from your login items", comment: "")
        alert.informativeText = error?.localizedDescription
            ?? NSLocalizedString("macOS is waiting for you to allow it.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Open Login Items", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Close", comment: ""))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
