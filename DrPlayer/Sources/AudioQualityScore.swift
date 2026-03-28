import Foundation

/// Scores audio quality for version comparison.
/// Higher score = better quality for audiophile listening.
enum AudioQualityScore {

    struct Score {
        let total: Int
        let drScore: Int
        let formatScore: Int
        let badge: Badge
    }

    enum Badge: String {
        case best = "star.fill"          // Best version
        case good = "checkmark.circle"   // Good quality
        case warning = "exclamationmark.triangle" // Compressed/lossy
    }

    /// Score a track+album combination
    static func score(track: Track, album: Album) -> Score {
        let dr = drScore(track.dr)
        let fmt = formatScore(album.format)
        let total = dr + fmt
        let badge = classifyBadge(dr: track.dr, format: album.format)
        return Score(total: total, drScore: dr, formatScore: fmt, badge: badge)
    }

    /// Score just DR value (0-50 points)
    private static func drScore(_ dr: Int?) -> Int {
        guard let dr, dr > 0 else { return 0 }
        // DR14+ = 50, DR10 = 30, DR7 = 15, DR4 = 5
        return min(50, dr * 4)
    }

    /// Score format (0-50 points)
    /// DSD > Hi-Res FLAC > CD FLAC > MQA > Lossy
    private static func formatScore(_ format: String) -> Int {
        let f = format.uppercased()

        // DSD formats
        if f.contains("DSF") || f.contains("DFF") || f.contains("DSD") {
            return 50
        }

        // Lossless hi-res
        if f.contains("FLAC") || f.contains("WAV") || f.contains("AIFF") || f.contains("ALAC") {
            return 40
        }

        // MQA (controversial but lossless-ish)
        if f.contains("MQA") {
            return 35
        }

        // Lossy
        if f.contains("MP3") || f.contains("AAC") || f.contains("OGG") || f.contains("OPUS") {
            return 10
        }

        return 20 // unknown
    }

    /// Classify into badge type
    private static func classifyBadge(dr: Int?, format: String) -> Badge {
        let f = format.uppercased()
        let isLossy = f.contains("MP3") || f.contains("AAC") || f.contains("OGG")
        let lowDR = (dr ?? 0) > 0 && (dr ?? 0) < 8

        if isLossy || lowDR {
            return .warning
        }
        return .good
    }

    /// Score and rank a list of versions, marking the best one
    static func rankVersions(_ versions: [(track: Track, album: Album)]) -> [(track: Track, album: Album, score: Score, isBest: Bool)] {
        let scored = versions.map { (track: $0.track, album: $0.album, score: score(track: $0.track, album: $0.album)) }
        let maxScore = scored.map(\.score.total).max() ?? 0

        return scored.map { item in
            let isBest = item.score.total == maxScore && maxScore > 0
            return (
                track: item.track,
                album: item.album,
                score: Score(
                    total: item.score.total,
                    drScore: item.score.drScore,
                    formatScore: item.score.formatScore,
                    badge: isBest ? .best : item.score.badge
                ),
                isBest: isBest
            )
        }
        .sorted { $0.score.total > $1.score.total }
    }
}
