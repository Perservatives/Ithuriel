import Foundation
import SwiftUI

/// Lightweight observer hub so AgentLoop can notify banners and other UI when
/// a run starts/finishes — without holding references to AppKit windows directly.
///
/// `ObservableObject` so SwiftUI views can drive their headline copy off the
/// agent's most recent plain-English narration (`lastSpoken`).
@MainActor
final class AgentStatusBus: ObservableObject {
    static let shared = AgentStatusBus()
    private init() {}

    enum Event {
        case started(task: String)
        case said(message: String)         // human-readable narration from the agent
        case replied(message: String)      // casual chat reply (no task banner)
        case finished(summary: String)
        case failed(error: String)
        case stopped
    }

    @Published private(set) var isRunning = false
    /// Most recent plain-English line the agent narrated via the `say` tool.
    /// SpotlightView reads this so the user sees what the agent is thinking
    /// in normal language, not symbol-prefixed transcript output.
    @Published private(set) var lastSpoken: String?

    private var listeners: [(Event) -> Void] = []

    func subscribe(_ listener: @escaping (Event) -> Void) {
        listeners.append(listener)
    }

    func publish(_ event: Event) {
        switch event {
        case .started:
            isRunning = true
            lastSpoken = nil
        case .said(let message):
            lastSpoken = message
        case .replied(let message):
            isRunning = false
            lastSpoken = message
        case .finished(let summary):
            isRunning = false
            lastSpoken = summary
        case .failed, .stopped:
            isRunning = false
        }
        for listener in listeners { listener(event) }
    }
}
