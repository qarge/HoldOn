//
//  MenuBar.swift
//  HoldOn — the status item, its menu, and the first-launch pointer to it.
//
//  Copyright (C) 2026 qarge
//  Portions Copyright (c) 2025 dudukee, from SlowQuit, under the MIT License (see NOTICE)
//  SPDX-License-Identifier: GPL-3.0-or-later AND MIT
//

import AppKit
import SwiftUI
import Combine

/// Owned in AppKit rather than a SwiftUI MenuBarExtra, because the welcome popover
/// needs the status item's button to point at.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store = Store.shared
    private var watch: AnyCancellable?
    private var welcome: NSPopover?

    override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.setAccessibilityLabel("HoldOn")

        // objectWillChange fires before the new value lands, so read it on the next tick.
        watch = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateIcon() } }
        }
        updateIcon()
    }

    private func updateIcon() {
        // Filled and outlined variants of one symbol share their metrics, and the item has a
        // fixed square width, so the icon never moves when protection is switched off.
        let stalled = store.protectionOn && !store.guarding
        let name = !store.trusted || stalled ? "exclamationmark.triangle.fill"
            : store.protectionOn ? "hand.raised.fill" : "hand.raised"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "HoldOn")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        image?.isTemplate = true
        item.button?.image = image
    }

    // MARK: - Menu

    /// Rebuilt on every open, so each item shows the state macOS reports right now.
    func menuNeedsUpdate(_ menu: NSMenu) {
        LaunchAtLogin.shared.refresh()
        menu.removeAllItems()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let title = NSMenuItem(title: "HoldOn \(version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        if !store.trusted {
            menu.addItem(entry("Allow accessibility access…", #selector(allowAccess)))
            menu.addItem(.separator())
        }

        menu.addItem(entry(store.protectionOn ? "Disable" : "Enable", #selector(toggleProtection)))
        menu.addItem(.separator())

        menu.addItem(entry("Settings…", #selector(openSettings), key: ","))
        let login = entry("Launch at login", #selector(toggleLaunchAtLogin))
        login.state = LaunchAtLogin.shared.isOn ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(entry("Quit", #selector(quit), key: "q"))
    }

    func menuWillOpen(_ menu: NSMenu) {
        welcome?.close()
    }

    private func entry(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: NSLocalizedString(title, comment: ""), action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    @objc private func allowAccess() { Permission.request() }
    @objc private func toggleProtection() { store.protectionOn.toggle() }
    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func toggleLaunchAtLogin() { LaunchAtLogin.shared.set(!LaunchAtLogin.shared.isOn) }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Welcome

    /// Points at the menu bar icon once, on the first launch. The app has no Dock icon,
    /// so without this it is easy to lose.
    func showWelcome() {
        // A crowded menu bar can hide the item behind the notch; then there is nothing to point at.
        guard let button = item.button, let window = button.window,
              window.occlusionState.contains(.visible) else { return }

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.contentViewController = NSHostingController(rootView: WelcomeView { [weak popover] in
            popover?.close()
        })
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        welcome = popover
    }
}

private struct WelcomeView: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HoldOn lives up here")
                .font(.headline)
            Text("It has no Dock icon. Click the hand to turn the guard off and on, open settings or quit.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Got it", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 270)
    }
}
