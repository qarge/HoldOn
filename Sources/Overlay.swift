//
//  Overlay.swift
//  HoldOn — the small HUD shown while a guarded shortcut is held.
//
//  Copyright (C) 2026 qarge
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

@MainActor
final class OverlayModel: ObservableObject {
    @Published var title = ""
    @Published var subtitle = ""
    @Published var icon: NSImage?
    @Published var progress = 0.0
    @Published var visible = false
}

@MainActor
final class Overlay {
    private let model = OverlayModel()

    private lazy var window: NSWindow = {
        let window = NSWindow(contentRect: NSScreen.main?.frame ?? .zero,
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: OverlayView(model: model))
        return window
    }()

    /// Builds the window up front so the first hold does not wait on SwiftUI.
    func prewarm() { _ = window }

    func show(title: String, subtitle: String, icon: NSImage?, duration: TimeInterval) {
        model.title = title
        model.subtitle = subtitle
        model.icon = icon
        model.progress = 0
        model.visible = true

        if let screen = NSScreen.main { window.setFrame(screen.frame, display: false) }
        window.orderFrontRegardless()

        // Next tick, so the bar is actually drawn empty before it starts filling.
        DispatchQueue.main.async {
            guard self.model.visible else { return }   // hidden again already: a very short tap
            withAnimation(.linear(duration: duration)) { self.model.progress = 1 }
        }
    }

    func hide() {
        model.visible = false
        model.progress = 0
        window.orderOut(nil)
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    private let barWidth: CGFloat = 180

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Group {
                    if let icon = model.icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "hand.raised.fill").resizable().scaledToFit().padding(4)
                    }
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(model.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Capsule()
                        .fill(.quaternary)
                        .frame(width: barWidth, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: barWidth * model.progress, height: 4)
                        }
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
            )
            .shadow(color: .black.opacity(0.28), radius: 20, y: 8)
            .opacity(model.visible ? 1 : 0)
            .padding(.bottom, 140)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
