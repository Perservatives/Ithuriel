import AppKit
import Combine
import SwiftUI

/// Full-screen edge highlight while `AgentLoop` is driving keyboard/mouse.
/// One borderless, click-through window per display.
@MainActor
final class AgentControlBorderOverlay {
    static let shared = AgentControlBorderOverlay()
    private init() {}

    private var borderWindows: [NSWindow] = []
    private var runningSubscription: AnyCancellable?

    func configure(agentLoop: AgentLoop) {
        runningSubscription = agentLoop.$isRunning
            .receive(on: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] running in
                if running {
                    self?.show()
                } else {
                    self?.hide()
                }
            }
    }

    private func show() {
        hide()
        for screen in NSScreen.screens {
            let window = TransparentWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .statusBar
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: AgentControlBorderView())
            window.orderFrontRegardless()
            borderWindows.append(window)
        }
    }

    private func hide() {
        for window in borderWindows {
            window.orderOut(nil)
        }
        borderWindows.removeAll()
    }
}

/// Glowing frame around the active display while the agent is in control.
private struct AgentControlBorderView: View {
    @State private var pulse = false

    private let borderWidth: CGFloat = 3
    private let inset: CGFloat = 4

    var body: some View {
        Rectangle()
            .strokeBorder(borderGradient, lineWidth: borderWidth)
            .padding(inset)
            .shadow(color: Color(red: 0.25, green: 0.92, blue: 0.55).opacity(pulse ? 0.55 : 0.35),
                    radius: pulse ? 14 : 9)
            .shadow(color: Color.accentColor.opacity(pulse ? 0.35 : 0.2), radius: pulse ? 8 : 5)
            .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.30, green: 0.95, blue: 0.58),
                Color.accentColor,
                Color(red: 0.22, green: 0.88, blue: 0.50)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
