//
//  SettingsView.swift
//  HoldOn — the settings window.
//
//  Copyright (C) 2026 qarge
//  Portions Copyright (c) 2025 dudukee, from SlowQuit, under the MIT License (see NOTICE)
//  SPDX-License-Identifier: GPL-3.0-or-later AND MIT
//

import SwiftUI
import AppKit

/// The one settings window, opened from the menu, on launch and from Launchpad.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        let window = self.window ?? make()
        self.window = window
        // An accessory app opens its windows behind whatever is in front unless it asks.
        // activate() is only a request since macOS 14, so also put the window on top
        // outright; it takes focus as soon as it is clicked.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func make() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView())
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = "HoldOn"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct SettingsView: View {
    @ObservedObject private var store = Store.shared
    @State private var pickingRunning = false

    var body: some View {
        Form {
            Section {
                header
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hold time")
                        Spacer()
                        Text(String(format: NSLocalizedString("%.1f s", comment: ""), store.delay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.delay, in: HoldTime.range, step: 0.1)
                        .accessibilityLabel(Text("Hold time"))
                }
                Toggle("Also hold ⌘W before a window closes", isOn: $store.guardClose)
            }

            Section("Applies to") {
                ForEach(Scope.allCases) { scopeRow($0) }
            }

            if store.scope != .everywhere {
                Section {
                    targetRows
                } header: {
                    Text(store.scope == .only ? "Apps that need the hold" as LocalizedStringKey : "Apps that quit right away")
                } footer: {
                    Text("Apps and plain executables both work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: store.scope == .everywhere ? 540 : 700)
        .sheet(isPresented: $pickingRunning) {
            RunningPicker { store.add($0) }
        }
        .onAppear { store.refreshTrust() }
    }

    // MARK: - Header

    /// What the guard is doing right now. The switch itself lives in the menu bar.
    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(status.title)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(status.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !store.trusted {
                Button("Allow…") { Permission.request() }
            }
        }
        .padding(.vertical, 4)
    }

    private var status: (title: String, detail: String, color: Color) {
        if !store.trusted {
            return (NSLocalizedString("Accessibility access is off", comment: ""),
                    NSLocalizedString("HoldOn cannot see ⌘Q until you allow it.", comment: ""),
                    .orange)
        }
        if !store.protectionOn {
            return (NSLocalizedString("Paused", comment: ""),
                    NSLocalizedString("Turn it back on from the hand in the menu bar.", comment: ""),
                    .gray)
        }

        if !store.guarding {
            return (NSLocalizedString("Protection is not running", comment: ""),
                    NSLocalizedString("macOS switched the keyboard watch off. HoldOn checks every few seconds and brings it back.", comment: ""),
                    .orange)
        }
        if store.scope == .only && store.targets.isEmpty {
            return (NSLocalizedString("Nothing is guarded yet", comment: ""),
                    NSLocalizedString("Only these apps is picked, and the list is empty. Add an app below.", comment: ""),
                    .orange)
        }

        let keys = store.guardClose ? "⌘Q ⌘W" : "⌘Q"
        let count = store.targets.count
        let apps = count == 1
            ? NSLocalizedString("1 app", comment: "")
            : String(format: NSLocalizedString("%d apps", comment: ""), count)
        let title: String
        switch store.scope {
        case .everywhere:
            title = String(format: NSLocalizedString("Holding %@ in every app", comment: ""), keys)
        case .except:
            title = String(format: NSLocalizedString("Holding %@ everywhere but %@", comment: ""), keys, apps)
        case .only:
            title = String(format: NSLocalizedString("Holding %@ in %@", comment: ""), keys, apps)
        }
        return (title, NSLocalizedString("Switch it off from the hand in the menu bar.", comment: ""), .green)
    }

    // MARK: - Scope

    private func scopeRow(_ scope: Scope) -> some View {
        let selected = store.scope == scope
        return Button {
            store.scope = scope
        } label: {
            HStack(spacing: 10) {
                Image(systemName: scope.symbol)
                    .frame(width: 20)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(scope.title)
                    Text(scope.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - List

    @ViewBuilder
    private var targetRows: some View {
        if store.targets.isEmpty {
            Text("Add the apps this should cover.")
                .foregroundStyle(.secondary)
        }
        ForEach(store.targets) { target in
            HStack(spacing: 10) {
                icon(target.icon, fallback: target.isPath ? "terminal" : "app")
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name)
                    Text(target.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    store.targets.removeAll { $0.id == target.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(format: NSLocalizedString("Remove %@", comment: ""), target.name))
                .accessibilityLabel(String(format: NSLocalizedString("Remove %@", comment: ""), target.name))
            }
        }
        Menu {
            Button("A running app…") { pickingRunning = true }
            Button("An app or program file…") { chooseFile() }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func icon(_ image: NSImage?, fallback: String) -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: fallback).resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("Choose an app or an executable file", comment: "")
        panel.prompt = NSLocalizedString("Add", comment: "")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { store.add(Target(file: $0)) }
    }
}

/// Picks from the apps that are running right now, including ones without a bundle
/// (a `java -jar …` window shows up here as "java").
struct RunningPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var apps: [NSRunningApplication] = []

    let onPick: (Target) -> Void

    private var shown: [NSRunningApplication] {
        guard !search.isEmpty else { return apps }
        return apps.filter {
            ($0.localizedName ?? "").localizedCaseInsensitiveContains(search)
                || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Running apps").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top], 12)

            // In the content rather than .searchable, which adds a toolbar that widens the sheet.
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            Divider()

            List(shown, id: \.processIdentifier) { app in
                Button {
                    if let target = Target(running: app) { onPick(target) }
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        if let image = app.icon {
                            Image(nsImage: image).resizable().frame(width: 22, height: 22)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.localizedName ?? "?")
                            Text(app.bundleIdentifier ?? app.executableURL?.path ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .truncationMode(.middle)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 320, height: 340)
        .onAppear {
            apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                .filter { $0.bundleIdentifier != nil || $0.executableURL != nil }   // nothing else can be matched
                .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
        }
    }
}
