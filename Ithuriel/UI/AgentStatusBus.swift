import Foundation

/// Lightweight observer hub so AgentLoop can notify the menu bar + banner +
/// any other UI when a run starts/finishes — without holding references to
/// AppKit windows directly.
@MainActor
final class AgentStatusBus {
    static let shared = AgentStatusBus()
    private init() {}

    enum Event {
        case started(task: String)
        case finished(summary: String)
        case failed(error: String)
        case stopped
    }

    private(set) var isRunning = false
    private var listeners: [(Event) -> Void] = []

    func subscribe(_ listener: @escaping (Event) -> Void) {
        listeners.append(listener)
    }

    func publish(_ event: Event) {
        switch event {
        case .started:  isRunning = true
        case .finished, .failed, .stopped: isRunning = false
        }
        for listener in listeners { listener(event) }
    }
}
