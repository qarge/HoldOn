// swift-tools-version: 5.10
//
// Describes the sources for SourceKit-LSP (Zed, VS Code, Xcode) and for `swift test`.
// The app itself is built by the Makefile, which produces the signed universal .app.
//
// Copyright (C) 2026 qarge
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "HoldOn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "HoldOn", path: "Sources"),
        .testTarget(name: "HoldOnTests", dependencies: ["HoldOn"], path: "Tests"),
    ]
)
