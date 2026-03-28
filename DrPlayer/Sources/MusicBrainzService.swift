import Foundation

struct MBRelease {
    let id: String
    let title: String
    let artist: String
    let date: String
    let country: String
    let label: String
    let catalogNumber: String
    let barcode: String
    let status: String
    let credits: [(name: String, role: String)]
    let wikipediaSlug: String?
    let genres: [String]
}

struct MBArtistInfo {
    let id: String
    let name: String
    let type: String // "Group", "Person"
    let beginDate: String
    let endDate: String
    let area: String
    let wikipediaSlug: String?
    let members: [(name: String, role: String, period: String)]
}

enum MusicBrainzService {
    private static let baseURL = "https://musicbrainz.org/ws/2"
    private static let userAgent = "DrPlayer/1.0 (carlos@drplayer)"

    // MARK: - Release search

    static func searchRelease(artist: String, album: String) async -> MBRelease? {
        let query = "release:\(album) AND artist:\(artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "\(baseURL)/release/?query=\(query)&fmt=json&limit=5"
        guard let url = URL(string: urlStr) else { return nil }

        guard let data = await fetch(url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let releases = json["releases"] as? [[String: Any]],
              let best = releases.first else { return nil }

        let releaseId = best["id"] as? String ?? ""

        // Fetch full release with relationships
        return await fetchRelease(id: releaseId)
    }

    static func fetchRelease(id: String) async -> MBRelease? {
        let cacheKey = "mb_release_\(id)"
        if let cached = MetadataCache.get(cacheKey),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
            return parseRelease(id: id, json: json)
        }

        let urlStr = "\(baseURL)/release/\(id)?inc=artist-credits+labels+recordings+release-groups+url-rels+artist-rels+recording-level-rels+genres&fmt=json"
        guard let url = URL(string: urlStr) else { return nil }

        // Rate limit: 1 req/sec
        try? await Task.sleep(for: .seconds(1))

        guard let data = await fetch(url) else { return nil }
        MetadataCache.set(cacheKey, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseRelease(id: id, json: json)
    }

    private static func parseRelease(id: String, json: [String: Any]) -> MBRelease? {
        let title = json["title"] as? String ?? ""
        let date = json["date"] as? String ?? ""
        let country = json["country"] as? String ?? ""
        let status = json["status"] as? String ?? ""
        let barcode = json["barcode"] as? String ?? ""

        // Artist
        var artist = ""
        if let credits = json["artist-credit"] as? [[String: Any]] {
            artist = credits.compactMap { $0["name"] as? String }.joined(separator: ", ")
        }

        // Label
        var label = ""
        var catalogNumber = ""
        if let labelInfo = json["label-info"] as? [[String: Any]], let first = labelInfo.first {
            if let labelObj = first["label"] as? [String: Any] {
                label = labelObj["name"] as? String ?? ""
            }
            catalogNumber = first["catalog-number"] as? String ?? ""
        }

        // Credits from relations
        var credits: [(name: String, role: String)] = []
        if let relations = json["relations"] as? [[String: Any]] {
            for rel in relations {
                let type = rel["type"] as? String ?? ""
                if let artistObj = rel["artist"] as? [String: Any] {
                    let name = artistObj["name"] as? String ?? ""
                    let attrs = (rel["attributes"] as? [String])?.joined(separator: ", ") ?? type
                    credits.append((name: name, role: attrs))
                }
            }
        }

        // Also get credits from media/recordings
        if let media = json["media"] as? [[String: Any]] {
            for medium in media {
                if let tracks = medium["tracks"] as? [[String: Any]] {
                    for track in tracks {
                        if let recording = track["recording"] as? [String: Any],
                           let relations = recording["relations"] as? [[String: Any]] {
                            for rel in relations {
                                let type = rel["type"] as? String ?? ""
                                if let artistObj = rel["artist"] as? [String: Any] {
                                    let name = artistObj["name"] as? String ?? ""
                                    let attrs = (rel["attributes"] as? [String])?.joined(separator: ", ") ?? type
                                    if !credits.contains(where: { $0.name == name && $0.role == attrs }) {
                                        credits.append((name: name, role: attrs))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Wikipedia link from release-group
        var wikiSlug: String? = nil
        if let rg = json["release-group"] as? [String: Any],
           let rels = rg["relations"] as? [[String: Any]] {
            for rel in rels {
                if let urlObj = rel["url"] as? [String: Any],
                   let resource = urlObj["resource"] as? String,
                   resource.contains("wikipedia.org") {
                    wikiSlug = resource.components(separatedBy: "/wiki/").last
                }
            }
        }
        // Also check direct URL relations
        if wikiSlug == nil, let relations = json["relations"] as? [[String: Any]] {
            for rel in relations {
                if let urlObj = rel["url"] as? [String: Any],
                   let resource = urlObj["resource"] as? String,
                   resource.contains("wikipedia.org") {
                    wikiSlug = resource.components(separatedBy: "/wiki/").last
                }
            }
        }

        // Genres
        var genres: [String] = []
        if let rg = json["release-group"] as? [String: Any],
           let genreList = rg["genres"] as? [[String: Any]] {
            genres = genreList.compactMap { $0["name"] as? String }
        }

        return MBRelease(
            id: id, title: title, artist: artist, date: date,
            country: country, label: label, catalogNumber: catalogNumber,
            barcode: barcode, status: status, credits: credits,
            wikipediaSlug: wikiSlug, genres: genres
        )
    }

    // MARK: - Artist info

    static func searchArtist(name: String) async -> MBArtistInfo? {
        let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "\(baseURL)/artist/?query=artist:\(query)&fmt=json&limit=3"
        guard let url = URL(string: urlStr) else { return nil }

        guard let data = await fetch(url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artists = json["artists"] as? [[String: Any]],
              let best = artists.first,
              let artistId = best["id"] as? String else { return nil }

        return await fetchArtist(id: artistId)
    }

    static func fetchArtist(id: String) async -> MBArtistInfo? {
        let cacheKey = "mb_artist_\(id)"
        if let cached = MetadataCache.get(cacheKey),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
            return parseArtist(id: id, json: json)
        }

        let urlStr = "\(baseURL)/artist/\(id)?inc=url-rels+artist-rels+genres&fmt=json"
        guard let url = URL(string: urlStr) else { return nil }

        try? await Task.sleep(for: .seconds(1))

        guard let data = await fetch(url) else { return nil }
        MetadataCache.set(cacheKey, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseArtist(id: id, json: json)
    }

    private static func parseArtist(id: String, json: [String: Any]) -> MBArtistInfo? {
        let name = json["name"] as? String ?? ""
        let type = json["type"] as? String ?? ""
        let beginDate = (json["life-span"] as? [String: Any])?["begin"] as? String ?? ""
        let endDate = (json["life-span"] as? [String: Any])?["end"] as? String ?? ""
        let area = (json["area"] as? [String: Any])?["name"] as? String ?? ""

        // Wikipedia
        var wikiSlug: String? = nil
        if let relations = json["relations"] as? [[String: Any]] {
            for rel in relations {
                if let urlObj = rel["url"] as? [String: Any],
                   let resource = urlObj["resource"] as? String,
                   resource.contains("wikipedia.org") {
                    wikiSlug = resource.components(separatedBy: "/wiki/").last
                    break
                }
            }
        }

        // Band members (deduplicated by name+period)
        var members: [(name: String, role: String, period: String)] = []
        var memberKeys = Set<String>()
        if let relations = json["relations"] as? [[String: Any]] {
            for rel in relations {
                let type = rel["type"] as? String ?? ""
                if type == "member of band",
                   let artistObj = rel["artist"] as? [String: Any] {
                    let memberName = artistObj["name"] as? String ?? ""
                    let attrs = (rel["attributes"] as? [String])?.joined(separator: ", ") ?? ""
                    let begin = (rel["begin"] as? String) ?? ""
                    let end = (rel["end"] as? String) ?? ""
                    let period = begin.isEmpty ? "" : "\(begin)–\(end.isEmpty ? "present" : end)"
                    let key = "\(memberName)|\(period)"
                    if memberKeys.insert(key).inserted {
                        members.append((name: memberName, role: attrs, period: period))
                    }
                }
            }
        }

        return MBArtistInfo(
            id: id, name: name, type: type,
            beginDate: beginDate, endDate: endDate, area: area,
            wikipediaSlug: wikiSlug, members: members
        )
    }

    // MARK: - Fetch helper

    private static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return data
    }
}
