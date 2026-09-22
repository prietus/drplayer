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
        let genres = normalizedGenres(album.genres)
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

    /// Tags that are too ambiguous or noisy to drive genre similarity.
    /// "classic" alone matches both "classic rock" albums and classical music
    /// after Last.fm enrichment, which pulls classical into rock playlists.
    /// Decade tags ("70s", "1970s") are weak signals already covered by `decade`.
    private static let stopTags: Set<String> = [
        "classic",
        "seen live", "favorite", "favorites", "favourite", "favourites",
        "awesome", "amazing", "good", "great", "best", "love", "loved",
        "albums i own", "owned", "own", "music", "song", "songs",
        "00s", "10s", "20s", "30s", "40s", "50s", "60s", "70s", "80s", "90s",
        "1900s", "1910s", "1920s", "1930s", "1940s", "1950s",
        "1960s", "1970s", "1980s", "1990s", "2000s", "2010s", "2020s"
    ]

    private static func normalizedGenres(_ raw: [String]) -> Set<String> {
        var out = Set<String>()
        for g in raw {
            let lower = g.lowercased().trimmingCharacters(in: .whitespaces)
            if lower.isEmpty || stopTags.contains(lower) { continue }
            out.insert(lower)
        }
        return out
    }

    /// Build a seed context from a track
    static func contextFromTrack(_ track: Track) -> SeedContext {
        let raw = track.genre.isEmpty
            ? []
            : track.genre.split(separator: "/").map { String($0) }
        let genres = normalizedGenres(raw)
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
                let parts = t.genre.split(separator: "/").map { String($0) }
                for g in normalizedGenres(parts) {
                    genres.insert(g)
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
    /// `similarArtists` is a map of lowercased artist name → match score 0-1 (from Last.fm).
    /// When non-empty it becomes the dominant signal; genre/decade/composer are tie-breakers.
    static func generate(
        from context: SeedContext,
        allAlbums: [Album],
        count: Int = 30,
        excludeFiles: Set<String> = [],
        similarArtists: [String: Double] = [:]
    ) -> [Track] {
        var scored: [(track: Track, score: Int, artist: String, album: String)] = []
        let seedArtist = context.artist.lowercased()
        let useSimilar = !similarArtists.isEmpty
        // With Last.fm data, genre is a tiebreaker (×25 Jaccard) vs primary (×50)
        let genreMax = useSimilar ? 25 : 50

        for album in allAlbums {
            let albumGenres = normalizedGenres(album.genres)
            let albumDecade = decadeFrom(date: album.date)
            let trackArtist = album.artist.lowercased()
            let albumKey = "\(trackArtist)//\(album.title.lowercased())"
            let similarMatch = similarArtists[trackArtist] ?? 0

            // Jaccard similarity: |A ∩ B| / |A ∪ B|. Normalizes so an album
            // tagged with 8 broad genres doesn't outscore one with 2 precise
            // tags when both overlap on "rock".
            let union = context.genres.union(albumGenres).count
            let overlap = context.genres.intersection(albumGenres).count
            let jaccard = union > 0 ? Double(overlap) / Double(union) : 0

            for track in album.tracks {
                guard !excludeFiles.contains(track.file) else { continue }

                let composerMatch = !context.composer.isEmpty &&
                    track.composer.lowercased() == context.composer.lowercased()
                let sameArtist = !seedArtist.isEmpty && trackArtist == seedArtist

                // Affinity gate: a track needs a real connection to the seed
                // (similar artist, genre overlap, composer, or same artist).
                // Without this, rating + decade alone (max 18 pts) let
                // highly-rated unrelated tracks (typically classical with 5★)
                // flood the queue regardless of seed genre.
                let hasAffinity = similarMatch > 0 || jaccard > 0 || composerMatch || sameArtist
                guard hasAffinity else { continue }

                var score = 0

                // Last.fm similar-artist match (dominant signal when present)
                // match 0-1 → 0-20 points
                if similarMatch > 0 {
                    score += Int(similarMatch * 20)
                }

                // Genre match (Jaccard-normalized)
                score += Int(jaccard * Double(genreMax))

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
                if composerMatch {
                    score += 8
                }

                // Rating bonus: 1-5 stars → 3-15 points
                if track.rating > 0 {
                    score += track.rating * 3
                }

                // Same artist: small bonus but NOT dominant
                // We want variety — same artist gets just +2 instead of +5
                if sameArtist {
                    score += 2
                }

                if score > 0 {
                    scored.append((track: track, score: score, artist: trackArtist, album: albumKey))
                }
            }
        }

        // Sort by score descending
        scored.sort { $0.score > $1.score }

        // Diversity pass: limit tracks per artist and per album.
        // Cap at ~10% per artist so no single attractor artist (e.g. a
        // classic-rock hub that Last.fm flags as similar to half the library)
        // can dominate the queue.
        let maxPerArtist = max(2, count / 10)
        let maxPerAlbum = 2
        var artistCounts: [String: Int] = [:]
        var albumCounts: [String: Int] = [:]
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
            if artistCounts[item.artist, default: 0] >= maxPerArtist { continue }
            if albumCounts[item.album, default: 0] >= maxPerAlbum { continue }
            artistCounts[item.artist, default: 0] += 1
            albumCounts[item.album, default: 0] += 1
            result.append(item.track)
            if result.count >= count { break }
        }

        // If we didn't get enough (restrictive genres), relax album limit
        if result.count < count {
            for item in bucketed {
                guard !result.contains(where: { $0.file == item.track.file }) else { continue }
                if artistCounts[item.artist, default: 0] >= maxPerArtist { continue }
                artistCounts[item.artist, default: 0] += 1
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
