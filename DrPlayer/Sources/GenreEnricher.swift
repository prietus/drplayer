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
        let cleanTitle = cleanAlbumTitle(album.title)
        let cacheKey = cacheKey(artist: album.artist, album: cleanTitle)

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

        // 2. Last.fm album tags
        // Try different artist name variants (AC-DC → AC/DC, etc.)
        let artistVariants = artistSearchNames(album.artist)
        var lfmTags: [String] = []
        for artistName in artistVariants {
            lfmTags = await LastFMService.fetchAlbumTags(artist: artistName, album: cleanTitle)
            if !lfmTags.isEmpty { break }
            if cleanTitle != album.title {
                lfmTags = await LastFMService.fetchAlbumTags(artist: artistName, album: album.title)
                if !lfmTags.isEmpty { break }
            }
        }
        // 3. Fallback: Last.fm artist tags
        if lfmTags.isEmpty && newGenres.isEmpty {
            for artistName in artistVariants {
                if let artistInfo = await LastFMService.fetchArtist(name: artistName) {
                    if !artistInfo.tags.isEmpty {
                        lfmTags = artistInfo.tags
                        break
                    }
                }
            }
        }
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
    static func enrichAllAlbums(
        _ albums: [Album],
        update: @escaping (Int, [String]) async -> Void,
        progress: @escaping (Int, Int) async -> Void
    ) async {
        let total = albums.count
        for (idx, album) in albums.enumerated() {
            await progress(idx, total)

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
        await progress(total, total)
    }

    /// Clean album title for API searches:
    /// "1974 Burn" → "Burn", "Machine Head [MQA-CD]" → "Machine Head"
    private static func cleanAlbumTitle(_ title: String) -> String {
        var cleaned = title

        // Remove leading year prefix: "1974 Burn" → "Burn"
        if let range = cleaned.range(of: #"^\d{4}\s+"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }

        // Remove trailing parenthesized content: "(UICY-40261)", "(Remastered 2011)"
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }

        // Remove trailing bracketed content: "[MQA-CD]", "[Deluxe Edition]"
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }

        // Remove " - Remastered" suffix
        if let range = cleaned.range(of: #"\s*-\s*remaster.*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Generate artist name variants for API searches
    /// "AC-DC" → ["AC-DC", "AC/DC"], "Guns N' Roses" → ["Guns N' Roses"]
    private static func artistSearchNames(_ name: String) -> [String] {
        var names = [name]
        // Try replacing - with / (AC-DC → AC/DC)
        if name.contains("-") {
            names.append(name.replacingOccurrences(of: "-", with: "/"))
        }
        // Try replacing / with -
        if name.contains("/") {
            names.append(name.replacingOccurrences(of: "/", with: "-"))
        }
        return names
    }

    /// Count how many albums are already cached
    static var cachedCount: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: cacheDir).count) ?? 0
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
