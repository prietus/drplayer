import Foundation

struct DiscogsRelease {
    let id: Int
    let title: String
    let year: Int
    let country: String
    let label: String
    let catalogNumber: String
    let formats: [String]       // "CD", "Vinyl", "SACD", etc.
    let genres: [String]
    let styles: [String]
    let notes: String
    let imageURL: String?
    let url: String             // discogs.com URL
    let tracklist: [(position: String, title: String, duration: String)]
    let lowestPrice: String?    // marketplace lowest price
}

enum DiscogsService {
    private static let baseURL = "https://api.discogs.com"

    private static var key: String { AppSettings.shared.discogsKey }
    private static var secret: String { AppSettings.shared.discogsSecret }

    private static var isConfigured: Bool { !key.isEmpty && !secret.isEmpty }

    /// Search by catalog number (most precise for pressing identification)
    static func searchByCatalog(_ catno: String, country: String? = nil) async -> DiscogsRelease? {
        guard isConfigured else { return nil }
        let suffix = country.map { "_\($0.lowercased())" } ?? ""
        let cacheKey = "discogs_catno_\(catno.lowercased())\(suffix)"
        if let cachedId = MetadataCache.getString(cacheKey) {
            return cachedId == "(none)" ? nil : await fetchRelease(id: Int(cachedId) ?? 0)
        }
        let encoded = catno.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "\(baseURL)/database/search?catno=\(encoded)&key=\(key)&secret=\(secret)"
        guard let results = await searchRequest(urlStr: urlStr, preferredCountry: country), let firstId = results.first else {
            MetadataCache.setString(cacheKey, value: "(none)")
            return nil
        }
        MetadataCache.setString(cacheKey, value: String(firstId))
        return await fetchRelease(id: firstId)
    }

    /// Search by barcode
    static func searchByBarcode(_ barcode: String, country: String? = nil) async -> DiscogsRelease? {
        guard isConfigured else { return nil }
        let suffix = country.map { "_\($0.lowercased())" } ?? ""
        let cacheKey = "discogs_barcode_\(barcode)\(suffix)"
        if let cachedId = MetadataCache.getString(cacheKey) {
            return cachedId == "(none)" ? nil : await fetchRelease(id: Int(cachedId) ?? 0)
        }
        let urlStr = "\(baseURL)/database/search?barcode=\(barcode)&key=\(key)&secret=\(secret)"
        guard let results = await searchRequest(urlStr: urlStr, preferredCountry: country), let firstId = results.first else {
            MetadataCache.setString(cacheKey, value: "(none)")
            return nil
        }
        MetadataCache.setString(cacheKey, value: String(firstId))
        return await fetchRelease(id: firstId)
    }

    /// Search by artist + album title
    static func search(artist: String, album: String) async -> DiscogsRelease? {
        guard isConfigured else { return nil }
        let cacheKey = "discogs_search_\(artist.lowercased())_\(album.lowercased())"
        if let cachedId = MetadataCache.getString(cacheKey) {
            return cachedId == "(none)" ? nil : await fetchRelease(id: Int(cachedId) ?? 0)
        }
        let q = "\(artist) \(album)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "\(baseURL)/database/search?q=\(q)&type=release&key=\(key)&secret=\(secret)"
        guard let results = await searchRequest(urlStr: urlStr), let firstId = results.first else {
            MetadataCache.setString(cacheKey, value: "(none)")
            return nil
        }
        MetadataCache.setString(cacheKey, value: String(firstId))
        return await fetchRelease(id: firstId)
    }

    /// Fetch full release details by Discogs ID
    static func fetchRelease(id: Int) async -> DiscogsRelease? {
        let cacheKey = "discogs_release_\(id)"
        if let cached = MetadataCache.get(cacheKey) {
            if let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
                return parseRelease(id: id, json: json)
            }
        }

        let urlStr = "\(baseURL)/releases/\(id)?key=\(key)&secret=\(secret)"
        guard let url = URL(string: urlStr) else { return nil }

        guard let data = await fetch(url) else { return nil }
        MetadataCache.set(cacheKey, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseRelease(id: id, json: json)
    }

    private static func parseRelease(id: Int, json: [String: Any]) -> DiscogsRelease {
        let title = json["title"] as? String ?? ""
        let year = json["year"] as? Int ?? 0
        let country = json["country"] as? String ?? ""
        let uri = json["uri"] as? String ?? ""
        let notes = json["notes"] as? String ?? ""

        // Labels
        var label = ""
        var catalogNumber = ""
        if let labels = json["labels"] as? [[String: Any]], let first = labels.first {
            label = first["name"] as? String ?? ""
            catalogNumber = first["catno"] as? String ?? ""
        }

        // Formats
        var formats: [String] = []
        if let fmts = json["formats"] as? [[String: Any]] {
            for fmt in fmts {
                let name = fmt["name"] as? String ?? ""
                let descriptions = (fmt["descriptions"] as? [String]) ?? []
                let desc = descriptions.isEmpty ? name : "\(name) (\(descriptions.joined(separator: ", ")))"
                formats.append(desc)
            }
        }

        // Genres & Styles
        let genres = (json["genres"] as? [String]) ?? []
        let styles = (json["styles"] as? [String]) ?? []

        // Images
        var imageURL: String?
        if let images = json["images"] as? [[String: Any]], let first = images.first {
            imageURL = first["uri"] as? String
        }

        // Tracklist
        var tracklist: [(position: String, title: String, duration: String)] = []
        if let tracks = json["tracklist"] as? [[String: Any]] {
            for track in tracks {
                let pos = track["position"] as? String ?? ""
                let title = track["title"] as? String ?? ""
                let dur = track["duration"] as? String ?? ""
                if !title.isEmpty {
                    tracklist.append((position: pos, title: title, duration: dur))
                }
            }
        }

        // Lowest price
        var lowestPrice: String?
        if let lp = json["lowest_price"] as? Double {
            lowestPrice = String(format: "%.2f", lp)
        }

        let discogsURL: String
        if uri.hasPrefix("http") {
            discogsURL = uri
        } else if !uri.isEmpty {
            discogsURL = "https://www.discogs.com\(uri)"
        } else {
            discogsURL = "https://www.discogs.com/release/\(id)"
        }

        return DiscogsRelease(
            id: id, title: title, year: year, country: country,
            label: label, catalogNumber: catalogNumber,
            formats: formats, genres: genres, styles: styles,
            notes: notes, imageURL: imageURL, url: discogsURL,
            tracklist: tracklist, lowestPrice: lowestPrice
        )
    }

    // MARK: - Helpers

    /// Search with optional country hint to rank results.
    /// Prefers official releases and matching country over random first result.
    private static func searchRequest(urlStr: String, preferredCountry: String? = nil) async -> [Int]? {
        guard let url = URL(string: urlStr) else { return nil }
        guard let data = await fetch(url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }

        // Rank results: prefer official releases and matching country
        let ranked = results.compactMap { result -> (id: Int, score: Int)? in
            guard let id = result["id"] as? Int else { return nil }
            var score = 0

            // Penalize unofficial/bootleg releases
            let formats = (result["format"] as? [String]) ?? []
            let formatStr = formats.joined(separator: " ").lowercased()
            if formatStr.contains("unofficial") || formatStr.contains("bootleg") {
                score -= 20
            }

            // Country match bonus
            if let pc = preferredCountry?.lowercased(),
               let country = (result["country"] as? String)?.lowercased(),
               country == pc {
                score += 10
            }

            return (id: id, score: score)
        }

        let sorted = ranked.sorted { $0.score > $1.score }
        return sorted.isEmpty ? nil : sorted.map { $0.id }
    }

    private static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("DrPlayer/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return data
    }
}
