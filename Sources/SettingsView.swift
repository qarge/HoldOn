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

    private static let presets: [Double] = [0.3, 0.5, 1, 1.5, 2, 3]

    var body: some View {
        Form {
            Section {
                header
            }

            Section("Hold for") {
                HoldSlider(delay: $store.delay, range: store.minDelay...store.maxDelay)
                Picker("Hold for", selection: presetBinding) {
                    ForEach(Self.presets, id: \.self) { Text(seconds($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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

    // MARK: - Hold time

    /// A preset lights up only when the slider sits exactly on it.
    private var presetBinding: Binding<Double> {
        Binding(get: { store.delay }, set: { store.delay = $0 })
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

/// "0.3 s", "1 s", "1.5 s".
private func seconds(_ value: Double) -> String {
    let number = value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    return String(format: NSLocalizedString("%@ s", comment: ""), number)
}

/// The same bar as the overlay, used as the slider. Drag it or use the arrow keys; letting
/// go, or picking a preset, draws the bar at real speed so the length can be felt.
private struct HoldSlider: View {
    @Binding var delay: Double
    let range: ClosedRange<Double>

    @State private var drawn = 1.0
    @State private var dragging = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let knob: CGFloat = 16

    var body: some View {
        HStack(spacing: 12) {
            GeometryReader { geometry in
                let track = geometry.size.width - knob
                let x = track * fraction
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 6)
                        .padding(.horizontal, knob / 2)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: knob / 2 + x * drawn, height: 6)
                        .padding(.leading, knob / 2)
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                        .overlay(Circle().strokeBorder(.black.opacity(0.08)))
                        .frame(width: knob, height: knob)
                        .offset(x: x)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = true
                            drawn = 1
                            set(range.lowerBound + (value.location.x - knob / 2) / track
                                * (range.upperBound - range.lowerBound))
                        }
                        .onEnded { _ in
                            dragging = false
                            replay()
                        }
                )
            }
            .frame(height: 22)

            Text(seconds(delay))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .focusable()
        .focused($focused)
        .onKeyPress(.leftArrow) { step(-0.1); return .handled }
        .onKeyPress(.rightArrow) { step(0.1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Hold for", comment: ""))
        .accessibilityValue(seconds(delay))
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 0.1 : -0.1)
        }
        .onChange(of: delay) { _, _ in
            if !dragging { replay() }
        }
    }

    private var fraction: Double {
        (delay - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    /// Tenths only, so a dragged value can land exactly on a preset.
    private func set(_ value: Double) {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let tenth = (clamped * 10).rounded() / 10
        if tenth != delay { delay = tenth }
    }

    private func step(_ amount: Double) {
        set(delay + amount)
    }

    private func replay() {
        guard !reduceMotion else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { drawn = 0 }
        // Next tick, so the empty bar is drawn before it starts filling.
        DispatchQueue.main.async {
            withAnimation(.linear(duration: delay)) { drawn = 1 }
        }
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
            .padding(12)

            Divider()

            List(shown, id: \.processIdentifier) { app in
                Button {
                    onPick(Target(running: app))
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
            .searchable(text: $search)
        }
        .frame(width: 340, height: 360)
        .onAppear {
            apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
        }
    }
}
