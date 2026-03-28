import Foundation

struct LyricsResult {
    let plain: String?
    let synced: String?
    let instrumental: Bool
}

struct SyncedLine: Identifiable {
    let id: Int
    let time: Double // seconds
    let text: String
}

enum LyricsService {
    private static let baseURL = "https://lrclib.net/api"
    private static let userAgent = "DrPlayer/1.0 (https://github.com/drplayer)"

    /// Fetch lyrics for a track. Tries exact match first, falls back to search.
    static func fetchLyrics(artist: String, title: String, album: String, duration: Double) async -> LyricsResult? {
        // Try exact match first (faster, cached)
        if let result = await fetchExact(artist: artist, title: title, album: album, duration: duration) {
            return result
        }
        // Fallback to search
        return await searchLyrics(artist: artist, title: title)
    }

    private static func fetchExact(artist: String, title: String, album: String, duration: Double) async -> LyricsResult? {
        var components = URLComponents(string: "\(baseURL)/get")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration)))
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return parseLyricsJSON(json)
    }

    private static func searchLyrics(artist: String, title: String) async -> LyricsResult? {
        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = results.first else {
            return nil
        }

        return parseLyricsJSON(first)
    }

    private static func parseLyricsJSON(_ json: [String: Any]) -> LyricsResult {
        LyricsResult(
            plain: json["plainLyrics"] as? String,
            synced: json["syncedLyrics"] as? String,
            instrumental: json["instrumental"] as? Bool ?? false
        )
    }

    /// Parse LRC format synced lyrics into timed lines
    static func parseSyncedLyrics(_ lrc: String) -> [SyncedLine] {
        var lines: [SyncedLine] = []
        for (idx, line) in lrc.components(separatedBy: "\n").enumerated() {
            // Format: [MM:SS.CC] text
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            guard let closeBracket = trimmed.firstIndex(of: "]") else { continue }

            let timeStr = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
            let text = String(trimmed[trimmed.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)

            if let time = parseTime(timeStr) {
                lines.append(SyncedLine(id: idx, time: time, text: text))
            }
        }
        return lines
    }

    private static func parseTime(_ s: String) -> Double? {
        // MM:SS.CC or MM:SS
        let parts = s.split(separator: ":")
        guard parts.count == 2, let mins = Double(parts[0]) else { return nil }
        let secParts = parts[1].split(separator: ".")
        guard let secs = Double(secParts[0]) else { return nil }
        let frac: Double
        if secParts.count > 1, let f = Double("0.\(secParts[1])") {
            frac = f
        } else {
            frac = 0
        }
        return mins * 60 + secs + frac
    }
}
