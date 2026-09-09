//
//  SettingsView.swift
//  HoldOn — the single settings window.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var store = Store.shared
    @State private var pickingRunning = false

    var body: some View {
        Form {
            if !store.trusted {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility access is off")
                                .font(.system(size: 12, weight: .semibold))
                            Text("HoldOn cannot watch shortcuts until you allow it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Allow…") { Permission.request() }
                    }
                }
            }

            Section {
                Toggle("Protection", isOn: $store.protectionOn)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hold time")
                        Spacer()
                        Text(String(format: "%.1f s", store.delay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.delay, in: store.minDelay...store.maxDelay, step: 0.1)
                }
                Toggle("Guard ⌘W as well", isOn: $store.guardClose)
            } footer: {
                Text("⌘Q and, if enabled, ⌘W only go through when you keep them held down.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Where it applies") {
                Picker("Scope", selection: $store.scope) {
                    ForEach(Scope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(store.scope.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if store.scope != .everywhere {
                    targetList
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: store.scope == .everywhere ? 420 : 620)
        .sheet(isPresented: $pickingRunning) {
            RunningPicker { store.add($0) }
        }
        .onAppear {
            store.refreshTrust()
            // An accessory app opens its settings window behind whatever is in front.
            DispatchQueue.main.async {
                NSApp.activate()
                NSApp.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private var targetList: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach(store.targets) { target in
                    HStack(spacing: 8) {
                        icon(target.icon, fallback: target.isPath ? "terminal" : "app")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(target.name).font(.system(size: 12))
                            Text(target.id)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .truncationMode(.middle)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            store.targets.removeAll { $0.id == target.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(height: 190)
            .overlay {
                if store.targets.isEmpty {
                    Text("Nothing added yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Menu {
                    Button("Running app…") { pickingRunning = true }
                    Button("App or binary file…") { chooseFile() }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Text("Applications and plain executables are both supported.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func icon(_ image: NSImage?, fallback: String) -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: fallback).resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("Choose an application or an executable file", comment: "")
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
                Text("Running apps").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
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
                            Text(app.localizedName ?? "?").font(.system(size: 12))
                            Text(app.bundleIdentifier ?? app.executableURL?.path ?? "")
                                .font(.system(size: 10))
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
        .frame(width: 380, height: 420)
        .onAppear {
            apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                .sorted { ($0.localizedName ?? "") .localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
        }
    }
}
