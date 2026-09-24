//  Copyright (C) 2026 qarge
//  SPDX-License-Identifier: GPL-3.0-or-later

// The matching rules and the hold time are the tricky logic here. Run with: make test
import XCTest
@testable import HoldOn

final class MatchingTests: XCTestCase {
    private let safari = Identity(bundleID: "com.apple.Safari",
                                  execPath: "/Applications/Safari.app/Contents/MacOS/Safari")
    private let java = Identity(bundleID: nil,
                                execPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")

    private func target(_ id: String) -> ResolvedTarget {
        ResolvedTarget(Target(id: id, name: (id as NSString).lastPathComponent))
    }

    func testBundleTargetsMatchOnlyTheirBundle() {
        XCTAssertTrue(safari.matches(target("com.apple.Safari")))
        XCTAssertFalse(safari.matches(target("com.apple.Terminal")))
        XCTAssertFalse(safari.matches(target("/usr/bin/java")))
    }

    // A bundle-less process is matched by path, and by binary name across JDK copies.
    func testPathTargetsMatchByPathOrName() {
        XCTAssertTrue(java.matches(target("/usr/bin/java")))
        XCTAssertTrue(java.matches(target("/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")))
        XCTAssertFalse(java.matches(target("/usr/bin/node")))
        XCTAssertFalse(java.matches(target("com.apple.Safari")))
    }

    // An .app picked in the file panel becomes a bundle target, a binary stays a path.
    func testPickedFilesBecomeTheRightKindOfTarget() {
        XCTAssertEqual(Target(file: URL(fileURLWithPath: "/System/Applications/Calculator.app")).id, "com.apple.calculator")
        XCTAssertEqual(Target(file: URL(fileURLWithPath: "/usr/bin/java")).id, "/usr/bin/java")
    }

    // A path is resolved when the list changes, so a symlinked target still matches the
    // executable the running process reports.
    func testTargetPathsAreResolvedOnceUpFront() {
        let resolved = ResolvedTarget(Target(id: "/var/select/sh", name: "sh"))
        XCTAssertEqual(resolved.path, URL(fileURLWithPath: "/var/select/sh").resolvingSymlinksInPath().path)
        XCTAssertEqual(resolved.name, "sh")
        XCTAssertNil(resolved.bundleID)
        XCTAssertNil(ResolvedTarget(Target(id: "com.apple.Safari", name: "Safari")).path)
    }
}

final class DelayTests: XCTestCase {
    // A hold time read from preferences decides how long ⌘Q is swallowed, so junk must not
    // reach the timer: 0 comes from a missing or wrongly typed value, and huge values would
    // hold the shortcut for minutes.
    func testUnusableValuesFallBackToTheDefault() {
        XCTAssertEqual(HoldTime.clamped(0), HoldTime.standard)
        XCTAssertEqual(HoldTime.clamped(-5), HoldTime.standard)
        XCTAssertEqual(HoldTime.clamped(.nan), HoldTime.standard)
        XCTAssertEqual(HoldTime.clamped(.infinity), HoldTime.standard)
    }

    func testValuesOutsideTheRangeAreClamped() {
        XCTAssertEqual(HoldTime.clamped(0.1), HoldTime.min)
        XCTAssertEqual(HoldTime.clamped(3600), HoldTime.max)
    }

    func testValuesInsideTheRangeSurvive() {
        XCTAssertEqual(HoldTime.clamped(HoldTime.min), HoldTime.min)
        XCTAssertEqual(HoldTime.clamped(1.4), 1.4)
        XCTAssertEqual(HoldTime.clamped(HoldTime.max), HoldTime.max)
    }
}
