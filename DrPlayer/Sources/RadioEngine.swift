import Foundation

/// Generates playlists based on metadata similarity.
/// Uses genre, artist, era, and composer to find related tracks.
enum RadioEngine {

    struct SeedContext {
        let genres: Set<String>
        let artist: String
        let decade: String       // "1970", "1980", etc.
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
        let genres = track.genre.isEmpty ? Set<String>() : Set(track.genre.lowercased().split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) })
        let decade = decadeFrom(date: track.date)
        return SeedContext(
            genres: genres,
            artist: track.artist,
            decade: decade,
            composer: track.composer,
            label: track.label
        )
    }

    /// Build a seed context from the last few played tracks (for playlist continuity)
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
            if !t.artist.isEmpty {
                artists[t.artist, default: 0] += 1
            }
            let d = decadeFrom(date: t.date)
            if !d.isEmpty { decades[d, default: 0] += 1 }
            if !t.composer.isEmpty { composers[t.composer, default: 0] += 1 }
        }

        let topArtist = artists.max(by: { $0.value < $1.value })?.key ?? ""
        let topDecade = decades.max(by: { $0.value < $1.value })?.key ?? ""
        let topComposer = composers.max(by: { $0.value < $1.value })?.key ?? ""

        return SeedContext(
            genres: genres,
            artist: topArtist,
            decade: topDecade,
            composer: topComposer,
            label: ""
        )
    }

    /// Generate a playlist of tracks similar to the seed context.
    /// Scores each track by metadata similarity and picks the top matches, shuffled.
    static func generate(from context: SeedContext, allAlbums: [Album], count: Int = 30, excludeFiles: Set<String> = []) -> [Track] {
        var scored: [(track: Track, score: Int)] = []

        for album in allAlbums {
            let albumGenres = Set(album.genres.map { $0.lowercased() })
            let albumDecade = decadeFrom(date: album.date)

            for track in album.tracks {
                // Skip already played/queued
                guard !excludeFiles.contains(track.file) else { continue }

                var score = 0

                // Genre match (strongest signal)
                let genreOverlap = context.genres.intersection(albumGenres).count
                score += genreOverlap * 10

                // Artist match
                if !context.artist.isEmpty &&
                   track.artist.lowercased() == context.artist.lowercased() {
                    score += 5
                }

                // Same decade
                if !context.decade.isEmpty && albumDecade == context.decade {
                    score += 3
                }

                // Composer match (important for classical)
                if !context.composer.isEmpty &&
                   track.composer.lowercased() == context.composer.lowercased() {
                    score += 8
                }

                // Only include tracks with some relevance
                if score > 0 {
                    scored.append((track: track, score: score))
                }
            }
        }

        // Sort by score descending, then shuffle within score tiers for variety
        scored.sort { $0.score > $1.score }

        // Take top candidates (2x count for variety), then shuffle and trim
        let candidates = Array(scored.prefix(count * 2))
        let shuffled = candidates.shuffled()
        return Array(shuffled.prefix(count).map(\.track))
    }

    // MARK: - Helpers

    private static func decadeFrom(date: String) -> String {
        guard date.count >= 4, let year = Int(date.prefix(4)), year > 1900 else { return "" }
        let decade = (year / 10) * 10
        return String(decade)
    }
}
