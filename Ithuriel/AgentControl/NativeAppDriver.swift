import Foundation
import AppKit

/// High-level helpers that drive native Apple apps via AppleScript,
/// so the agent can open pages in Safari, draft emails, add calendar events,
/// create notes, and open files without fumbling through pixel-level clicks.
///
/// All methods throw `NativeAppDriver.Failure` on AppleScript error so the
/// agent loop surfaces the error to Gemini, which can then ask the user to
/// grant Automation permission for the target app if needed.
enum NativeAppDriver {
    enum Failure: Error, CustomStringConvertible {
        case appleScript(String)
        case notSupported

        var description: String {
            switch self {
            case .appleScript(let msg): return "AppleScript error: \(msg)"
            case .notSupported: return "Operation not supported on this system."
            }
        }
    }

    /// Open a URL in Safari. If Safari isn't the user's default browser,
    /// NSWorkspace.shared.open still routes to the system default.
    static func openInSafari(url: String) async throws {
        let script = """
        tell application "Safari"
            activate
            if (count of windows) = 0 then
                make new document with properties {URL:"\(escape(url))"}
            else
                tell front window to set URL of current tab to "\(escape(url))"
            end if
        end tell
        """
        try await runAppleScript(script)
    }

    /// Compose a new outgoing email draft in Mail.app. Leaves the draft window
    /// open so the user can review and send.
    static func composeEmail(to: String, subject: String, body: String) async throws {
        let script = """
        tell application "Mail"
            activate
            set newMsg to make new outgoing message with properties {subject:"\(escape(subject))", content:"\(escape(body))", visible:true}
            tell newMsg to make new to recipient with properties {address:"\(escape(to))"}
        end tell
        """
        try await runAppleScript(script)
    }

    /// Add an event to the first calendar in Calendar.app.
    /// `offsetMinutes` shifts the start time from now; `durationMinutes` sets the length.
    static func addCalendarEvent(title: String, offsetMinutes: Int = 0, durationMinutes: Int = 60) async throws {
        let script = """
        tell application "Calendar"
            tell first calendar
                make new event with properties {summary:"\(escape(title))", start date:(current date) + \(offsetMinutes) * minutes, end date:(current date) + \(offsetMinutes + durationMinutes) * minutes}
            end tell
            activate
        end tell
        """
        try await runAppleScript(script)
    }

    /// Add a note to the iCloud account in Notes.app.
    static func addNote(title: String, body: String) async throws {
        let script = """
        tell application "Notes"
            tell account "iCloud"
                make new note with properties {name:"\(escape(title))", body:"\(escape(body))"}
            end tell
            activate
        end tell
        """
        try await runAppleScript(script)
    }

    /// Open a file with its default app, or with a specific app by bundle identifier.
    static func openFile(path: String, bundleId: String? = nil) async throws {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if let bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            try await NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                              configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private helpers

    private static func runAppleScript(_ source: String) async throws {
        if HackathonConfig.skipPermissionPrompts {
            throw Failure.notSupported
        }
        // NSAppleScript must run on a thread that has a run loop; detached task satisfies that.
        try await Task.detached(priority: .userInitiated) {
            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                throw Failure.appleScript("could not compile script")
            }
            script.executeAndReturnError(&errorInfo)
            if let err = errorInfo {
                throw Failure.appleScript(err.description)
            }
        }.value
    }

    /// Escape a string for safe embedding inside an AppleScript double-quoted literal.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: " ")
    }
}
