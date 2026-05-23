import Foundation
import SwiftData

@Model
final class UserPrefs {
    @Attribute(.unique) var id: String
    var redactKeys: Bool
    var localOnly: Bool
    var capturingEnabled: Bool
    var excludePathsRaw: String
    var targetToolsRaw: String
    var apiBaseURL: String
    var apiToken: String
    var firebaseWebAPIKey: String

    // Agent (primary feature)
    var agentEnabled: Bool
    var geminiApiKey: String
    var geminiModel: String
    var activeWorkspace: String
    var confirmEveryAction: Bool
    var autoApproveSafeOnly: Bool
    /// When false, file ops may touch any path (except Redactor-blocked secrets paths).
    var restrictToWorkspace: Bool

    /// Hex color (e.g. "#7B5BFF") used as the seed for the launch animation's
    /// fuzzy blobs and the orb halo. Independent of system accent color.
    var launchColorHex: String

    /// Google Cloud API key for Speech-to-Text and Text-to-Speech. Defaults
    /// to falling back to `geminiApiKey` when empty so a single key gets
    /// users running.
    var googleCloudAPIKey: String

    /// OpenAI API key (sk-…). One paste covers Whisper STT + OpenAI TTS —
    /// the primary voice path for the consumer flow.
    var openAIAPIKey: String = ""

    /// OpenAI TTS voice: alloy / ash / ballad / coral / echo / fable /
    /// nova / onyx / sage / shimmer.
    var openAITTSVoice: String = "alloy"

    /// OpenAI TTS model. Default `gpt-4o-mini-tts`; alternatives `tts-1`,
    /// `tts-1-hd`.
    var openAITTSModel: String = "gpt-4o-mini-tts"

    /// Whether to speak agent finishes via Google Cloud TTS.
    var spokenResponsesEnabled: Bool

    /// Google Cloud TTS voice name (e.g. "en-US-Neural2-F").
    var ttsVoice: String

    /// Gemini-native TTS voice (e.g. "Kore", "Puck", "Zephyr"). Used by the
    /// primary TTS path because it works with a consumer Gemini key.
    var geminiTTSVoice: String

    /// TTS speaking rate, 0.25–4.0; 1.0 is normal.
    var ttsRate: Double

    /// Global hotkey: virtual key code (e.g. 49 = Space) and packed modifier
    /// mask (cmd=1, shift=2, opt=4, ctrl=8). Default: ⌃Space (control + space).
    /// Users change this in Settings → Hotkey.
    var hotkeyKeyCode: Int
    var hotkeyModifiers: Int

    /// Onboarding completion: once true, the first-run flow stops appearing.
    var onboardingComplete: Bool

    /// Agent transcript verbosity: 0 = summary only, 1 = answer + tool count,
    /// 2 = every tool call.
    var transcriptVerbosity: Int

    init(id: String = "default",
         redactKeys: Bool = true,
         localOnly: Bool = false,
         capturingEnabled: Bool = true,
         excludePathsRaw: String = ".env,secrets/,private/,.ssh/",
         targetToolsRaw: String = "claude-code,cursor,chatgpt,claude-desktop",
         apiBaseURL: String = FirebaseConfig.defaultAPIBaseURL,
         apiToken: String = "",
         firebaseWebAPIKey: String = FirebaseConfig.defaultWebAPIKey,
         agentEnabled: Bool = true,
         geminiApiKey: String = "",
         geminiModel: String = GeminiModels.defaultModel,
         activeWorkspace: String = "",
         confirmEveryAction: Bool = false,
         autoApproveSafeOnly: Bool = false,
         restrictToWorkspace: Bool = false,
         launchColorHex: String = "#7B5BFF",
         googleCloudAPIKey: String = "",
         spokenResponsesEnabled: Bool = true,
         ttsVoice: String = "en-US-Neural2-F",
         geminiTTSVoice: String = "Kore",
         ttsRate: Double = 1.0,
         hotkeyKeyCode: Int = 49,        // kVK_Space
         hotkeyModifiers: Int = 4,       // option — ⌃Space is reserved by macOS for input source
         onboardingComplete: Bool = false,
         transcriptVerbosity: Int = 1) {
        self.id = id
        self.redactKeys = redactKeys
        self.localOnly = localOnly
        self.capturingEnabled = capturingEnabled
        self.excludePathsRaw = excludePathsRaw
        self.targetToolsRaw = targetToolsRaw
        self.apiBaseURL = apiBaseURL
        self.apiToken = apiToken
        self.firebaseWebAPIKey = firebaseWebAPIKey
        self.agentEnabled = agentEnabled
        self.geminiApiKey = geminiApiKey
        self.geminiModel = geminiModel
        self.activeWorkspace = activeWorkspace
        self.confirmEveryAction = confirmEveryAction
        self.autoApproveSafeOnly = autoApproveSafeOnly
        self.restrictToWorkspace = restrictToWorkspace
        self.launchColorHex = launchColorHex
        self.googleCloudAPIKey = googleCloudAPIKey
        self.spokenResponsesEnabled = spokenResponsesEnabled
        self.ttsVoice = ttsVoice
        self.geminiTTSVoice = geminiTTSVoice
        self.ttsRate = ttsRate
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.onboardingComplete = onboardingComplete
        self.transcriptVerbosity = transcriptVerbosity
    }

    var excludePaths: [String] {
        excludePathsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var targetTools: [AITool] {
        targetToolsRaw
            .split(separator: ",")
            .compactMap { AITool(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }

    static func defaults() -> UserPrefs { UserPrefs() }

    @MainActor
    static func load(in container: ModelContainer) throws -> UserPrefs {
        let context = container.mainContext
        let descriptor = FetchDescriptor<UserPrefs>()
        if let existing = try context.fetch(descriptor).first {
            if existing.activeWorkspace.isEmpty,
               let path = WorkspaceMonitor.mostRecentEditorWorkspace() {
                existing.activeWorkspace = path
                try? context.save()
            }
            // Seed Gemini key from the user's macOS Keychain if Settings hasn't
            // been filled in yet. Run once: `security add-generic-password
            // -s dev.ithuriel.agent -a gemini.apiKey -w <KEY>`.
            if existing.geminiApiKey.isEmpty,
               let seed = Keychain.get("gemini.apiKey"), !seed.isEmpty {
                existing.geminiApiKey = seed
                try? context.save()
            }
            if existing.openAIAPIKey.isEmpty,
               let seed = Keychain.get("openai.apiKey"), !seed.isEmpty {
                existing.openAIAPIKey = seed
                try? context.save()
            }
            // One-time migration: ⌃Space is reserved by macOS for "Show next
            // input source" and silently swallows our hotkey. Flip existing
            // ⌃Space users to ⌥Space — same finger, no conflict.
            if existing.hotkeyKeyCode == 49 && existing.hotkeyModifiers == 8 {
                existing.hotkeyModifiers = 4   // option
                try? context.save()
            }
            let normalizedModel = GeminiModels.normalize(existing.geminiModel)
            if normalizedModel != existing.geminiModel {
                existing.geminiModel = normalizedModel
                try? context.save()
            }
            return existing
        }
        let seededKey = Keychain.get("gemini.apiKey") ?? ""
        let prefs = UserPrefs(
            geminiApiKey: seededKey,
            activeWorkspace: WorkspaceMonitor.mostRecentEditorWorkspace() ?? ""
        )
        context.insert(prefs)
        try context.save()
        return prefs
    }
}
