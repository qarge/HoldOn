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

/// How long a guarded shortcut has to be held. Preferences can hold anything: a value edited
/// by hand, a wrong type that reads back as 0, or a leftover from another version. An unusable
/// hold time would either wave ⌘Q straight through or swallow it for minutes, so nothing
/// reaches the timer unchecked.
enum HoldTime {
    static let min = 0.3
    static let max = 3.0
    static let standard = 1.0

    static func clamped(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return standard }
        return Swift.min(Swift.max(value, min), max)
    }
}

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

    /// Fails for a process that reports neither a bundle nor an executable: there would be
    /// nothing to match it by, so the entry could only sit in the list doing nothing.
    init?(running app: NSRunningApplication) {
        guard let identifier = app.bundleIdentifier ?? app.executableURL?.path else { return nil }
        id = identifier
        name = app.localizedName ?? app.executableURL?.lastPathComponent ?? identifier
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A target with its path resolved once, when the list changes rather than when a key is
/// pressed. The tap callback sits inside the keystroke delivery path, and a target on a
/// stalled network or removable volume would block every key in the session.
struct ResolvedTarget {
    let bundleID: String?
    /// The path as the user gave it, plus the symlink-free form once that is known.
    let paths: Set<String>
    let name: String?

    init(_ target: Target, resolved: String? = nil) {
        if target.isPath {
            bundleID = nil
            paths = resolved.map { [target.id, $0] } ?? [target.id]
            name = (target.id as NSString).lastPathComponent
        } else {
            bundleID = target.id
            paths = []
            name = nil
        }
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

    /// Takes the executable path as the kernel reports it, with no filesystem work: this is
    /// built inside the tap callback, in the keystroke delivery path.
    init(_ app: NSRunningApplication) {
        self.init(bundleID: app.bundleIdentifier, execPath: app.executableURL?.path)
    }

    func matches(_ target: ResolvedTarget) -> Bool {
        if let wanted = target.bundleID { return wanted == bundleID }
        if let path = execPath, target.paths.contains(path) { return true }
        // ponytail: also match on the executable name so /usr/bin/java covers every JDK copy.
        // Drop this line if you ever need to protect one specific build of a binary.
        return target.name != nil && target.name == execName
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    var minDelay: Double { HoldTime.min }
    var maxDelay: Double { HoldTime.max }

    @Published var protectionOn: Bool { didSet { d.set(protectionOn, forKey: "protectionOn") } }
    @Published var delay: Double {
        didSet {
            let safe = HoldTime.clamped(delay)
            // Swift does not re-enter didSet for an assignment made inside it, so this
            // corrects the value without recursion, and the safe one is what gets stored.
            if safe != delay { delay = safe }
            d.set(safe, forKey: "delay")
        }
    }
    @Published var guardClose: Bool { didSet { d.set(guardClose, forKey: "guardClose") } }
    @Published var scope: Scope { didSet { d.set(scope.rawValue, forKey: "scope") } }
    @Published var targets: [Target] {
        didSet {
            d.set(try? JSONEncoder().encode(targets), forKey: "targets")
            rebuildTargets()
        }
    }
    /// Accessibility permission, refreshed by the app delegate.
    @Published private(set) var trusted = AXIsProcessTrusted()

    private let d = UserDefaults.standard
    private var resolvedTargets: [ResolvedTarget] = []

    private init() {
        d.register(defaults: ["protectionOn": true, "delay": HoldTime.standard, "guardClose": false])
        protectionOn = d.bool(forKey: "protectionOn")
        let stored = d.double(forKey: "delay")
        delay = HoldTime.clamped(stored)
        guardClose = d.bool(forKey: "guardClose")
        scope = Scope(rawValue: d.string(forKey: "scope") ?? "") ?? .everywhere
        targets = (d.data(forKey: "targets")).flatMap { try? JSONDecoder().decode([Target].self, from: $0) } ?? []
        rebuildTargets()
        if stored != delay { d.set(delay, forKey: "delay") }   // repair an unusable stored value
    }

    /// The list a keystroke is matched against. The paths as given are ready at once, so a
    /// press never waits on anything; their symlink-free forms are filled in off the main
    /// thread, because a target on a stalled volume must not hold up a launch either.
    private func rebuildTargets() {
        resolvedTargets = targets.map { ResolvedTarget($0) }

        let snapshot = targets
        Task.detached(priority: .utility) {
            let enriched = snapshot.map { target in
                target.isPath
                    ? ResolvedTarget(target, resolved: URL(fileURLWithPath: target.id).resolvingSymlinksInPath().path)
                    : ResolvedTarget(target)
            }
            await MainActor.run { [weak self] in
                guard let self, self.targets == snapshot else { return }
                self.resolvedTargets = enriched
            }
        }
    }

    func add(_ target: Target) {
        guard !targets.contains(where: { $0.id == target.id }) else { return }
        targets.append(target)
        targets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// True when the shortcut must be held for this app.
    func applies(to app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        switch scope {
        case .everywhere: return true
        case .only: return listContains(app)
        case .except: return !listContains(app)
        }
    }

    private func listContains(_ app: NSRunningApplication) -> Bool {
        let identity = Identity(app)
        return resolvedTargets.contains { identity.matches($0) }
    }

    @discardableResult
    func refreshTrust() -> Bool {
        let now = AXIsProcessTrusted()
        if now != trusted { trusted = now }
        return now
    }
}
