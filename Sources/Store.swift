//
//  Store.swift
//  HoldOn — settings, protected-target list, and the matching rules.
//
//  Copyright (C) 2026 qarge
//  Portions Copyright (c) 2025 dudukee, from SlowQuit, under the MIT License (see NOTICE)
//  SPDX-License-Identifier: GPL-3.0-or-later AND MIT
//

import AppKit
import ApplicationServices

/// Where the hold guard applies.
enum Scope: String, CaseIterable, Identifiable {
    case everywhere, except, only

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everywhere: return NSLocalizedString("Every app", comment: "")
        case .except: return NSLocalizedString("Every app except these", comment: "")
        case .only: return NSLocalizedString("Only these apps", comment: "")
        }
    }

    var hint: String {
        switch self {
        case .everywhere: return NSLocalizedString("⌘Q needs the hold wherever you are.", comment: "")
        case .except: return NSLocalizedString("The apps in the list quit right away.", comment: "")
        case .only: return NSLocalizedString("Only the apps in the list need the hold.", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .everywhere: return "globe"
        case .except: return "minus.circle"
        case .only: return "checklist"
        }
    }
}

/// One protected program. `id` is either a bundle identifier ("com.apple.Safari")
/// or an absolute executable path ("/usr/bin/java") for programs that ship no bundle.
struct Target: Codable, Identifiable, Hashable {
    let id: String
    let name: String

    var isPath: Bool { id.hasPrefix("/") }

    var icon: NSImage? {
        let path = isPath ? id : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path
        return path.map { NSWorkspace.shared.icon(forFile: $0) }
    }

    /// Reads a file the user picked: an .app bundle becomes a bundle-id target,
    /// anything else (java, node, a shell script) becomes a path target.
    init(file url: URL) {
        if url.pathExtension == "app", let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier {
            id = bid
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        } else {
            id = url.path
            name = url.lastPathComponent
        }
    }

    init(running app: NSRunningApplication) {
        id = app.bundleIdentifier ?? app.executableURL?.path ?? "?"
        name = app.localizedName ?? app.executableURL?.lastPathComponent ?? "?"
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The identity of a running program, compared against the target list.
struct Identity {
    let bundleID: String?
    let execPath: String?

    var execName: String? { execPath.map { ($0 as NSString).lastPathComponent } }

    init(bundleID: String?, execPath: String?) {
        self.bundleID = bundleID
        self.execPath = execPath
    }

    init(_ app: NSRunningApplication?) {
        self.init(bundleID: app?.bundleIdentifier,
                  execPath: app?.executableURL?.resolvingSymlinksInPath().path)
    }

    func matches(_ target: Target) -> Bool {
        guard target.isPath else { return target.id == bundleID }
        if URL(fileURLWithPath: target.id).resolvingSymlinksInPath().path == execPath { return true }
        // ponytail: also match on the executable name so /usr/bin/java covers every JDK copy.
        // Drop this line if you ever need to protect one specific build of a binary.
        return (target.id as NSString).lastPathComponent == execName
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    let minDelay = 0.3
    let maxDelay = 3.0

    @Published var protectionOn: Bool { didSet { d.set(protectionOn, forKey: "protectionOn") } }
    @Published var delay: Double { didSet { d.set(delay, forKey: "delay") } }
    @Published var guardClose: Bool { didSet { d.set(guardClose, forKey: "guardClose") } }
    @Published var scope: Scope { didSet { d.set(scope.rawValue, forKey: "scope") } }
    @Published var targets: [Target] {
        didSet { d.set(try? JSONEncoder().encode(targets), forKey: "targets") }
    }
    /// Accessibility permission, refreshed by the app delegate.
    @Published private(set) var trusted = AXIsProcessTrusted()

    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: ["protectionOn": true, "delay": 1.0, "guardClose": false])
        protectionOn = d.bool(forKey: "protectionOn")
        delay = d.double(forKey: "delay")
        guardClose = d.bool(forKey: "guardClose")
        scope = Scope(rawValue: d.string(forKey: "scope") ?? "") ?? .everywhere
        targets = (d.data(forKey: "targets")).flatMap { try? JSONDecoder().decode([Target].self, from: $0) } ?? []
    }

    func add(_ target: Target) {
        guard !targets.contains(where: { $0.id == target.id }) else { return }
        targets.append(target)
        targets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// True when the shortcut must be held for this app.
    func applies(to app: NSRunningApplication?) -> Bool {
        guard app != nil else { return false }
        switch scope {
        case .everywhere: return true
        case .only: return targets.contains(where: Identity(app).matches)
        case .except: return !targets.contains(where: Identity(app).matches)
        }
    }

    @discardableResult
    func refreshTrust() -> Bool {
        let now = AXIsProcessTrusted()
        if now != trusted { trusted = now }
        return now
    }
}
