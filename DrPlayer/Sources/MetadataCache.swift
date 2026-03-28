import Foundation

/// Generic disk cache for API responses. TTL-based expiration.
enum MetadataCache {

    private static let cacheDir: String = {
        let dir = NSHomeDirectory() + "/.drplayer/metadata"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Default TTL: 30 days
    static let defaultTTL: TimeInterval = 30 * 24 * 3600

    /// Get cached data for a key. Returns nil if missing or expired.
    static func get(_ key: String, ttl: TimeInterval = defaultTTL) -> Data? {
        let path = filePath(for: key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date else { return nil }

        // Check TTL
        if Date().timeIntervalSince(modified) > ttl { return nil }

        return FileManager.default.contents(atPath: path)
    }

    /// Get cached string
    static func getString(_ key: String, ttl: TimeInterval = defaultTTL) -> String? {
        guard let data = get(key, ttl: ttl) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Store data
    static func set(_ key: String, data: Data) {
        let path = filePath(for: key)
        try? data.write(to: URL(fileURLWithPath: path))
    }

    /// Store string
    static func setString(_ key: String, value: String) {
        set(key, data: value.data(using: .utf8) ?? Data())
    }

    /// Store a dictionary as JSON
    static func setJSON(_ key: String, value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value) {
            set(key, data: data)
        }
    }

    /// Get cached dictionary from JSON
    static func getJSON(_ key: String, ttl: TimeInterval = defaultTTL) -> [String: Any]? {
        guard let data = get(key, ttl: ttl) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Helpers

    private static func filePath(for key: String) -> String {
        "\(cacheDir)/\(hash(key)).cache"
    }

    private static func hash(_ s: String) -> String {
        var h: UInt64 = 5381
        for byte in s.utf8 { h = h &* 33 &+ UInt64(byte) }
        return String(h, radix: 16)
    }
}
