import AppKit
import Foundation

/// Fetches and caches artist avatar images from Wikipedia and Last.fm.
enum ArtistAvatarService {

    private static let cacheDir: String = {
        let dir = NSHomeDirectory() + "/.drplayer/artist-avatars"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Returns cached avatar or fetches from Wikipedia/Last.fm.
    static func avatar(for artistName: String) async -> NSImage? {
        let key = cacheKey(artistName)

        // Check disk cache
        if let cached = loadCached(key: key) { return cached }

        // Check if marked as not found
        if isMarkedNotFound(key: key) { return nil }

        // Try Wikipedia thumbnail first (best quality)
        let searchName = WikipediaService.artistSearchQueries(artistName).first ?? artistName
        if let wiki = await WikipediaService.searchArtist(name: artistName),
           let urlStr = wiki.thumbnailURL,
           let url = URL(string: urlStr),
           let image = await fetchImage(url: url) {
            saveCached(key: key, image: image)
            return image
        }

        // Fallback to Last.fm
        if let lfm = await LastFMService.fetchArtist(name: searchName),
           let urlStr = lfm.imageURL, !urlStr.isEmpty,
           let url = URL(string: urlStr),
           let image = await fetchImage(url: url) {
            saveCached(key: key, image: image)
            return image
        }

        // Mark as not found so we don't retry
        markNotFound(key: key)
        return nil
    }

    // MARK: - Cache

    private static func cacheKey(_ name: String) -> String {
        let normalized = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return String(normalized.prefix(80))
    }

    private static func loadCached(key: String) -> NSImage? {
        let path = "\(cacheDir)/\(key).jpg"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return NSImage(data: data)
    }

    private static func saveCached(key: String, image: NSImage) {
        let path = "\(cacheDir)/\(key).jpg"
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return }
        try? jpg.write(to: URL(fileURLWithPath: path))
    }

    private static func isMarkedNotFound(key: String) -> Bool {
        FileManager.default.fileExists(atPath: "\(cacheDir)/\(key).notfound")
    }

    private static func markNotFound(key: String) {
        let path = "\(cacheDir)/\(key).notfound"
        FileManager.default.createFile(atPath: path, contents: nil)
    }

    private static func fetchImage(url: URL) async -> NSImage? {
        var request = URLRequest(url: url)
        request.setValue("DrPlayer/1.0 (music player; contact@drplayer.app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }
}
