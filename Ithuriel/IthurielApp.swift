import SwiftUI
import AppKit
import SwiftData
import ApplicationServices

#if DEBUG
let kIthurielDebug = true
#else
let kIthurielDebug = false
#endif

@main
struct IthurielApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .modelContainer(for: [UserPrefs.self, CachedSnapshot.self])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private var workspaceMonitor: WorkspaceMonitor?
    private var fileWatcher: FileWatcher?
    private var captureTimer: Timer?
    private(set) var modelContainer: ModelContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            modelContainer = try ModelContainer(for: UserPrefs.self, CachedSnapshot.self)
        } catch {
            Log.error("Failed to initialize SwiftData container: \(error)")
        }

        menuBarManager = MenuBarManager(container: modelContainer)
        menuBarManager?.install()

        requestAccessibilityIfNeeded()

        let monitor = WorkspaceMonitor(container: modelContainer)
        monitor.start()
        workspaceMonitor = monitor

        let watcher = FileWatcher(debounceSeconds: 5)
        fileWatcher = watcher
        Task { await watcher.setOnChange { [weak self] changed in
            self?.handleFileChanges(changed)
        }}

        if let initialPath = WorkspaceMonitor.mostRecentEditorWorkspace() {
            Task { await watcher.watch(path: initialPath) }
        }

        captureTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.runPeriodicCapture(reason: .timer) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureTimer?.invalidate()
        Task { await fileWatcher?.stop() }
        workspaceMonitor?.stop()
    }

    private func requestAccessibilityIfNeeded() {
        let opts: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(opts as CFDictionary)
        if !trusted {
            Log.info("Accessibility permission not yet granted. Injection features disabled until granted.")
            menuBarManager?.setAccessibilityState(granted: false)
        } else {
            menuBarManager?.setAccessibilityState(granted: true)
        }
    }

    private func handleFileChanges(_ changed: [String]) {
        Log.debug("File changes (\(changed.count)) — triggering capture")
        Task { await runPeriodicCapture(reason: .fileChange(changed)) }
    }

    enum CaptureReason {
        case timer
        case fileChange([String])
        case appFocus(AITool)
    }

    func runPeriodicCapture(reason: CaptureReason) async {
        guard let container = modelContainer else { return }
        let prefs = (try? UserPrefs.load(in: container)) ?? UserPrefs.defaults()

        let workspacePath = WorkspaceMonitor.mostRecentEditorWorkspace() ?? FileManager.default.homeDirectoryForCurrentUser.path
        let git = await GitCapture.capture(at: workspacePath)
        let terminal = await TerminalCapture.recentCommands(limit: 20)

        var changed: [String] = []
        if case .fileChange(let files) = reason { changed = files }

        let raw = ContextSnapshot(
            id: UUID(),
            capturedAt: Date(),
            source: SnapshotSource.detect(for: workspacePath),
            workspacePath: workspacePath,
            gitState: git,
            recentEdits: changed.map { ContextSnapshot.EditRecord(path: $0, linesAdded: 0, linesRemoved: 0, summary: "modified") },
            terminalHistory: terminal,
            activeFiles: WorkspaceMonitor.openFiles(in: workspacePath)
        )

        let (redacted, redactionCount) = Redactor.redact(snapshot: raw, prefs: prefs)
        Log.debug("Capture: source=\(redacted.source.rawValue) edits=\(redacted.recentEdits.count) redactions=\(redactionCount)")

        await CachedSnapshot.persist(redacted, in: container)

        if prefs.localOnly {
            Log.debug("Local-only mode: skipping network upload")
            return
        }

        if kIthurielDebug {
            Log.debug("DEBUG flag — skipping POST, snapshot logged only")
            return
        }

        let client = IthurielClient(prefs: prefs)
        do {
            try await client.postSnapshot(redacted)
        } catch {
            Log.error("Snapshot upload failed: \(error). Will retry on next capture.")
        }
    }
}

enum Log {
    static func debug(_ message: @autoclosure () -> String) {
        if kIthurielDebug { print("[Ithuriel.debug] \(message())") }
    }
    static func info(_ message: @autoclosure () -> String) {
        print("[Ithuriel.info]  \(message())")
    }
    static func error(_ message: @autoclosure () -> String) {
        print("[Ithuriel.error] \(message())")
    }
}
