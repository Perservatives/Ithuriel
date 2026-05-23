import SwiftUI

/// Inline thinking indicator that mutates its label in place instead of
/// stacking new transcript rows. Mirrors the Claude Code "still thinking /
/// thinking more / almost done thinking" pattern. Renders nothing once the
/// agent stops running.
///
/// Drop in next to a TranscriptChip; takes the parent's @ObservedObject
/// `AgentLoop` to know when to start/stop and a tiny pulsing dot to signal
/// activity. No new transcript lines are created; the label is pure state.
struct ThinkingSpinner: View {
    @ObservedObject var agent: AgentLoop
    @State private var elapsed: TimeInterval = 0
    @State private var started: Date?
    @State private var dotPulse = false

    var body: some View {
        if agent.isRunning {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .scaleEffect(dotPulse ? 1.35 : 0.9)
                    .opacity(dotPulse ? 1 : 0.6)
                Text(label(for: elapsed))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .id(bucketID(for: elapsed))    // forces a clean transition between buckets
            }
            .animation(.easeInOut(duration: 0.25), value: bucketID(for: elapsed))
            .onAppear {
                started = Date()
                elapsed = 0
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    dotPulse = true
                }
            }
            .onDisappear {
                started = nil
                dotPulse = false
            }
            .task {
                // Tick once per second; the bucketed label changes infrequently
                // so the visible mutation is intentional, not flickery.
                while agent.isRunning {
                    if let started { elapsed = Date().timeIntervalSince(started) }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    private func label(for t: TimeInterval) -> String {
        switch t {
        case ..<3:   return NSLocalizedString("thinking.0", comment: "")
        case ..<10:  return NSLocalizedString("thinking.1", comment: "")
        case ..<25:  return NSLocalizedString("thinking.2", comment: "")
        case ..<60:  return NSLocalizedString("thinking.3", comment: "")
        default:     return NSLocalizedString("thinking.4", comment: "")
        }
    }

    private func bucketID(for t: TimeInterval) -> Int {
        switch t {
        case ..<3:   return 0
        case ..<10:  return 1
        case ..<25:  return 2
        case ..<60:  return 3
        default:     return 4
        }
    }
}
