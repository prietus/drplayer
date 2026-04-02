import SwiftUI

/// Full-panel view comparing local editions of an album with Loudness War DB entries.
/// Shows release-identifying info (label, catalog, barcode, country, codec, source)
/// so the user can identify exactly which pressing they have and what's best overall.
struct EditionComparisonView: View {
    let album: Album
    let allAlbums: [Album]
    let onPlayFile: (String) -> Void
    let onSetPreferred: ((String) -> Void)?
    let preferredFiles: Set<String>
    let onBack: () -> Void
    var onScanDR: ((Int) async -> Void)? = nil
    var onSelectLabel: ((String) -> Void)? = nil

    @State private var loudnessWarEntries: [LoudnessWarEntry] = []
    @State private var loudnessWarLoading = false
    @State private var releaseInfo: [String: MBRelease] = [:]  // album.id -> release
    @State private var discogsInfo: [String: DiscogsRelease] = [:]  // album.id -> discogs
    @State private var computedDR: [String: Int] = [:]  // album.id -> avg DR

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Back button
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(album.title)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

                // Title
                Text(String(localized: "Compare editions", defaultValue: "Compare editions"))
                    .font(.title2.bold())
                    .padding(.horizontal)
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    Text(album.artist + " — " + album.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    let headerDR = album.avgDR
                        ?? computedDR[album.id]
                        ?? {
                            let drs = album.tracks.compactMap(\.dr).filter { $0 > 0 }
                            guard !drs.isEmpty else { return nil as Int? }
                            return drs.reduce(0, +) / drs.count
                        }()
                    if let dr = headerDR, dr > 0 {
                        Text("DR\(dr)")
                            .font(.caption.bold().monospaced())
                            .foregroundColor(drColor(dr))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(drColor(dr).opacity(0.15)))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)

                // My editions (local)
                sectionTitle(String(localized: "My versions", defaultValue: "My versions"))
                myEditionsSection

                Divider().padding(.horizontal).padding(.vertical, 8)

                // Loudness War DB
                sectionTitle("Loudness War DB")
                loudnessWarSection

                Spacer().frame(height: 20)
            }
        }
        .task {
            await loadLoudnessWar()
        }
        .task {
            await loadReleaseInfo()
        }
        .task {
            await scanAllDR()
        }
    }

    // MARK: - Section Title

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 6)
    }

    // MARK: - My Editions

    private var myEditions: [Album] {
        let titleNorm = normalizeForMatch(album.title)
        let artistNorm = album.artist.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        let others = allAlbums.filter { other in
            let otherArtist = other.artist.lowercased()
                .folding(options: .diacriticInsensitive, locale: .current)
            guard otherArtist == artistNorm else { return false }
            return normalizeForMatch(other.title) == titleNorm
        }

        // Rank by AudioQualityScore (use first track as representative)
        let scored = others.map { ed -> (album: Album, score: Int) in
            let representative = ed.tracks.first ?? Track(
                id: "", title: "", artist: "", albumArtist: "", album: "",
                file: "", pos: 0, duration: 0, genre: "", date: "",
                trackNumber: "", disc: "", composer: "", performer: "",
                conductor: "", label: "", originalDate: "",
                musicbrainzTrackId: "", musicbrainzAlbumId: "", country: "")
            let s = AudioQualityScore.score(track: representative, album: ed)
            return (album: ed, score: s.total)
        }

        return scored.sorted { $0.score > $1.score }.map(\.album)
    }

    private var myEditionsSection: some View {
        let editions = myEditions
        let bestId = editions.first?.id

        return VStack(spacing: 0) {
            ForEach(Array(editions.enumerated()), id: \.element.id) { idx, edition in
                let isCurrent = edition.id == album.id
                let isBest = edition.id == bestId
                let score = {
                    let representative = edition.tracks.first ?? Track(
                        id: "", title: "", artist: "", albumArtist: "", album: "",
                        file: "", pos: 0, duration: 0, genre: "", date: "",
                        trackNumber: "", disc: "", composer: "", performer: "",
                        conductor: "", label: "", originalDate: "",
                        musicbrainzTrackId: "", musicbrainzAlbumId: "", country: "")
                    return AudioQualityScore.score(track: representative, album: edition)
                }()
                let mb = releaseInfo[edition.id]
                let dg = discogsInfo[edition.id]

                VStack(alignment: .leading, spacing: 4) {
                    // Row 1: title + badges
                    HStack(spacing: 6) {
                        Button {
                            onPlayFile(edition.tracks.first?.file ?? "")
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)

                        Text(edition.title)
                            .font(.callout)
                            .fontWeight(isBest ? .bold : .regular)
                            .lineLimit(1)

                        if isBest && editions.count > 1 {
                            Text(String(localized: "BEST", defaultValue: "BEST"))
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundColor(.green)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.green.opacity(0.15)))
                        }
                        if isCurrent {
                            Text(String(localized: "CURRENT", defaultValue: "CURRENT"))
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.blue.opacity(0.15)))
                        }

                        Spacer()

                        Text("\(score.total)pts")
                            .font(.system(size: 9, weight: .medium).monospaced())
                            .foregroundStyle(.quaternary)
                    }

                    // Row 2: technical info
                    let editionDR = edition.avgDR
                        ?? computedDR[edition.id]
                        ?? {
                            let drs = edition.tracks.compactMap(\.dr).filter { $0 > 0 }
                            guard !drs.isEmpty else { return nil as Int? }
                            return drs.reduce(0, +) / drs.count
                        }()
                    HStack(spacing: 8) {
                        if !edition.format.isEmpty {
                            Text(edition.format)
                                .font(.caption2.monospaced().bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(formatColor(edition.format).opacity(0.15)))
                                .foregroundColor(formatColor(edition.format))
                        }
                        if let dr = editionDR, dr > 0 {
                            HStack(spacing: 3) {
                                Text("DR\(dr)")
                                    .font(.caption2.bold().monospaced())
                                    .foregroundColor(drColor(dr))
                                drBar(dr)
                            }
                        } else {
                            Text("DR …")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.quaternary)
                        }
                        Text("\(edition.tracks.count) tracks")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(edition.formattedDuration)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, 36)

                    // Row 3: release info from metadata + APIs
                    let releaseDetails = buildReleaseDetails(edition: edition, mb: mb, dg: dg)
                    if !releaseDetails.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                            ForEach(releaseDetails, id: \.label) { detail in
                                GridRow {
                                    Text(detail.label)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 80, alignment: .trailing)
                                    if detail.label == "Label", let onSelectLabel {
                                        Button { onSelectLabel(detail.value) } label: {
                                            Text(detail.value)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                                    } else {
                                        Text(detail.value)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                        .padding(.leading, 36)
                    }

                    // Row 4: folder path
                    Text(edition.folder)
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(.quaternary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .padding(.leading, 36)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    isBest && editions.count > 1 ? Color.green.opacity(0.05) :
                    score.badge == .warning ? Color.red.opacity(0.03) : Color.clear
                )

                if idx < editions.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
    }

    private struct ReleaseDetail: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private func buildReleaseDetails(edition: Album, mb: MBRelease?, dg: DiscogsRelease?) -> [ReleaseDetail] {
        var details: [ReleaseDetail] = []

        // Label: prefer API when matched by catalog (more specific sub-label), fallback to metadata
        let apiLabel: String? = {
            if let mb, !mb.label.isEmpty, !mb.catalogNumber.isEmpty { return mb.label }
            if let dg, !dg.label.isEmpty, !dg.catalogNumber.isEmpty { return dg.label }
            return nil
        }()
        let label = apiLabel ?? (!edition.label.isEmpty ? edition.label : (mb?.label ?? dg?.label ?? ""))
        if !label.isEmpty {
            details.append(ReleaseDetail(label: String(localized: "Label", defaultValue: "Label"), value: label))
        }

        // Catalog number
        let catalog = mb?.catalogNumber ?? dg?.catalogNumber ?? ""
        if !catalog.isEmpty {
            details.append(ReleaseDetail(label: String(localized: "Catalog", defaultValue: "Catalog"), value: catalog))
        }

        // Barcode
        let barcode = mb?.barcode ?? ""
        if !barcode.isEmpty {
            details.append(ReleaseDetail(label: String(localized: "Barcode", defaultValue: "Barcode"), value: barcode))
        }

        // Country
        let country = mb?.country ?? dg?.country ?? ""
        if !country.isEmpty {
            details.append(ReleaseDetail(label: String(localized: "Country", defaultValue: "Country"), value: country))
        }

        // Date
        let date = !edition.date.isEmpty ? edition.date : (mb?.date ?? "")
        if !date.isEmpty {
            details.append(ReleaseDetail(label: String(localized: "Date", defaultValue: "Date"), value: date))
        }

        // Original date (if different)
        if !edition.originalDate.isEmpty && edition.originalDate != edition.date {
            details.append(ReleaseDetail(label: "Original", value: edition.originalDate))
        }

        // Discogs format (CD, Vinyl, SACD, etc.)
        if let dg, !dg.formats.isEmpty {
            details.append(ReleaseDetail(label: String(localized: "Source", defaultValue: "Source"), value: dg.formats.joined(separator: ", ")))
        }

        // Producer / Engineer / Mastering from MusicBrainz
        if let mb {
            if !mb.producers.isEmpty {
                details.append(ReleaseDetail(label: "Producer", value: mb.producers.joined(separator: ", ")))
            }
            if !mb.engineers.isEmpty {
                details.append(ReleaseDetail(label: "Engineer", value: mb.engineers.joined(separator: ", ")))
            }
            if !mb.masteringEngineers.isEmpty {
                details.append(ReleaseDetail(label: "Mastering", value: mb.masteringEngineers.joined(separator: ", ")))
            }
        }

        return details
    }

    // MARK: - Loudness War DB

    @ViewBuilder
    private var loudnessWarSection: some View {
        if loudnessWarLoading {
            HStack {
                ProgressView().controlSize(.small)
                Text(String(localized: "Querying Loudness War DB...",
                            defaultValue: "Querying Loudness War DB..."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        } else if loudnessWarEntries.isEmpty {
            Text(String(localized: "No data found in Loudness War DB for this album",
                        defaultValue: "No data found in Loudness War DB for this album"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
        } else {
            let myDR = album.avgDR ?? 0

            VStack(spacing: 0) {
                ForEach(Array(loudnessWarEntries.enumerated()), id: \.element.id) { idx, entry in
                    loudnessWarRow(entry, myDR: myDR)
                    if idx < loudnessWarEntries.count - 1 {
                        Divider().padding(.leading, 20)
                    }
                }

                // Footer
                HStack {
                    Text("dr.loudness-war.info")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .italic()
                    Spacer()
                    Button {
                        let artist = album.artist
                            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        let albumName = album.title
                            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "https://dr.loudness-war.info/album/list?artist=\(artist)&album=\(albumName)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text(String(localized: "Open in browser", defaultValue: "Open in browser"))
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top, 6)
            }
        }
    }

    private func loudnessWarRow(_ entry: LoudnessWarEntry, myDR: Int) -> some View {
        let matchesMine = myDR > 0 && entry.drAvg == myDR
        let isBetter = myDR > 0 && entry.drAvg > myDR

        return VStack(alignment: .leading, spacing: 3) {
            // Row 1: album title (clickable → loudness-war.info) + DR + year
            HStack(spacing: 6) {
                Button {
                    if let url = URL(string: "https://dr.loudness-war.info/album/view/\(entry.id)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text(entry.album)
                        .font(.callout)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                Spacer()

                Text("DR\(entry.drAvg)")
                    .font(.caption.bold().monospaced())
                    .foregroundColor(drColor(entry.drAvg))
                Text("(\(entry.drMin)–\(entry.drMax))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            // Row 2: codec, source, year
            HStack(spacing: 6) {
                Text(entry.codec)
                    .font(.caption2.monospaced().bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(
                        entry.codec.lowercased().contains("lossless") ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15)
                    ))
                    .foregroundColor(entry.codec.lowercased().contains("lossless") ? .blue : .orange)

                Text(entry.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(entry.year)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Row 3: label, catalog, country (from detail page)
            let details = [entry.label, entry.catalogNumber, entry.country].filter { !$0.isEmpty }
            if !details.isEmpty {
                HStack(spacing: 8) {
                    if !entry.label.isEmpty {
                        HStack(spacing: 3) {
                            Text(String(localized: "Label", defaultValue: "Label"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(entry.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !entry.catalogNumber.isEmpty {
                        Text(entry.catalogNumber)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if !entry.country.isEmpty {
                        Text(entry.country)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(
            matchesMine ? Color.accentColor.opacity(0.08) :
            isBetter ? Color.green.opacity(0.04) :
            Color.clear
        )
    }

    // MARK: - Helpers

    private func normalizeForMatch(_ s: String) -> String {
        var cleaned = s
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        return cleaned.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    private func drColor(_ dr: Int) -> Color {
        switch dr {
        case 14...: return .green
        case 10...13: return .yellow
        case 7...9: return .orange
        default: return .red
        }
    }

    private func drBar(_ dr: Int) -> some View {
        let normalized = min(Double(dr) / 20.0, 1.0)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(drColor(dr)).frame(width: geo.size.width * normalized)
            }
        }
        .frame(width: 60, height: 6)
    }

    private func formatColor(_ format: String) -> Color {
        let f = format.uppercased()
        if f.contains("DSF") || f.contains("DFF") || f.contains("DSD") { return .green }
        if f.contains("FLAC") || f.contains("WAV") || f.contains("AIFF") { return .blue }
        if f.contains("MQA") { return .purple }
        if f.contains("MP3") || f.contains("AAC") { return .orange }
        return .secondary
    }

    /// Clean album title for API searches
    private func cleanTitle(_ title: String) -> String {
        var cleaned = title
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201C}\u{201D}\u{00AB}\u{00BB}"))
        if let range = cleaned.range(of: #"^\d{4}\s+"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        if let range = cleaned.range(of: #"\s*-\s*(remaster|deluxe|bonus).*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Data Loading

    private func loadLoudnessWar() async {
        loudnessWarLoading = true
        let entries = await LoudnessWarService.search(artist: album.artist, album: album.title)
        loudnessWarEntries = entries
        loudnessWarLoading = false

        // Fetch detail pages in parallel for label/catalog/country
        await withTaskGroup(of: (Int, LoudnessWarEntry).self) { group in
            for (idx, entry) in entries.enumerated() {
                group.addTask {
                    let detailed = await LoudnessWarService.fetchDetail(entry: entry)
                    return (idx, detailed)
                }
            }
            for await (idx, detailed) in group {
                if idx < loudnessWarEntries.count {
                    loudnessWarEntries[idx] = detailed
                }
            }
        }
    }

    private func scanAllDR() async {
        let musicBase = AppSettings.shared.musicLibraryPath

        for edition in myEditions {
            let editionId = edition.id

            // If we already computed locally, skip
            if computedDR[editionId] != nil { continue }

            // If avgDR already available, use it directly
            if let existing = edition.avgDR {
                computedDR[editionId] = existing
                continue
            }

            let tracks = edition.tracks

            // Analyze all tracks in background
            let dr = await Task.detached {
                var drs: [Int] = []
                for track in tracks {
                    if let cached = track.dr, cached > 0 {
                        drs.append(cached)
                        continue
                    }
                    let fullPath = AppSettings.shared.resolveFilePath(track.file)
                    if let result = DR14Analyzer.analyze(filePath: fullPath) {
                        drs.append(result.dr)
                    }
                }
                guard !drs.isEmpty else { return nil as Int? }
                return drs.reduce(0, +) / drs.count
            }.value

            if let dr {
                computedDR[editionId] = dr
            }

            // Also trigger ViewModel scan so it persists
            if let onScanDR, let idx = allAlbums.firstIndex(where: { $0.id == editionId }) {
                await onScanDR(idx)
            }
        }
    }

    /// Extract catalog number from album title parentheses.
    private func extractCatalog(_ title: String) -> String? {
        let patterns = [
            #"\(([A-Z]{2,}[\s-]?\d[\w\s-]*)\)"#,
            #"\((\d+[\s-][A-Z][\w\s-]*)\)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range(at: 1), in: title) {
                let candidate = String(title[range])
                let lower = candidate.lowercased()
                if lower.contains("remaster") || lower.contains("deluxe") ||
                   lower.contains("live") || lower.contains("edition") { continue }
                return candidate
            }
        }
        return nil
    }

    private func loadReleaseInfo() async {
        // Load MusicBrainz + Discogs for each local edition
        for edition in myEditions {
            let cleanAlbum = cleanTitle(edition.title)
            let catalogFromTitle = extractCatalog(edition.title)

            // MusicBrainz: catalog → ID → title
            var mb: MBRelease?
            if !edition.musicbrainzAlbumId.isEmpty {
                mb = await MusicBrainzService.fetchRelease(id: edition.musicbrainzAlbumId)
            }
            if mb == nil, let catno = catalogFromTitle {
                mb = await MusicBrainzService.searchByCatalog(artist: edition.artist, catno: catno)
            }
            if mb == nil {
                mb = await MusicBrainzService.searchRelease(artist: edition.artist, album: cleanAlbum)
            }
            if let mb {
                releaseInfo[edition.id] = mb
            }

            // Discogs: catalog from title → MB catalog → barcode → search
            let mbCountry = mb?.country
            var dg: DiscogsRelease?
            if let catno = catalogFromTitle {
                dg = await DiscogsService.searchByCatalog(catno, country: mbCountry)
            }
            if dg == nil, let catno = mb?.catalogNumber, !catno.isEmpty {
                dg = await DiscogsService.searchByCatalog(catno, country: mbCountry)
            }
            if dg == nil, let barcode = mb?.barcode, !barcode.isEmpty {
                dg = await DiscogsService.searchByBarcode(barcode, country: mbCountry)
            }
            if dg == nil {
                dg = await DiscogsService.search(artist: edition.artist, album: cleanAlbum)
            }
            if let dg {
                discogsInfo[edition.id] = dg
            }
        }
    }
}
