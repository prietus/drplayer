import Foundation

/// Generates playlists based on metadata similarity.
/// Uses genre, artist, era, and composer to find related tracks.
/// Ensures diversity: limits tracks per artist, avoids seed artist domination.
enum RadioEngine {

    struct SeedContext {
        let genres: Set<String>
        let artist: String
        let decade: String
        let composer: String
        let label: String
    }

    /// Build a seed context from an album
    static func contextFromAlbum(_ album: Album) -> SeedContext {
        let genres = Set(album.genres.map { $0.lowercased() })
        let decade = decadeFrom(date: album.date)
        let composer = album.composers.first ?? ""
        return SeedContext(
            genres: genres,
            artist: album.artist,
            decade: decade,
            composer: composer,
            label: album.label
        )
    }

    /// Build a seed context from a track
    static func contextFromTrack(_ track: Track) -> SeedContext {
        let genres = track.genre.isEmpty
            ? Set<String>()
            : Set(track.genre.lowercased().split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) })
        return SeedContext(
            genres: genres,
            artist: track.artist,
            decade: decadeFrom(date: track.date),
            composer: track.composer,
            label: track.label
        )
    }

    /// Build a seed context from the last few played tracks
    static func contextFromPlaylist(_ tracks: [Track], lastN: Int = 5) -> SeedContext {
        let recent = Array(tracks.suffix(lastN))
        var genres = Set<String>()
        var artists: [String: Int] = [:]
        var decades: [String: Int] = [:]
        var composers: [String: Int] = [:]

        for t in recent {
            if !t.genre.isEmpty {
                for g in t.genre.lowercased().split(separator: "/") {
                    genres.insert(g.trimmingCharacters(in: .whitespaces))
                }
            }
            if !t.artist.isEmpty { artists[t.artist, default: 0] += 1 }
            let d = decadeFrom(date: t.date)
            if !d.isEmpty { decades[d, default: 0] += 1 }
            if !t.composer.isEmpty { composers[t.composer, default: 0] += 1 }
        }

        return SeedContext(
            genres: genres,
            artist: artists.max(by: { $0.value < $1.value })?.key ?? "",
            decade: decades.max(by: { $0.value < $1.value })?.key ?? "",
            composer: composers.max(by: { $0.value < $1.value })?.key ?? "",
            label: ""
        )
    }

    /// Generate a diverse playlist of tracks similar to the seed context.
    static func generate(
        from context: SeedContext,
        allAlbums: [Album],
        count: Int = 30,
        excludeFiles: Set<String> = [],
        preferredFiles: Set<String> = []
    ) -> [Track] {
        var scored: [(track: Track, score: Int, artist: String)] = []
        let seedArtist = context.artist.lowercased()

        for album in allAlbums {
            let albumGenres = Set(album.genres.map { $0.lowercased() })
            let albumDecade = decadeFrom(date: album.date)
            let trackArtist = album.artist.lowercased()

            for track in album.tracks {
                guard !excludeFiles.contains(track.file) else { continue }

                var score = 0

                // Genre match (strongest signal)
                let genreOverlap = context.genres.intersection(albumGenres).count
                score += genreOverlap * 10

                // Same decade bonus
                if !context.decade.isEmpty && albumDecade == context.decade {
                    score += 3
                }

                // Adjacent decade (smaller bonus)
                if !context.decade.isEmpty, !albumDecade.isEmpty,
                   let sd = Int(context.decade), let ad = Int(albumDecade),
                   abs(sd - ad) == 10 {
                    score += 1
                }

                // Composer match (important for classical)
                if !context.composer.isEmpty &&
                   track.composer.lowercased() == context.composer.lowercased() {
                    score += 8
                }

                // Preferred version bonus
                if preferredFiles.contains(track.file) {
                    score += 15
                }

                // Same artist: small bonus but NOT dominant
                // We want variety — same artist gets just +2 instead of +5
                if !seedArtist.isEmpty && trackArtist == seedArtist {
                    score += 2
                }

                if score > 0 {
                    scored.append((track: track, score: score, artist: trackArtist))
                }
            }
        }

        // Sort by score descending
        scored.sort { $0.score > $1.score }

        // Diversity pass: limit max tracks per artist
        let maxPerArtist = max(3, count / 6)
        var artistCounts: [String: Int] = [:]
        var result: [Track] = []

        // Shuffle within score tiers for variety
        let shuffled = scored.shuffled()
        // Re-sort but with some randomness: group by score buckets
        let bucketed = shuffled.sorted { a, b in
            // Same score bucket (within 3 points) → random order (already shuffled)
            if abs(a.score - b.score) <= 3 { return false }
            return a.score > b.score
        }

        for item in bucketed {
            let count = artistCounts[item.artist, default: 0]
            if count >= maxPerArtist { continue }
            artistCounts[item.artist, default: 0] += 1
            result.append(item.track)
            if result.count >= count { break }
        }

        // If we didn't get enough (restrictive genres), fill with remaining
        if result.count < count {
            for item in bucketed {
                guard !result.contains(where: { $0.file == item.track.file }) else { continue }
                result.append(item.track)
                if result.count >= count { break }
            }
        }

        return Array(result.prefix(count))
    }

    // MARK: - Helpers

    private static func decadeFrom(date: String) -> String {
        guard date.count >= 4, let year = Int(date.prefix(4)), year > 1900 else { return "" }
        return String((year / 10) * 10)
    }
}
