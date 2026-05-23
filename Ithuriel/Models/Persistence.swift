import Foundation
import SwiftData

/// Creates the app's SwiftData store with recovery when schema drift breaks
/// an existing on-disk database (e.g. after adding a new @Model property).
enum Persistence {
    private static let schema = Schema([UserPrefs.self, CachedSnapshot.self, SavedAgentRun.self])

    static func makeContainer() -> ModelContainer {
        let persistent = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = openContainer(configuration: persistent) {
            return container
        }

        Log.error("SwiftData persistent store failed — resetting local store and retrying")
        resetPersistentStoreFiles()
        if let container = openContainer(configuration: persistent) {
            Log.info("SwiftData store recreated successfully")
            return container
        }

        Log.error("SwiftData persistent store still unavailable — using in-memory store")
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [memory])
        } catch {
            fatalError("SwiftData in-memory store failed: \(error)")
        }
    }

    private static func openContainer(configuration: ModelConfiguration) -> ModelContainer? {
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            Log.error("SwiftData open failed: \(error)")
            return nil
        }
    }

    private static func resetPersistentStoreFiles() {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let storeURL = config.url
        let directory = storeURL.deletingLastPathComponent()
        let prefix = storeURL.lastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return
        }
        for name in names where name.hasPrefix(prefix) {
            let url = directory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
            Log.info("Removed stale SwiftData file: \(name)")
        }
    }
}
