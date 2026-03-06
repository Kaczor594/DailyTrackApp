import Foundation

/// Provides access to the shared App Group container for data sharing between the main app and widget extension.
enum AppGroupContainer {
    static let appGroupIdentifier = "group.com.kaczor594.DailyTrack"

    /// URL to the shared container directory.
    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            fatalError("App Group container not found. Ensure App Groups capability is configured.")
        }
        return url
    }

    /// URL to the shared SwiftData database.
    static var databaseURL: URL {
        containerURL.appendingPathComponent("DailyTrack.store")
    }

    /// Migrates existing SwiftData store to the shared container if needed.
    /// Call this on first launch after adding App Groups.
    static func migrateExistingStoreIfNeeded() {
        let fileManager = FileManager.default

        // Default SwiftData location in Application Support
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let defaultStoreURL = appSupport.appendingPathComponent("default.store")
        let sharedStoreURL = databaseURL

        // If shared store already exists, no migration needed
        guard !fileManager.fileExists(atPath: sharedStoreURL.path) else {
            return
        }

        // If default store exists, copy it to shared container
        if fileManager.fileExists(atPath: defaultStoreURL.path) {
            do {
                // Create shared container directory if needed
                try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)

                // Copy the store file
                try fileManager.copyItem(at: defaultStoreURL, to: sharedStoreURL)

                // Also copy the -wal and -shm files if they exist
                let walURL = defaultStoreURL.appendingPathExtension("wal")
                let shmURL = defaultStoreURL.appendingPathExtension("shm")

                if fileManager.fileExists(atPath: walURL.path) {
                    try fileManager.copyItem(at: walURL, to: sharedStoreURL.appendingPathExtension("wal"))
                }
                if fileManager.fileExists(atPath: shmURL.path) {
                    try fileManager.copyItem(at: shmURL, to: sharedStoreURL.appendingPathExtension("shm"))
                }

                print("Successfully migrated SwiftData store to App Group container")
            } catch {
                print("Failed to migrate SwiftData store: \(error)")
            }
        }
    }
}
