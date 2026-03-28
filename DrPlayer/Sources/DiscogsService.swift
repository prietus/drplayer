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
    static func searchByCatalog(_ catno: String) async -> DiscogsRelease? {
        guard isConfigured else { return nil }
        let encoded = catno.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "\(baseURL)/database/search?catno=\(encoded)&key=\(key)&secret=\(secret)"
        guard let results = await searchRequest(urlStr: urlStr) else { return nil }
        guard let firstId = results.first else { return nil }
        return await fetchRelease(id: firstId)
    }

    /// Search by barcode
    static func searchByBarcode(_ barcode: String) async -> DiscogsRelease? {
        guard isConfigured else { return nil }
        let urlStr = "\(baseURL)/database/search?barcode=\(barcode)&key=\(key)&secret=\(secret)"
        guard let results = await searchRequest(urlStr: urlStr) else { return nil }
        guard let firstId = results.first else { return nil }
        return await fetchRelease(id: firstId)
    }

    /// Search by artist + album title
    static func search(artist: String, album: String) async -> DiscogsRelease? {
        guard isConfigured else { return nil }
        let q = "\(artist) \(album)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "\(baseURL)/database/search?q=\(q)&type=release&key=\(key)&secret=\(secret)"
        guard let results = await searchRequest(urlStr: urlStr) else { return nil }
        guard let firstId = results.first else { return nil }
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

        let discogsURL = uri.isEmpty ? "https://www.discogs.com/release/\(id)" : "https://www.discogs.com\(uri)"

        return DiscogsRelease(
            id: id, title: title, year: year, country: country,
            label: label, catalogNumber: catalogNumber,
            formats: formats, genres: genres, styles: styles,
            notes: notes, imageURL: imageURL, url: discogsURL,
            tracklist: tracklist, lowestPrice: lowestPrice
        )
    }

    // MARK: - Helpers

    private static func searchRequest(urlStr: String) async -> [Int]? {
        guard let url = URL(string: urlStr) else { return nil }
        guard let data = await fetch(url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }

        return results.compactMap { $0["id"] as? Int }
    }

    private static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("DrPlayer/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return data
    }
}
