//
//  HoldOnApp.swift
//  HoldOn — menu bar entry point.
//
//  Copyright (C) 2026 qarge
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import Combine
import ServiceManagement
import ApplicationServices

@main
struct HoldOnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: symbol).accessibilityLabel("HoldOn")
        }

        Settings {
            SettingsView()
        }
    }

    private var symbol: String {
        if !store.trusted { return "exclamationmark.triangle.fill" }
        // Filled and outlined variants of one symbol share their metrics, so the
        // icon keeps its exact position when protection is switched off.
        return store.protectionOn ? "hand.raised.fill" : "hand.raised"
    }
}

struct MenuContent: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var login = LaunchAtLogin.shared

    var body: some View {
        Text(verbatim: "HoldOn \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")

        Divider()

        if !store.trusted {
            Button("Allow accessibility access…") { Permission.request() }
            Divider()
        }

        Button(store.protectionOn ? "Disable" : "Enable") {
            store.protectionOn.toggle()
        }

        Divider()

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Toggle("Launch at login", isOn: Binding(get: { login.isOn },
                                                set: { login.set($0) }))

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let guardian = KeyGuard()
    private var watch: AnyCancellable?
    private var poll: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = Store.shared
        if !store.refreshTrust() { Permission.prompt() }

        watch = store.$protectionOn.sink { [weak self] on in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.sync(on) } }
        }
        sync(store.protectionOn)

        // ponytail: a 5 s poll is the whole health check. Granting or revoking accessibility
        // access sends no notification, and it costs less than watching for it properly.
        poll = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sync(Store.shared.protectionOn)
                LaunchAtLogin.shared.refresh()   // it can also be changed in System Settings
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guardian.stop()
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
    /// The system prompt. Shown once per launch while access is missing.
    static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Prompt and open the settings pane. Only from an explicit click, never at launch.
    static func request() {
        prompt()
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }
}

/// The login-item registration. Published, because the menu has to redraw its checkmark
/// from what macOS actually did, not from what was asked for.
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published private(set) var isOn = SMAppService.mainApp.status == .enabled

    private init() {}

    func refresh() {
        let now = SMAppService.mainApp.status == .enabled
        if now != isOn { isOn = now }
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
