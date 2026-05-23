import Foundation

enum Redactor {
    private static let secretPatterns: [String] = [
        #"sk-[A-Za-z0-9]{20,}"#,
        #"ghp_[A-Za-z0-9]{36}"#,
        #"AIza[0-9A-Za-z\-_]{35}"#,
        #"xoxb-[0-9A-Za-z\-]+"#,
        #"[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]\s*[:=]\s*\S+"#
    ]

    private static let sensitivePathFragments: [String] = [
        ".env", ".ssh/", "secrets/", "private/", "api_key"
    ]

    private static let regexes: [NSRegularExpression] = {
        secretPatterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Redacts secret-like substrings in arbitrary text.
    /// Returns the scrubbed string and the number of replacements made.
    static func redact(text: String) -> (String, Int) {
        var working = text
        var total = 0
        for regex in regexes {
            let range = NSRange(working.startIndex..., in: working)
            let matches = regex.matches(in: working, range: range)
            total += matches.count
            working = regex.stringByReplacingMatches(in: working, range: range, withTemplate: "[REDACTED]")
        }
        return (working, total)
    }

    static func isSensitivePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return sensitivePathFragments.contains { lower.contains($0) }
    }

    /// Scrubs an entire ContextSnapshot, replacing sensitive paths/strings.
    /// Honours per-user excludePaths from prefs.
    static func redact(snapshot: ContextSnapshot, prefs: UserPrefs) -> (ContextSnapshot, Int) {
        var redactions = 0
        let excludes = prefs.excludePaths
        let scrubSecrets = prefs.redactKeys

        func scrub(_ s: String) -> String {
            guard scrubSecrets else { return s }
            let (out, n) = redact(text: s)
            redactions += n
            return out
        }

        func isExcluded(_ path: String) -> Bool {
            if isSensitivePath(path) { return true }
            return excludes.contains { !$0.isEmpty && path.contains($0) }
        }

        let cleanFiles = snapshot.activeFiles.filter { !isExcluded($0) }
        if cleanFiles.count < snapshot.activeFiles.count {
            redactions += (snapshot.activeFiles.count - cleanFiles.count)
        }

        let cleanEdits = snapshot.recentEdits
            .filter { !isExcluded($0.path) }
            .map { edit in
                ContextSnapshot.EditRecord(
                    path: edit.path,
                    linesAdded: edit.linesAdded,
                    linesRemoved: edit.linesRemoved,
                    summary: scrub(edit.summary)
                )
            }
        if cleanEdits.count < snapshot.recentEdits.count {
            redactions += (snapshot.recentEdits.count - cleanEdits.count)
        }

        let cleanHistory = snapshot.terminalHistory.map(scrub)

        var cleanGit: GitState? = nil
        if let g = snapshot.gitState {
            cleanGit = GitState(
                branch: g.branch,
                lastCommit: scrub(g.lastCommit),
                changedFiles: g.changedFiles.filter { !isExcluded($0) },
                diffSummary: scrub(g.diffSummary),
                recentCommits: g.recentCommits.map(scrub)
            )
        }

        let cleaned = ContextSnapshot(
            id: snapshot.id,
            capturedAt: snapshot.capturedAt,
            source: snapshot.source,
            workspacePath: snapshot.workspacePath,
            gitState: cleanGit,
            recentEdits: cleanEdits,
            terminalHistory: cleanHistory,
            activeFiles: cleanFiles
        )
        return (cleaned, redactions)
    }
}
