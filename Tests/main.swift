//  Copyright (C) 2026 qarge
//  SPDX-License-Identifier: GPL-3.0-or-later

// The matching rules are the only tricky logic here. Run with: make test
import Foundation

let safari = Identity(bundleID: "com.apple.Safari",
                      execPath: "/Applications/Safari.app/Contents/MacOS/Safari")
let java = Identity(bundleID: nil,
                    execPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")

assert(safari.matches(Target(id: "com.apple.Safari", name: "Safari")))
assert(!safari.matches(Target(id: "com.apple.Terminal", name: "Terminal")))
assert(!safari.matches(Target(id: "/usr/bin/java", name: "java")))

// A bundle-less process is matched by path, and by binary name across JDK copies.
assert(java.matches(Target(id: "/usr/bin/java", name: "java")))
assert(java.matches(Target(id: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java", name: "java")))
assert(!java.matches(Target(id: "/usr/bin/node", name: "node")))
assert(!java.matches(Target(id: "com.apple.Safari", name: "Safari")))

// An .app the user picks in the file panel becomes a bundle target, a binary stays a path.
assert(Target(file: URL(fileURLWithPath: "/System/Applications/Calculator.app")).id == "com.apple.calculator")
assert(Target(file: URL(fileURLWithPath: "/usr/bin/java")).id == "/usr/bin/java")

print("matching: ok")
