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
        NSApp.setActivationPolicy(.regular)

        if !HackathonConfig.skipPermissionPrompts {
            AuthService.shared.bootstrap(silent: true)
        }

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
        LaunchCoordinator.shared.configure(container: container)
        ChatWindowController.shared.configure(container: container, agent: loop)
        InstantChatController.shared.configure(container: container, agent: loop)
        VoiceController.shared.configure(container: container, agentLoop: loop)
        AgentControlBorderOverlay.shared.configure(agentLoop: loop)

        // Seed hotkey binding, refresh permissions, then install the event tap
        // so we don't prompt when Accessibility is already granted.
        Task { @MainActor in
            if let prefs = try? UserPrefs.load(in: container) {
                HotkeyMonitor.shared.updateBinding(
                    keyCode: prefs.hotkeyKeyCode,
                    modifiers: prefs.hotkeyModifiers
                )
            }
            if !HackathonConfig.skipPermissionPrompts {
                await PermissionsManager.shared.refresh(force: true)
            }
            self.installGlobalHotkey()
        }

        if !HackathonConfig.skipPermissionPrompts {
            scheduleDeferredCloudSync(container: container)
        }

        // Done/Failed/Stopped banner responds to bus events.
        AgentStatusBus.shared.subscribe { event in
            Task { @MainActor in
                switch event {
                case .started, .said, .replied:
                    break
                case .captured(let workspace):
                    let hex = (try? UserPrefs.load(in: container))?.launchColorHex ?? "#7B5BFF"
                    CapturePillController.shared.flash(workspace: workspace, accentHex: hex)
                case .finished(let summary):
                    DoneBannerController.shared.showFinished(summary: summary)
                case .failed(let err):
                    DoneBannerController.shared.showFailed(summary: err)
                case .stopped:
                    DoneBannerController.shared.showStopped(summary: "Stopped")
                }
            }
        }

        // Sequence: launch animation → onboarding (only on first run) →
        // chat window. The chat window is the primary surface, but we keep
        // it off-screen until onboarding completes so the user isn't seeing
        // two windows fight for focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task { @MainActor in
                LaunchCoordinator.shared.playLaunchAnimation()

                let needsOnboarding: Bool = {
                    if let prefs = try? UserPrefs.load(in: container) {
                        return prefs.onboardingComplete == false
                    }
                    return true
                }()

                // Wait for the orb sequence to finish before opening any
                // window so the animation isn't covered.
                try? await Task.sleep(nanoseconds: 1_900_000_000)

                await LaunchCoordinator.shared.dismissAndWait()

                if needsOnboarding {
                    OnboardingCoordinator.shared.onFinish = {
                        Task { @MainActor in
                            ChatWindowController.shared.show(container: container, agent: loop)
                        }
                    }
                    OnboardingCoordinator.shared.present(container: container)
                    AppForeground.activate(bringing: OnboardingCoordinator.shared.mainWindow)
                } else {
                    ChatWindowController.shared.show(container: container, agent: loop)
                    AppForeground.activate(bringing: ChatWindowController.shared.keyWindow)
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

    /// Pull remote prefs + cloud secrets after the UI is visible.
    @MainActor
    private func scheduleDeferredCloudSync(container: ModelContainer) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard AuthService.shared.isSignedIn else { return }
            await PrefsSync.shared.pullRemote(container: container)
            if let prefs = try? UserPrefs.load(in: container) {
                await SecretManagerClient.shared.sync(into: prefs) {
                    try? container.mainContext.save()
                }
            }
        }
    }

    /// ⌃Space (or user-configured chord): tap opens chat, hold starts voice.
    @MainActor
    private func installGlobalHotkey() {
        let monitor = HotkeyMonitor.shared
        monitor.onHotkeyTap = {
            Task { @MainActor in
                InstantChatController.shared.toggle()
            }
        }
        monitor.onVoiceStart = { Task { @MainActor in _ = await VoiceController.shared.start() } }
        monitor.onVoiceEnd   = { Task { @MainActor in VoiceController.shared.stopAndSubmit() } }
        monitor.install()

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

        // Compute a 768-d Gemini embedding for this snapshot when the user
        // has a key configured. The vector is persisted alongside the cached
        // payload so it survives restarts, and pushed straight to Firestore
        // as a native `vectorValue` so the existing composite index matches.
        var embedding: [Float] = []
        if !prefs.geminiApiKey.isEmpty {
            let text = Self.snapshotEmbeddingText(redacted)
            do {
                embedding = try await GeminiEmbed.embed(
                    text: text,
                    apiKey: prefs.geminiApiKey,
                    dimensions: 768,
                    taskType: .retrievalDocument
                )
            } catch {
                Log.error("Snapshot embedding failed: \(error). Continuing without vector.")
            }
        }

        await CachedSnapshot.persist(redacted, in: container, embedding: embedding)

        if prefs.localOnly {
            Log.debug("Local-only mode: skipping network upload")
            return
        }

        // Push the snapshot + embedding directly to Firestore under
        // users/{uid}/snapshots/{id}. This is independent of the Cloud Run
        // Pub/Sub pipeline — if the user is signed in and we computed a
        // vector, the local path lands a document with `embedding` set.
        if !embedding.isEmpty, AuthService.shared.isSignedIn {
            if let uid = await Self.currentFirebaseUID() {
                do {
                    try await DirectFirestoreClient.shared.writeSnapshotWithEmbedding(
                        redacted, embedding: embedding, userId: uid
                    )
                } catch {
                    Log.error("Direct vector upsert failed: \(error)")
                }
            }
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

    /// Compact text representation of a snapshot used as the embedding
    /// input. Capped around ~2000 chars so we stay well inside Gemini's
    /// per-request limit while still carrying enough signal (workspace,
    /// branch, last commit, changed files, recent terminal commands).
    static func snapshotEmbeddingText(_ s: ContextSnapshot) -> String {
        var lines: [String] = []
        lines.append("workspace: \(s.workspacePath)")
        if let g = s.gitState {
            lines.append("branch: \(g.branch)")
            lines.append("last commit: \(g.lastCommit)")
            let files = g.changedFiles.prefix(5).joined(separator: ", ")
            if !files.isEmpty { lines.append("changed files: \(files)") }
        }
        if !s.recentEdits.isEmpty {
            let edits = s.recentEdits.prefix(5).map { ($0.path as NSString).lastPathComponent }
            lines.append("recent edits: \(edits.joined(separator: ", "))")
        }
        if !s.terminalHistory.isEmpty {
            let cmds = s.terminalHistory.suffix(5).joined(separator: " | ")
            lines.append("recent shell: \(cmds)")
        }
        let joined = lines.joined(separator: "\n")
        if joined.count <= 2000 { return joined }
        return String(joined.prefix(2000))
    }

    /// Decodes the Firebase uid (sub claim) from the current ID token —
    /// same trick `IthurielClient` uses to avoid pulling in a JWT lib.
    static func currentFirebaseUID() async -> String? {
        guard AuthService.shared.isSignedIn,
              let token = try? await AuthService.shared.refreshIfNeeded() else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        while payload.count % 4 != 0 { payload.append("=") }
        payload = payload.replacingOccurrences(of: "-", with: "+")
                         .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["user_id"] as? String) ?? (json["sub"] as? String)
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
