import AppKit

/// In-memory cache for album cover images to avoid repeated NFS reads.
final class CoverCache {
    static let shared = CoverCache()

    private var cache: [String: NSImage?] = [:]
    private let lock = NSLock()

    func get(_ folder: String) -> NSImage?? {
        lock.lock()
        defer { lock.unlock() }
        if cache.keys.contains(folder) {
            return cache[folder]
        }
        return nil // not cached yet (different from cached nil)
    }

    func set(_ folder: String, image: NSImage?) {
        lock.lock()
        defer { lock.unlock() }
        cache[folder] = image
    }
}
