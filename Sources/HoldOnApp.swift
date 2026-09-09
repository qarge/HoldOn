//
//  HoldOnApp.swift
//  HoldOn — menu bar entry point.
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
        return store.protectionOn ? "hand.raised.fill" : "hand.raised.slash"
    }
}

struct MenuContent: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        Text(verbatim: "HoldOn \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")

        Divider()

        if !store.trusted {
            Button("Allow accessibility access…") { Permission.request() }
            Divider()
        }

        Toggle("Protection", isOn: $store.protectionOn)
        Toggle("Guard ⌘W as well", isOn: $store.guardClose)

        Divider()

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Toggle("Launch at login", isOn: Binding(get: { LaunchAtLogin.enabled },
                                                set: { LaunchAtLogin.enabled = $0 }))

        Divider()

        Button("Quit HoldOn") { NSApp.terminate(nil) }
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
            MainActor.assumeIsolated { self?.sync(Store.shared.protectionOn) }
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

enum LaunchAtLogin {
    static var enabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                try newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            } catch {
                NSLog("HoldOn: launch at login failed: \(error.localizedDescription)")
            }
        }
    }
}
