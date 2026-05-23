import Foundation
import AppKit
import ApplicationServices

enum AppDetector {
    /// Bundle identifiers we are willing to type into automatically.
    /// All others get clipboard-only injection regardless of user setting.
    private static let typeInjectAllowlist: Set<String> = [
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.openai.chat",                // ChatGPT desktop
        "com.anthropic.claudefordesktop"  // Claude desktop
    ]

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func currentFrontmostTool() -> AITool {
        guard let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return .unknown }
        return AITool.from(bundleId: bundle)
    }

    static func canTypeInject(into tool: AITool) -> Bool {
        guard isAccessibilityTrusted else { return false }
        let ids = tool.bundleIdentifiers
        return ids.contains { typeInjectAllowlist.contains($0) }
    }
}
