import Foundation

struct GitState: Codable, Sendable {
    let branch: String
    let lastCommit: String
    let changedFiles: [String]
    let diffSummary: String
    let recentCommits: [String]
}

enum GitCapture {
    static func capture(at path: String) async -> GitState? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: path)
        var foundRoot: URL?
        for _ in 0..<8 {
            let gitDir = dir.appendingPathComponent(".git")
            if fm.fileExists(atPath: gitDir.path) {
                foundRoot = dir
                break
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        guard let root = foundRoot else { return nil }

        async let branch = run(["branch", "--show-current"], cwd: root.path)
        async let status = run(["status", "--short"], cwd: root.path)
        async let lastCommit = run(["log", "-1", "--pretty=%H %s"], cwd: root.path)
        async let log = run(["log", "--oneline", "-10"], cwd: root.path)
        async let diff = run(["diff", "--stat"], cwd: root.path)

        let branchOut = (await branch).trimmingCharacters(in: .whitespacesAndNewlines)
        let statusOut = await status
        let lastCommitOut = (await lastCommit).trimmingCharacters(in: .whitespacesAndNewlines)
        let logOut = await log
        let diffOut = (await diff).trimmingCharacters(in: .whitespacesAndNewlines)

        let changed = statusOut
            .split(separator: "\n")
            .compactMap { line -> String? in
                let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2 else { return nil }
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }

        let commits = logOut.split(separator: "\n").map(String.init)

        return GitState(
            branch: branchOut.isEmpty ? "(detached)" : branchOut,
            lastCommit: lastCommitOut,
            changedFiles: changed,
            diffSummary: diffOut,
            recentCommits: commits
        )
    }

    @discardableResult
    private static func run(_ args: [String], cwd: String) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.launchPath = "/usr/bin/env"
                process.arguments = ["git"] + args
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    cont.resume(returning: "")
                    return
                }
                process.waitUntilExit()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}
