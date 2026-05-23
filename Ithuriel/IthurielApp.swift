import SwiftUI
import AppKit
import SwiftData
import ApplicationServices
import FirebaseCore

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
            if let container = appDelegate.modelContainer {
                SettingsView()
                    .modelContainer(container)
            } else {
                SettingsView()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var workspaceMonitor: WorkspaceMonitor?
    private var fileWatcher: FileWatcher?
    private var captureTimer: Timer?
    private(set) var modelContainer: ModelContainer?
    private(set) var agentLoop: AgentLoop?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Initialize Firebase from the bundled GoogleService-Info.plist
        // BEFORE anything that might want to talk to the project (AuthService,
        // DirectFirestoreClient, IthurielClient fallbacks).
        if FirebaseApp.app() == nil { FirebaseApp.configure() }

        let container = Persistence.makeContainer()
        modelContainer = container

        let loop = AgentLoop(container: container)
        agentLoop = loop
        AppRouter.shared.wire(container: container, agentLoop: loop)

        KillSwitch.shared.install()
        URLSchemeHandler.shared.install()
        SpotlightCoordinator.shared.configure(container: container, agentLoop: loop)
        ChatWindowController.shared.configure(container: container, agent: loop)
        VoiceController.shared.configure(container: container, agentLoop: loop)
        SpotlightCoordinator.shared.installSummonHotkey()

        // Seed the hotkey binding from saved prefs (defaults to ⌃Space).
        Task { @MainActor in
            if let prefs = try? UserPrefs.load(in: container) {
                HotkeyMonitor.shared.updateBinding(
                    keyCode: prefs.hotkeyKeyCode,
                    modifiers: prefs.hotkeyModifiers
                )
            }
        }

        // Apple-Intelligence-style screen-edge glow while voice hotkey is held.
        let prev = HotkeyMonitor.shared.onVoiceStart
        HotkeyMonitor.shared.onVoiceStart = {
            Task { @MainActor in
                EdgeGlowController.shared.show()
                prev()
            }
        }
        let prevEnd = HotkeyMonitor.shared.onVoiceEnd
        HotkeyMonitor.shared.onVoiceEnd = {
            Task { @MainActor in
                EdgeGlowController.shared.hide()
                prevEnd()
            }
        }

        // Done/Failed/Stopped banner responds to bus events.
        AgentStatusBus.shared.subscribe { event in
            Task { @MainActor in
                switch event {
                case .started, .said:
                    // Live narration — surfaced inside SpotlightView via the
                    // bus's @Published lastSpoken. No banner or status flip.
                    break
                case .finished(let summary):
                    DoneBannerController.shared.showFinished(summary: summary)
                case .failed(let err):
                    DoneBannerController.shared.showFailed(summary: err)
                case .stopped:
                    DoneBannerController.shared.showStopped(summary: "Stopped")
                }
            }
        }

        refreshPermissionState()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPermissionState()
        }

        // Sequence: blob backdrop blooms in → orb assembles centre-screen →
        // if first run, the orb shrinks into the onboarding header while the
        // backdrop dims and the onboarding glass fades in over it; on
        // onboarding finish, both launch surfaces fade out and the chat
        // window appears. Otherwise the orb fades and the chat window opens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task { @MainActor in
                let needsOnboarding: Bool = {
                    if let prefs = try? UserPrefs.load(in: container) {
                        return prefs.onboardingComplete == false
                    }
                    return true
                }()

                if needsOnboarding {
                    OnboardingCoordinator.shared.onFinish = {
                        Task { @MainActor in
                            SpotlightCoordinator.shared.fadeOutLaunchSurfaces {
                                ChatWindowController.shared.show(container: container, agent: loop)
                            }
                        }
                    }
                    SpotlightCoordinator.shared.playLaunchThenSummon(onAssembled: {
                        Task { @MainActor in
                            SpotlightCoordinator.shared.handoffToOnboarding(container: container)
                        }
                    })
                } else {
                    // No onboarding: orb fades into the chat window as before.
                    SpotlightCoordinator.shared.playLaunchThenSummon()
                    // playLaunchThenSummon's default path opens the chat
                    // window via dismissLaunch → ChatWindowController.toggle.
                    // We don't need an explicit show() here.
                }
            }
        }

        let monitor = WorkspaceMonitor(container: container)
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

    private func refreshPermissionState() {
        Task { @MainActor in
            await PermissionsManager.shared.refresh()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let container = modelContainer, let loop = agentLoop else { return true }
        if !flag {
            ChatWindowController.shared.show(container: container, agent: loop)
        }
        return true
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

    @MainActor
    func runPeriodicCapture(reason: CaptureReason) async {
        guard let container = modelContainer else { return }
        let prefs = (try? UserPrefs.load(in: container)) ?? UserPrefs.defaults()
        guard prefs.capturingEnabled else {
            Log.debug("Capture disabled in Settings — skipping")
            return
        }

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
