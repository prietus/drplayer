import Foundation

struct WikiSummary {
    let title: String
    let extract: String
    let thumbnailURL: String?
    let originalImageURL: String?
    let pageURL: String
    let language: String
}

enum WikipediaService {
    /// Fetch article summary. Tries English first, falls back to Spanish.
    static func fetchSummary(slug: String) async -> WikiSummary? {
        if let summary = await fetchFromWiki(lang: "en", slug: slug) {
            return summary
        }
        if let summary = await fetchFromWiki(lang: "es", slug: slug) {
            return summary
        }
        return nil
    }

    /// Search Wikipedia for an artist — handles compound names and special chars
    static func searchArtist(name: String) async -> WikiSummary? {
        // Try variations of the name
        for query in artistSearchQueries(name) {
            if let result = await search(query: query) {
                return result
            }
        }
        // Try Spanish Wikipedia
        for query in artistSearchQueries(name) {
            if let result = await search(query: query, lang: "es") {
                return result
            }
        }
        return nil
    }

    /// Generate search queries for an artist name, handling separators and special chars
    static func artistSearchQueries(_ name: String) -> [String] {
        var queries: [String] = []

        // 1. Exact name
        queries.append(name)

        // 2. If compound artist (feat, &, with, y, +), try first artist alone
        let separators = [" & ", " and ", " with ", " feat. ", " feat ", " ft. ", " ft ", " + ", " y "]
        for sep in separators {
            if let range = name.range(of: sep, options: .caseInsensitive) {
                let first = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !first.isEmpty {
                    queries.append(first)
                }
                break
            }
        }

        // 3. Replace special chars: AC/DC → AC/DC (wiki handles /), but also try without
        if name.contains("/") {
            queries.append(name.replacingOccurrences(of: "/", with: " "))
        }

        return queries
    }

    /// Search Wikipedia for a topic
    static func search(query: String, lang: String = "en") async -> WikiSummary? {
        let slug = query.replacingOccurrences(of: " ", with: "_")
        if let result = await fetchFromWiki(lang: lang, slug: slug) {
            return result
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let urlStr = "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(encoded)"
        guard let url = URL(string: urlStr) else { return nil }
        return await fetchSummaryFromURL(url, lang: lang)
    }

    private static func fetchFromWiki(lang: String, slug: String) async -> WikiSummary? {
        let decoded = slug.removingPercentEncoding ?? slug
        let cleanSlug = decoded.replacingOccurrences(of: " ", with: "_")
        let urlStr = "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(cleanSlug)"
        guard let url = URL(string: urlStr) else { return nil }
        return await fetchSummaryFromURL(url, lang: lang)
    }

    private static func fetchSummaryFromURL(_ url: URL, lang: String) async -> WikiSummary? {
        var request = URLRequest(url: url)
        request.setValue("DrPlayer/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let title = json["title"] as? String ?? ""
        let extract = json["extract"] as? String ?? ""
        let pageURL = (json["content_urls"] as? [String: Any])?["desktop"] as? [String: Any]
        let url = pageURL?["page"] as? String ?? ""

        var thumbnail: String? = nil
        if let thumb = json["thumbnail"] as? [String: Any] {
            thumbnail = thumb["source"] as? String
        }

        // Get higher resolution original image
        var originalImage: String? = nil
        if let orig = json["originalimage"] as? [String: Any] {
            originalImage = orig["source"] as? String
        }

        guard !extract.isEmpty else { return nil }

        return WikiSummary(
            title: title, extract: extract,
            thumbnailURL: thumbnail, originalImageURL: originalImage,
            pageURL: url, language: lang
        )
    }
}
