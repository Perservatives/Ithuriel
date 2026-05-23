import AppKit
import Combine
import SwiftUI

/// Full-screen white edge frame while `AgentLoop` is driving keyboard/mouse.
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
            window.level = .screenSaver
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

/// White frame around each display while the agent is in control.
private struct AgentControlBorderView: View {
    @State private var pulse = false

    private let borderWidth: CGFloat = 4
    private let inset: CGFloat = 2

    var body: some View {
        Rectangle()
            .strokeBorder(Color.white.opacity(pulse ? 0.95 : 0.72), lineWidth: borderWidth)
            .padding(inset)
            .shadow(color: Color.white.opacity(pulse ? 0.55 : 0.30), radius: pulse ? 16 : 10)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
