import Foundation
import CoreServices

actor FileWatcher {
    typealias ChangeHandler = ([String]) -> Void

    private var stream: FSEventStreamRef?
    private var watchedPath: String?
    private let debounce: TimeInterval
    private var pending: Set<String> = []
    private var debounceTask: Task<Void, Never>?
    private var onChange: ChangeHandler?

    init(debounceSeconds: TimeInterval) {
        self.debounce = debounceSeconds
    }

    func setOnChange(_ handler: @escaping ChangeHandler) {
        self.onChange = handler
    }

    func watch(path: String) {
        stopStreamLocked()

        let pathsToWatch = [path] as CFArray
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)

        let flags: FSEventStreamCreateFlags = UInt32(kFSEventStreamCreateFlagFileEvents |
                                                     kFSEventStreamCreateFlagNoDefer |
                                                     kFSEventStreamCreateFlagUseCFTypes)

        guard let s = FSEventStreamCreate(kCFAllocatorDefault,
                                          FileWatcher.fsCallback,
                                          &context,
                                          pathsToWatch,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          0.5,
                                          flags) else {
            Log.error("FSEventStreamCreate failed for path \(path)")
            return
        }

        FSEventStreamSetDispatchQueue(s, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(s)
        self.stream = s
        self.watchedPath = path
        Log.info("FileWatcher started for \(path)")
    }

    func stop() {
        stopStreamLocked()
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func stopStreamLocked() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
        watchedPath = nil
    }

    fileprivate func enqueue(paths: [String]) {
        for p in paths where FileWatcher.shouldKeep(path: p) {
            pending.insert(p)
        }
        scheduleDebounce()
    }

    private func scheduleDebounce() {
        debounceTask?.cancel()
        let interval = debounce
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.flush()
        }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        let snapshot = Array(pending)
        pending.removeAll(keepingCapacity: true)
        onChange?(snapshot)
    }

    private static func shouldKeep(path: String) -> Bool {
        // Filter out noise: .git internals, node_modules, build artifacts, swap files.
        let ignored = ["/.git/", "/node_modules/", "/.build/", "/DerivedData/", "/.next/", "/dist/"]
        if ignored.contains(where: { path.contains($0) }) { return false }
        let lower = (path as NSString).lastPathComponent.lowercased()
        if lower.hasPrefix(".") && lower.hasSuffix(".swp") { return false }
        if lower == ".ds_store" { return false }
        return true
    }

    private static let fsCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
        guard let info = info else { return }
        let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
        guard let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else { return }
        let paths = Array(cfPaths.prefix(numEvents))
        Task { await watcher.enqueue(paths: paths) }
    }
}
