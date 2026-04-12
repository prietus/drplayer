import Foundation

/// Certified pressing info linked to an album via OBI Scanner identification.
///
/// Sidecar file `.drmobile-pressing.json` is cross-platform compatible with
/// DrMobile — certify on mobile, see badge on Mac and vice versa.
struct PressingInfo: Codable {
    let discogsId: Int
    let catalogNumber: String
    let label: String
    let country: String
    let year: String
    let formats: [String]
    let masteringEngineer: String
    let url: String

    // v2 — audiophile enrichment
    let cutBy: String
    let pressedAt: String
    let recordedAt: String
    let mixedAt: String
    let matrixRunout: String

    init(
        discogsId: Int, catalogNumber: String, label: String, country: String,
        year: String, formats: [String], masteringEngineer: String, url: String,
        cutBy: String = "", pressedAt: String = "", recordedAt: String = "",
        mixedAt: String = "", matrixRunout: String = ""
    ) {
        self.discogsId = discogsId
        self.catalogNumber = catalogNumber
        self.label = label
        self.country = country
        self.year = year
        self.formats = formats
        self.masteringEngineer = masteringEngineer
        self.url = url
        self.cutBy = cutBy
        self.pressedAt = pressedAt
        self.recordedAt = recordedAt
        self.mixedAt = mixedAt
        self.matrixRunout = matrixRunout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        discogsId = try c.decode(Int.self, forKey: .discogsId)
        catalogNumber = try c.decode(String.self, forKey: .catalogNumber)
        label = try c.decode(String.self, forKey: .label)
        country = try c.decode(String.self, forKey: .country)
        year = try c.decode(String.self, forKey: .year)
        formats = try c.decode([String].self, forKey: .formats)
        masteringEngineer = try c.decode(String.self, forKey: .masteringEngineer)
        url = try c.decode(String.self, forKey: .url)
        cutBy = (try? c.decodeIfPresent(String.self, forKey: .cutBy)) ?? ""
        pressedAt = (try? c.decodeIfPresent(String.self, forKey: .pressedAt)) ?? ""
        recordedAt = (try? c.decodeIfPresent(String.self, forKey: .recordedAt)) ?? ""
        mixedAt = (try? c.decodeIfPresent(String.self, forKey: .mixedAt)) ?? ""
        matrixRunout = (try? c.decodeIfPresent(String.self, forKey: .matrixRunout)) ?? ""
    }

    var formatDisplay: String { formats.joined(separator: ", ") }

    var hasDetailedInfo: Bool {
        !cutBy.isEmpty || !pressedAt.isEmpty || !recordedAt.isEmpty
            || !mixedAt.isEmpty || !matrixRunout.isEmpty
    }
}

/// Persists certified pressings as sidecar JSON files inside each album folder.
/// Compatible with DrMobile's sidecar format — shared via NFS/WebDAV.
enum PressingCertification {

    struct Sidecar: Codable {
        let version: Int
        let certifiedAt: Date
        let certifiedBy: String
        let info: PressingInfo

        static let filename = ".drmobile-pressing.json"
        static let currentVersion = 2
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Read sidecar from local album folder (NFS-mounted).
    static func read(albumFullPath: String) -> PressingInfo? {
        let resolved = (albumFullPath as NSString).resolvingSymlinksInPath
        let path = "\(resolved)/\(Sidecar.filename)"
        guard let data = FileManager.default.contents(atPath: path),
              let sidecar = try? decoder.decode(Sidecar.self, from: data) else { return nil }
        return sidecar.info
    }

    /// Write sidecar to local album folder.
    static func write(albumFullPath: String, info: PressingInfo) {
        let resolved = (albumFullPath as NSString).resolvingSymlinksInPath
        let path = "\(resolved)/\(Sidecar.filename)"
        let sidecar = Sidecar(
            version: Sidecar.currentVersion,
            certifiedAt: Date(),
            certifiedBy: "DrPlayer",
            info: info
        )
        guard let data = try? encoder.encode(sidecar) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    static func remove(albumFullPath: String) {
        let resolved = (albumFullPath as NSString).resolvingSymlinksInPath
        try? FileManager.default.removeItem(atPath: "\(resolved)/\(Sidecar.filename)")
    }
}

/// In-memory store for certified pressings. Observable so the UI updates
/// automatically when a new certification arrives via the URL callback.
@MainActor
final class PressingStore: ObservableObject {
    static let shared = PressingStore()

    @Published private(set) var cache: [String: PressingInfo] = [:]

    private init() {}

    func get(albumFullPath: String) -> PressingInfo? {
        let resolved = (albumFullPath as NSString).resolvingSymlinksInPath
        if let cached = cache[resolved] { return cached }
        if let info = PressingCertification.read(albumFullPath: resolved) {
            cache[resolved] = info
            return info
        }
        return nil
    }

    func set(albumFullPath: String, info: PressingInfo) {
        let resolved = (albumFullPath as NSString).resolvingSymlinksInPath
        cache[resolved] = info
        PressingCertification.write(albumFullPath: resolved, info: info)
    }

    /// Called from the drplayer://identify URL handler.
    /// Fetches the release from Discogs and persists.
    func certify(albumFullPath: String, discogsId: Int) {
        Task {
            guard let release = await DiscogsService.fetchRelease(id: discogsId) else { return }
            let info = release.toPressingInfo()
            await MainActor.run {
                self.set(albumFullPath: albumFullPath, info: info)
            }
        }
    }
}
