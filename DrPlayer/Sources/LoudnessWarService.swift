import Foundation

struct LoudnessWarEntry: Identifiable {
    let id: String      // album view ID
    let artist: String
    let album: String
    let year: String
    let drAvg: Int
    let drMin: Int
    let drMax: Int
    let codec: String   // "Lossless", "Lossy"
    let source: String  // "CD", "Vinyl", "Download", etc.
}

enum LoudnessWarService {
    private static let baseURL = "https://dr.loudness-war.info/album/list"

    /// Clean album title: remove parenthesized catalog numbers, bracketed suffixes, etc.
    private static func cleanAlbumTitle(_ title: String) -> String {
        var cleaned = title
        // Remove trailing parenthesized content like (UICY-40261), (Remastered 2011)
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove trailing bracketed content like [Deluxe Edition]
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Search for DR entries of an album on dr.loudness-war.info
    static func search(artist: String, album: String) async -> [LoudnessWarEntry] {
        let cleanedAlbum = cleanAlbumTitle(album)
        let params = [
            "artist": artist,
            "album": cleanedAlbum
        ]
        let query = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        let urlStr = "\(baseURL)?\(query)"
        guard let url = URL(string: urlStr) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("DrPlayer/1.0 (music player)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return [] }

        return parseAlbumList(html: html)
    }

    private static func parseAlbumList(html: String) -> [LoudnessWarEntry] {
        var entries: [LoudnessWarEntry] = []

        // Extract album IDs from links
        let idPattern = #"album/view/(\d+)"#
        let ids = matches(in: html, pattern: idPattern).map { $0[1] }

        // Extract table rows
        let rowPattern = #"<tr>(.*?)</tr>"#
        let rows = matches(in: html, pattern: rowPattern).map { $0[0] }

        for row in rows {
            let cellPattern = #"<td[^>]*>(.*?)</td>"#
            let cells = matches(in: row, pattern: cellPattern).map { stripHTML($0[1]) }

            guard cells.count >= 8 else { continue }

            let artist = cells[0]
            let album = cells[1]
            let year = cells[2]
            guard let drAvg = Int(cells[3]),
                  let drMin = Int(cells[4]),
                  let drMax = Int(cells[5]) else { continue }
            let codec = cells[6]
            let source = cells[7]

            // Find matching album ID
            let albumSlug = album.lowercased()
            let matchingId = ids.first ?? "\(entries.count)"

            entries.append(LoudnessWarEntry(
                id: matchingId,
                artist: artist,
                album: album,
                year: year,
                drAvg: drAvg,
                drMin: drMin,
                drMax: drMax,
                codec: codec,
                source: source
            ))
        }

        // Assign correct IDs based on order
        var result: [LoudnessWarEntry] = []
        for (i, entry) in entries.enumerated() {
            let entryId = i < ids.count ? ids[i] : "\(i)"
            result.append(LoudnessWarEntry(
                id: entryId,
                artist: entry.artist,
                album: entry.album,
                year: entry.year,
                drAvg: entry.drAvg,
                drMin: entry.drMin,
                drMax: entry.drMax,
                codec: entry.codec,
                source: entry.source
            ))
        }

        return result
    }

    private static func matches(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { i in
                guard let r = Range(match.range(at: i), in: text) else { return nil }
                return String(text[r])
            }
        }
    }

    private static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
