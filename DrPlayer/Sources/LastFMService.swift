import Foundation

struct LastFMArtist {
    let name: String
    let bio: String
    let summary: String
    let tags: [String]
    let similarArtists: [String]
    let listeners: String
    let playcount: String
    let imageURL: String?
    let url: String
}

enum LastFMService {
    static var apiKey: String {
        AppSettings.shared.lastfmApiKey
    }

    private static let baseURL = "https://ws.audioscrobbler.com/2.0"

    static func fetchArtist(name: String) async -> LastFMArtist? {
        guard !apiKey.isEmpty else { return nil }

        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "\(baseURL)?method=artist.getinfo&artist=\(encoded)&api_key=\(apiKey)&format=json"
        guard let url = URL(string: urlStr) else { return nil }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artist = json["artist"] as? [String: Any] else { return nil }

        let artistName = artist["name"] as? String ?? name
        let url2 = artist["url"] as? String ?? ""

        // Bio
        var bio = ""
        var summary = ""
        if let bioObj = artist["bio"] as? [String: Any] {
            bio = bioObj["content"] as? String ?? ""
            summary = bioObj["summary"] as? String ?? ""
            // Strip HTML links from summary
            summary = summary.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            bio = bio.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Stats
        let stats = artist["stats"] as? [String: Any]
        let listeners = stats?["listeners"] as? String ?? ""
        let playcount = stats?["playcount"] as? String ?? ""

        // Tags
        var tags: [String] = []
        if let tagObj = artist["tags"] as? [String: Any],
           let tagList = tagObj["tag"] as? [[String: Any]] {
            tags = tagList.compactMap { $0["name"] as? String }
        }

        // Similar artists
        var similar: [String] = []
        if let simObj = artist["similar"] as? [String: Any],
           let simList = simObj["artist"] as? [[String: Any]] {
            similar = simList.compactMap { $0["name"] as? String }
        }

        // Image (largest available)
        var imageURL: String?
        if let images = artist["image"] as? [[String: Any]] {
            imageURL = images.last?["#text"] as? String
            if imageURL?.isEmpty == true { imageURL = nil }
        }

        return LastFMArtist(
            name: artistName, bio: bio, summary: summary,
            tags: tags, similarArtists: similar,
            listeners: listeners, playcount: playcount,
            imageURL: imageURL, url: url2
        )
    }
}
