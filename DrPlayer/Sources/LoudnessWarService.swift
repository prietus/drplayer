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
    // Detail fields (from album/view page)
    var label: String = ""
    var catalogNumber: String = ""
    var country: String = ""
}

enum LoudnessWarService {
    private static let baseURL = "https://dr.loudness-war.info/album/list"

    /// Clean album title: remove year prefixes, format suffixes, catalog numbers, etc.
    private static func cleanAlbumTitle(_ title: String) -> String {
        var cleaned = title
        // Strip surrounding quotes: "Heroes" → Heroes
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201C}\u{201D}\u{00AB}\u{00BB}"))
        // Remove leading year prefix: "1972 Demons and Wizards" → "Demons and Wizards"
        if let range = cleaned.range(of: #"^\d{4}\s+"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove trailing parenthesized content like (UICY-40261), (Remastered 2011)
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove trailing bracketed content like [Deluxe Edition]
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove format suffixes: "Beat SHM-CD Legacy Collection 1980" → "Beat"
        if let range = cleaned.range(of: #"\s+(SHM-CD|SHM-SACD|HDCD|MQA-CD|XRCD|K2HD|HQCD|Blu-spec CD|UHQCD).*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        // Remove collection/edition suffixes
        if let range = cleaned.range(of: #"\s+(Legacy|Anniversary|Collector|Limited|Special)\s+(Collection|Edition).*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        // Remove " - Remastered" etc
        if let range = cleaned.range(of: #"\s*-\s*(remaster|deluxe|bonus).*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        // Remove " - CD 1", " - Disc Two" etc
        if let range = cleaned.range(of: #"\s*-\s*(CD|Disc)\s.*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        // Remove trailing year: "Beat 1980" → "Beat"
        if let range = cleaned.range(of: #"\s+\d{4}\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Search for DR entries of an album on dr.loudness-war.info
    static func search(artist: String, album: String) async -> [LoudnessWarEntry] {
        let cleanedAlbum = cleanAlbumTitle(album)
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "album", value: cleanedAlbum)
        ]
        // URLComponents doesn't encode apostrophes — fix manually
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "'", with: "%27")
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("DrPlayer/1.0 (music player)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return [] }

        let results = parseAlbumList(html: html)

        // If no results and artist contains "-", retry with "/" (AC-DC → AC/DC)
        if results.isEmpty && artist.contains("-") {
            let altArtist = artist.replacingOccurrences(of: "-", with: "/")
            return await search(artist: altArtist, album: album)
        }

        return results
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

    /// Fetch detail page for an entry to get label, catalog number, country
    static func fetchDetail(entry: LoudnessWarEntry) async -> LoudnessWarEntry {
        let urlStr = "https://dr.loudness-war.info/album/view/\(entry.id)"
        guard let url = URL(string: urlStr) else { return entry }

        var request = URLRequest(url: url)
        request.setValue("DrPlayer/1.0 (music player)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return entry }

        var result = entry
        result.label = extractField(html: html, field: "Label")
        result.catalogNumber = extractField(html: html, field: "Catalog number")
        result.country = extractField(html: html, field: "Country")
        return result
    }

    /// Extract a field value from the detail page HTML.
    /// Fields are in <dt>Label</dt><dd>value</dd> or <th>Label</th><td>value</td> patterns.
    private static func extractField(html: String, field: String) -> String {
        // Try <th>field</th> ... <td>value</td> pattern
        let thPattern = #"<th[^>]*>\s*"# + NSRegularExpression.escapedPattern(for: field) + #"\s*</th>\s*<td[^>]*>(.*?)</td>"#
        if let match = matches(in: html, pattern: thPattern).first, match.count > 1 {
            return stripHTML(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Try <dt>field</dt><dd>value</dd> pattern
        let dtPattern = #"<dt[^>]*>\s*"# + NSRegularExpression.escapedPattern(for: field) + #"\s*</dt>\s*<dd[^>]*>(.*?)</dd>"#
        if let match = matches(in: html, pattern: dtPattern).first, match.count > 1 {
            return stripHTML(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
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
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
