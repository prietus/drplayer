import Foundation

/// Enriches album genres from MusicBrainz and Last.fm, with disk cache.
enum GenreEnricher {

    private static let cacheDir: String = {
        let dir = NSHomeDirectory() + "/.drplayer/genres"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Enrich genres for a single album. Returns additional genres not already present.
    static func enrichGenres(for album: Album) async -> [String] {
        let cacheKey = cacheKey(artist: album.artist, album: album.title)

        // Check cache first
        if let cached = loadCache(key: cacheKey) {
            return cached
        }

        var newGenres: [String] = []

        // 1. MusicBrainz: direct lookup by album ID (fastest, most reliable)
        if !album.musicbrainzAlbumId.isEmpty {
            if let release = await MusicBrainzService.fetchRelease(id: album.musicbrainzAlbumId) {
                newGenres.append(contentsOf: release.genres)
            }
        }

        // 2. Last.fm album tags (good for subgenres like "progressive rock", "post-punk")
        let lfmTags = await LastFMService.fetchAlbumTags(artist: album.artist, album: album.title)
        newGenres.append(contentsOf: lfmTags)

        // Deduplicate and normalize
        let existing = Set(album.genres.map { $0.lowercased() })
        let enriched = newGenres
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { capitalizeGenre($0) }
            .filter { !existing.contains($0.lowercased()) }

        // Deduplicate among enriched
        var seen = Set<String>()
        let unique = enriched.filter { seen.insert($0.lowercased()).inserted }

        // Cache result (even if empty, to avoid re-fetching)
        saveCache(key: cacheKey, genres: unique)

        return unique
    }

    /// Enrich all albums in background. Rate-limited to avoid API hammering.
    static func enrichAllAlbums(_ albums: [Album], update: @escaping (Int, [String]) async -> Void) async {
        for (idx, album) in albums.enumerated() {
            // Skip if already has rich genre data (3+ genres)
            if album.genres.count >= 3 { continue }

            // Skip if already cached
            let key = cacheKey(artist: album.artist, album: album.title)
            if let cached = loadCache(key: key) {
                if !cached.isEmpty {
                    await update(idx, cached)
                }
                continue
            }

            let newGenres = await enrichGenres(for: album)
            if !newGenres.isEmpty {
                await update(idx, newGenres)
            }

            // Rate limit: 1 second between API calls
            try? await Task.sleep(for: .seconds(1))
        }
    }

    // MARK: - Cache

    private static func cacheKey(artist: String, album: String) -> String {
        let raw = "\(artist)|\(album)".lowercased()
        var hash: UInt64 = 5381
        for byte in raw.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return String(hash, radix: 16)
    }

    private static func loadCache(key: String) -> [String]? {
        let path = "\(cacheDir)/\(key).genres"
        guard let data = FileManager.default.contents(atPath: path),
              let str = String(data: data, encoding: .utf8) else { return nil }
        if str == "(empty)" { return [] }
        return str.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private static func saveCache(key: String, genres: [String]) {
        let path = "\(cacheDir)/\(key).genres"
        let content = genres.isEmpty ? "(empty)" : genres.joined(separator: "\n")
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private static func capitalizeGenre(_ genre: String) -> String {
        genre.split(separator: " ")
            .map { word in
                let w = String(word)
                if w.count <= 2 && w.uppercased() == w { return w }
                return w.prefix(1).uppercased() + w.dropFirst()
            }
            .joined(separator: " ")
    }
}
