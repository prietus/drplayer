import AppKit
import Foundation

/// Downloads cover art from Discogs (pressing-specific) or Cover Art Archive (generic).
/// Caches downloaded images to disk.
enum CoverArtService {

    private static let cacheDir: String = {
        let dir = NSHomeDirectory() + "/.drplayer/covers"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Try to download cover for an album. Priority:
    /// 1. Discogs (pressing-specific: Japanese obi, special editions, etc.)
    /// 2. Cover Art Archive via MusicBrainz album ID
    /// Returns the local file path if successful.
    static func downloadCover(for album: Album) async -> NSImage? {
        // Check disk cache first
        let cacheKey = cacheKey(artist: album.artist, album: album.title)
        if let cached = loadCachedImage(key: cacheKey) {
            return cached
        }

        // Check if marked as not found
        if isMarkedNotFound(key: cacheKey) { return nil }

        var imageData: Data?

        // 1. Discogs: pressing-specific cover (best for special editions)
        if !AppSettings.shared.discogsKey.isEmpty {
            imageData = await fetchDiscogsImage(for: album)
        }

        // 2. Cover Art Archive: by MusicBrainz album ID
        if imageData == nil && !album.musicbrainzAlbumId.isEmpty {
            imageData = await fetchCoverArtArchive(releaseId: album.musicbrainzAlbumId)
        }

        // 3. Cover Art Archive: search by name if no ID
        if imageData == nil {
            imageData = await fetchCoverArtBySearch(artist: album.artist, album: album.title)
        }

        guard let data = imageData, let image = NSImage(data: data) else {
            markNotFound(key: cacheKey)
            return nil
        }

        // Save to disk cache
        saveCachedImage(key: cacheKey, data: data)
        return image
    }

    // MARK: - Discogs

    private static func fetchDiscogsImage(for album: Album) async -> Data? {
        // Search Discogs for this specific release
        let discogs: DiscogsRelease?
        // Try catalog number from MusicBrainz first
        if let catno = await getCatalogNumber(for: album), !catno.isEmpty {
            discogs = await DiscogsService.searchByCatalog(catno)
        } else {
            let cleanTitle = cleanAlbumTitle(album.title)
            discogs = await DiscogsService.search(artist: album.artist, album: cleanTitle)
        }

        guard let dg = discogs, let imgURL = dg.imageURL, let url = URL(string: imgURL) else {
            return nil
        }

        return await fetchImageData(url: url)
    }

    private static func getCatalogNumber(for album: Album) async -> String? {
        if !album.musicbrainzAlbumId.isEmpty {
            if let release = await MusicBrainzService.fetchRelease(id: album.musicbrainzAlbumId) {
                return release.catalogNumber
            }
        }
        return nil
    }

    // MARK: - Cover Art Archive

    private static func fetchCoverArtArchive(releaseId: String) async -> Data? {
        let urlStr = "https://coverartarchive.org/release/\(releaseId)/front"
        guard let url = URL(string: urlStr) else { return nil }
        return await fetchImageData(url: url)
    }

    private static func fetchCoverArtBySearch(artist: String, album: String) async -> Data? {
        // Search MusicBrainz for the release to get an ID
        let cleanTitle = cleanAlbumTitle(album)
        guard let release = await MusicBrainzService.searchRelease(artist: artist, album: cleanTitle) else {
            return nil
        }
        return await fetchCoverArtArchive(releaseId: release.id)
    }

    // MARK: - Image fetching

    private static func fetchImageData(url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("DrPlayer/1.0 (music player)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...399).contains(http.statusCode),
              data.count > 1000 else { return nil } // sanity check: real images are > 1KB

        // Follow redirects (Cover Art Archive returns 307)
        if let location = http.value(forHTTPHeaderField: "Location"),
           let redirectURL = URL(string: location) {
            return await fetchImageData(url: redirectURL)
        }

        return data
    }

    // MARK: - Disk cache

    private static func cacheKey(artist: String, album: String) -> String {
        let raw = "\(artist)|\(album)".lowercased()
        var h: UInt64 = 5381
        for byte in raw.utf8 { h = h &* 33 &+ UInt64(byte) }
        return String(h, radix: 16)
    }

    private static func loadCachedImage(key: String) -> NSImage? {
        let path = "\(cacheDir)/\(key).jpg"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private static func saveCachedImage(key: String, data: Data) {
        let path = "\(cacheDir)/\(key).jpg"
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private static func isMarkedNotFound(key: String) -> Bool {
        let path = "\(cacheDir)/\(key).notfound"
        return FileManager.default.fileExists(atPath: path)
    }

    private static func markNotFound(key: String) {
        let path = "\(cacheDir)/\(key).notfound"
        FileManager.default.createFile(atPath: path, contents: nil)
    }

    // MARK: - Helpers

    private static func cleanAlbumTitle(_ title: String) -> String {
        var cleaned = title
        if let range = cleaned.range(of: #"^\d{4}\s+"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}
