//  Copyright (C) 2026 qarge
//  SPDX-License-Identifier: GPL-3.0-or-later

// The matching rules are the only tricky logic here. Run with: make test
import XCTest
@testable import HoldOn

final class MatchingTests: XCTestCase {
    private let safari = Identity(bundleID: "com.apple.Safari",
                                  execPath: "/Applications/Safari.app/Contents/MacOS/Safari")
    private let java = Identity(bundleID: nil,
                                execPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")

    func testBundleTargetsMatchOnlyTheirBundle() {
        XCTAssertTrue(safari.matches(Target(id: "com.apple.Safari", name: "Safari")))
        XCTAssertFalse(safari.matches(Target(id: "com.apple.Terminal", name: "Terminal")))
        XCTAssertFalse(safari.matches(Target(id: "/usr/bin/java", name: "java")))
    }

    // A bundle-less process is matched by path, and by binary name across JDK copies.
    func testPathTargetsMatchByPathOrName() {
        XCTAssertTrue(java.matches(Target(id: "/usr/bin/java", name: "java")))
        XCTAssertTrue(java.matches(Target(id: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java", name: "java")))
        XCTAssertFalse(java.matches(Target(id: "/usr/bin/node", name: "node")))
        XCTAssertFalse(java.matches(Target(id: "com.apple.Safari", name: "Safari")))
    }

    // An .app picked in the file panel becomes a bundle target, a binary stays a path.
    func testPickedFilesBecomeTheRightKindOfTarget() {
        XCTAssertEqual(Target(file: URL(fileURLWithPath: "/System/Applications/Calculator.app")).id, "com.apple.calculator")
        XCTAssertEqual(Target(file: URL(fileURLWithPath: "/usr/bin/java")).id, "/usr/bin/java")
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
