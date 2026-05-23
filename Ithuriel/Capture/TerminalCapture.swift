import Foundation

enum TerminalCapture {
    /// Reads recent shell history from $HISTFILE / common fallbacks.
    /// We never read closed-session history beyond what's already on disk.
    static func recentCommands(limit: Int = 20) async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .utility).async {
                let candidates = candidateHistoryFiles()
                for url in candidates {
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    let lines = text
                        .split(separator: "\n", omittingEmptySubsequences: true)
                        .map { stripZshTimestamp(String($0)) }
                        .filter { !$0.isEmpty }
                    let tail = Array(lines.suffix(limit))
                    if !tail.isEmpty {
                        cont.resume(returning: tail)
                        return
                    }
                }
                cont.resume(returning: [])
            }
        }
    }

    private static func candidateHistoryFiles() -> [URL] {
        let env = ProcessInfo.processInfo.environment
        var urls: [URL] = []
        if let hist = env["HISTFILE"], !hist.isEmpty {
            urls.append(URL(fileURLWithPath: (hist as NSString).expandingTildeInPath))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        urls.append(home.appendingPathComponent(".zsh_history"))
        urls.append(home.appendingPathComponent(".bash_history"))
        urls.append(home.appendingPathComponent(".local/share/fish/fish_history"))
        return urls
    }

    /// Zsh extended history lines look like `: 1700000000:0;ls -la`. Strip the prefix.
    private static func stripZshTimestamp(_ line: String) -> String {
        if line.hasPrefix(": "),
           let semi = line.firstIndex(of: ";") {
            return String(line[line.index(after: semi)...])
        }
        return line
    }
}
