import Foundation

// MARK: - Data Model

enum SmartField: String, Codable, CaseIterable {
    case genre = "Genre"
    case artist = "Artist"
    case label = "Label"
    case format = "Format"
    case year = "Year"
    case dr = "DR"
    case playCount = "Play Count"
    case favorite = "Favorite"
    case composer = "Composer"
    case country = "Country"

    var isNumeric: Bool {
        switch self {
        case .year, .dr, .playCount: return true
        default: return false
        }
    }

    var isBoolean: Bool { self == .favorite }
    var isString: Bool { !isNumeric && !isBoolean }
}

enum SmartOperator: String, Codable, CaseIterable {
    case equals = "is"
    case notEquals = "is not"
    case contains = "contains"
    case notContains = "doesn't contain"
    case greaterThan = ">"
    case lessThan = "<"
    case between = "between"
    case isTrue = "yes"
    case isFalse = "no"

    static func available(for field: SmartField) -> [SmartOperator] {
        if field.isBoolean { return [.isTrue, .isFalse] }
        if field.isNumeric { return [.equals, .greaterThan, .lessThan, .between] }
        return [.contains, .notContains, .equals, .notEquals]
    }
}

enum SmartMatch: String, Codable, CaseIterable {
    case all = "all"
    case any = "any"
}

struct SmartRule: Codable, Identifiable {
    let id: UUID
    var field: SmartField
    var op: SmartOperator
    var value: String
    var value2: String  // for "between"

    init(field: SmartField = .genre, op: SmartOperator = .contains, value: String = "", value2: String = "") {
        self.id = UUID()
        self.field = field
        self.op = op
        self.value = value
        self.value2 = value2
    }
}

struct SmartPlaylist: Codable, Identifiable {
    let id: UUID
    var name: String
    var match: SmartMatch
    var rules: [SmartRule]
    var limit: Int?

    init(name: String = "New Playlist") {
        self.id = UUID()
        self.name = name
        self.match = .all
        self.rules = [SmartRule()]
        self.limit = nil
    }
}

// MARK: - Persistence

extension SmartPlaylist {
    private static let key = "smartPlaylists"

    static func loadAll() -> [SmartPlaylist] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SmartPlaylist].self, from: data)) ?? []
    }

    static func saveAll(_ playlists: [SmartPlaylist]) {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Evaluation Engine

extension SmartPlaylist {
    func evaluate(
        albums: [Album],
        playCounts: [String: Int] = [:],
        favoriteFiles: Set<String> = []
    ) -> [Track] {
        var allTracks: [(Track, Album)] = []
        for album in albums {
            for track in album.tracks {
                allTracks.append((track, album))
            }
        }

        let matched = allTracks.filter { track, album in
            let results = rules.map { rule in
                evaluateRule(rule, track: track, album: album, playCounts: playCounts, favoriteFiles: favoriteFiles)
            }
            switch match {
            case .all: return results.allSatisfy { $0 }
            case .any: return results.contains { $0 }
            }
        }

        var tracks = matched.map(\.0)
        if let limit, tracks.count > limit {
            tracks = Array(tracks.prefix(limit))
        }
        return tracks
    }

    private func evaluateRule(
        _ rule: SmartRule,
        track: Track,
        album: Album,
        playCounts: [String: Int],
        favoriteFiles: Set<String>
    ) -> Bool {
        switch rule.field {
        case .genre:
            let genres = track.genre.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            let allGenres = genres + album.genres
            return matchString(rule, values: allGenres)
        case .artist:
            return matchString(rule, values: [track.artist, track.albumArtist])
        case .label:
            return matchString(rule, values: [track.label, album.label])
        case .format:
            let ext = (track.file as NSString).pathExtension.uppercased()
            // "DSD" matches DSF and DFF
            if rule.value.uppercased() == "DSD" {
                let isDSD = ext == "DSF" || ext == "DFF"
                return rule.op == .equals ? isDSD : !isDSD
            }
            return matchString(rule, values: [ext])
        case .year:
            let year = Int(String(track.date.prefix(4))) ?? 0
            return matchNumeric(rule, value: year)
        case .dr:
            return matchNumeric(rule, value: track.dr ?? 0)
        case .playCount:
            return matchNumeric(rule, value: playCounts[track.file] ?? 0)
        case .favorite:
            let isFav = track.isFavorite || favoriteFiles.contains(track.file)
            return rule.op == .isTrue ? isFav : !isFav
        case .composer:
            return matchString(rule, values: [track.composer])
        case .country:
            return matchString(rule, values: [track.country])
        }
    }

    private func matchString(_ rule: SmartRule, values: [String]) -> Bool {
        let query = rule.value.lowercased()
        switch rule.op {
        case .contains:
            return values.contains { $0.lowercased().contains(query) }
        case .notContains:
            return !values.contains { $0.lowercased().contains(query) }
        case .equals:
            return values.contains { $0.lowercased() == query }
        case .notEquals:
            return !values.contains { $0.lowercased() == query }
        default:
            return false
        }
    }

    private func matchNumeric(_ rule: SmartRule, value: Int) -> Bool {
        let v1 = Int(rule.value) ?? 0
        switch rule.op {
        case .equals: return value == v1
        case .greaterThan: return value > v1
        case .lessThan: return value < v1
        case .between:
            let v2 = Int(rule.value2) ?? 0
            return value >= v1 && value <= v2
        default: return false
        }
    }
}
