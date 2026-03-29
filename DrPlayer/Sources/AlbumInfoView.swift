import SwiftUI

struct AlbumInfoView: View {
    let artist: String
    let albumTitle: String
    let musicbrainzAlbumId: String

    @State private var release: MBRelease?
    @State private var artistInfo: MBArtistInfo?
    @State private var discogs: DiscogsRelease?
    @State private var albumWiki: WikiSummary?
    @State private var artistWiki: WikiSummary?
    @State private var loading = true

    // Capa 3 toggles
    @State private var showFullRelease = false
    @State private var showDiscogs = false
    @State private var showCredits = false
    @State private var showMembers = false

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            if loading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                // ─── CAPA 2: "Lo importante si me interesa" ───

                // Release summary badge (compact one-liner)
                if let rel = release {
                    releaseSummaryBadge(rel)
                }

                // Album Wikipedia
                if let wiki = albumWiki {
                    wikiSection(title: "About the album", summary: wiki)
                }

                // Artist Wikipedia (only if different article)
                if let wiki = artistWiki,
                   wiki.pageURL != albumWiki?.pageURL {
                    wikiSection(title: "Sobre \(artistInfo?.name ?? artist)", summary: wiki)
                }

                // ─── CAPA 3: "Nerd mode / archivista" ───

                if release != nil || discogs != nil || artistInfo != nil {
                    Divider().padding(.vertical, 4)

                    Text("Details")
                        .font(.caption2.bold())
                        .foregroundStyle(.quaternary)
                        .textCase(.uppercase)
                }

                // MusicBrainz release details
                if let rel = release {
                    collapsibleSection("Release (MusicBrainz)", isExpanded: $showFullRelease) {
                        releaseSection(rel)
                    }
                }

                // Discogs edition
                if let dg = discogs {
                    collapsibleSection("Physical edition (Discogs)", isExpanded: $showDiscogs) {
                        discogsSection(dg)
                    }
                }

                // Credits
                if let rel = release, !rel.credits.isEmpty {
                    collapsibleSection("Credits", isExpanded: $showCredits) {
                        creditsSection(rel.credits)
                    }
                }

                // Band members
                if let info = artistInfo, !info.members.isEmpty {
                    collapsibleSection("Members", isExpanded: $showMembers) {
                        membersSection(info)
                    }
                }

                if release == nil && albumWiki == nil && artistWiki == nil && discogs == nil {
                    Text("No additional information")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        }
        .task {
            await loadInfo()
        }
    }

    // MARK: - CAPA 2: Release Summary Badge

    private func releaseSummaryBadge(_ rel: MBRelease) -> some View {
        let parts: [String] = [
            rel.label,
            rel.country,
            rel.date
        ].filter { !$0.isEmpty }

        let line2Parts: [String] = [
            rel.catalogNumber.isEmpty ? nil : "Cat. \(rel.catalogNumber)",
            rel.status.isEmpty ? nil : rel.status,
            discogs.flatMap { $0.formats.isEmpty ? nil : $0.formats.first }
        ].compactMap { $0 }

        return VStack(alignment: .leading, spacing: 3) {
            if !parts.isEmpty {
                Text(parts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !line2Parts.isEmpty {
                Text(line2Parts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Compact external links
            HStack(spacing: 8) {
                if !rel.id.isEmpty {
                    miniLink("MusicBrainz", url: "https://musicbrainz.org/release/\(rel.id)")
                }
                if let dg = discogs {
                    miniLink("Discogs", url: dg.url)
                }
                if let wiki = albumWiki, !wiki.pageURL.isEmpty {
                    miniLink("Wikipedia", url: wiki.pageURL)
                }
            }
            .padding(.top, 2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
    }

    private func miniLink(_ label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }

    // MARK: - CAPA 2: Wikipedia

    private func wikiSection(title: String, summary: WikiSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(summary.extract)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(6)

            if !summary.pageURL.isEmpty {
                Button {
                    if let url = URL(string: summary.pageURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Read more on Wikipedia")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - CAPA 3: Full Release Details

    private func releaseSection(_ rel: MBRelease) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                if !rel.label.isEmpty { infoRow("Label", rel.label) }
                if !rel.catalogNumber.isEmpty { infoRow("Catalog", rel.catalogNumber) }
                if !rel.date.isEmpty { infoRow("Date", rel.date) }
                if !rel.country.isEmpty { infoRow("Country", rel.country) }
                if !rel.barcode.isEmpty { infoRow("Barcode", rel.barcode) }
                if !rel.status.isEmpty { infoRow("Status", rel.status) }
                if !rel.genres.isEmpty { infoRow("Genres", rel.genres.joined(separator: ", ")) }
            }
            sourceLabel("MusicBrainz")
        }
    }

    private func discogsSection(_ dg: DiscogsRelease) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                if !dg.label.isEmpty { infoRow("Label", dg.label) }
                if !dg.catalogNumber.isEmpty { infoRow("Catalog", dg.catalogNumber) }
                if dg.year > 0 { infoRow("Year", String(dg.year)) }
                if !dg.country.isEmpty { infoRow("Country", dg.country) }
                if !dg.formats.isEmpty { infoRow("Format", dg.formats.joined(separator: ", ")) }
                if !dg.styles.isEmpty { infoRow("Styles", dg.styles.joined(separator: ", ")) }
                if let price = dg.lowestPrice { infoRow("Min. price", "$\(price)") }
            }

            if !dg.notes.isEmpty {
                Text(dg.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.top, 2)
            }

            HStack(spacing: 8) {
                miniLink("View on Discogs", url: dg.url)
            }
            sourceLabel("Discogs")
        }
    }

    private func creditsSection(_ credits: [(name: String, role: String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let grouped = Dictionary(grouping: credits, by: { $0.role })
            ForEach(grouped.keys.sorted(), id: \.self) { role in
                HStack(alignment: .top, spacing: 6) {
                    Text(role.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 90, alignment: .trailing)
                    Text(grouped[role]!.map(\.name).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            sourceLabel("MusicBrainz")
        }
    }

    private func membersSection(_ info: MBArtistInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !info.area.isEmpty || !info.beginDate.isEmpty {
                HStack(spacing: 4) {
                    if !info.area.isEmpty {
                        Text(info.area)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if !info.beginDate.isEmpty {
                        Text("· since \(info.beginDate)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            ForEach(info.members, id: \.name) { member in
                HStack(spacing: 4) {
                    Text(member.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !member.role.isEmpty {
                        Text("(\(member.role))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if !member.period.isEmpty {
                        Spacer()
                        Text(member.period)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            sourceLabel("MusicBrainz")
        }
    }

    // MARK: - Collapsible

    private func collapsibleSection<Content: View>(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text(title)
                        .font(.caption.bold())
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sourceLabel(_ source: String) -> some View {
        Text("Source: \(source)")
            .font(.caption2)
            .foregroundStyle(.quaternary)
            .italic()
    }

    // MARK: - Load

    /// Clean album title for API searches:
    /// "1974 Burn" → "Burn", "Machine Head [MQA-CD]" → "Machine Head",
    /// "Beat SHM-CD Legacy Collection 1980" → "Beat"
    private func cleanTitle(_ title: String) -> String {
        var cleaned = title
        // Strip surrounding quotes: "Heroes" → Heroes
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201C}\u{201D}\u{00AB}\u{00BB}"))
        // Remove leading year prefix: "1974 Burn" → "Burn"
        if let range = cleaned.range(of: #"^\d{4}\s+"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove trailing parenthesized content
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove trailing bracketed content
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove format/edition suffixes embedded in title:
        // "Beat SHM-CD Legacy Collection 1980" → "Beat"
        // "Album HDCD" → "Album", "Album MQA-CD" → "Album"
        if let range = cleaned.range(of: #"\s+(SHM-CD|SHM-SACD|HDCD|MQA-CD|XRCD|K2HD|HQCD|Blu-spec CD|UHQCD).*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        // Remove "Legacy Collection YYYY", "Anniversary Edition", etc.
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

    /// Extract catalog number from album title parentheses/brackets.
    /// "A Kind Of Magic (UICY-40261)" → "UICY-40261"
    /// "Machine Head [SHM-SACD]" → nil (not a catalog number)
    private func extractCatalog(_ title: String) -> String? {
        // Match patterns like (UICY-40261), (P28P 25067), (MFSL 1-256)
        // Catalog numbers typically have letters+digits or digits+letters with dashes/spaces
        let patterns = [
            #"\(([A-Z]{2,}[\s-]?\d[\w\s-]*)\)"#,   // (UICY-40261), (P28P 25067)
            #"\((\d+[\s-][A-Z][\w\s-]*)\)"#,         // (276 441 7)
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range(at: 1), in: title) {
                let candidate = String(title[range])
                // Skip common non-catalog parenthesized content
                let lower = candidate.lowercased()
                if lower.contains("remaster") || lower.contains("deluxe") ||
                   lower.contains("live") || lower.contains("edition") ||
                   lower.contains("bonus") || lower.contains("disc") { continue }
                return candidate
            }
        }
        return nil
    }

    /// Detect MusicBrainz format/country hints from album title keywords
    private func detectHints(_ title: String) -> (format: String?, country: String?) {
        let lower = title.lowercased()
        if lower.contains("shm-sacd") || lower.contains("shm sacd") { return ("sacd", "JP") }
        if lower.contains("shm-cd") || lower.contains("shm cd") || lower.contains("uhqcd") ||
           lower.contains("blu-spec") || lower.contains("hqcd") { return ("cd", "JP") }
        if lower.contains("sacd") { return ("sacd", nil) }
        if lower.contains("xrcd") || lower.contains("k2hd") { return (nil, "JP") }
        if lower.contains("vinyl") || lower.contains("lp") { return ("Vinyl", nil) }
        return (nil, nil)
    }

    private func loadInfo() async {
        let cleanAlbum = cleanTitle(albumTitle)
        let catalogFromTitle = extractCatalog(albumTitle)
        let hints = detectHints(albumTitle)

        // MusicBrainz: prefer catalog number → MB ID → format/country-specific → generic
        async let mbRelease: MBRelease? = {
            // 1. Direct lookup by MusicBrainz ID (most precise)
            if !musicbrainzAlbumId.isEmpty {
                return await MusicBrainzService.fetchRelease(id: musicbrainzAlbumId)
            }
            // 2. Search by catalog number extracted from title
            if let catno = catalogFromTitle {
                if let r = await MusicBrainzService.searchByCatalog(artist: artist, catno: catno) {
                    return r
                }
            }
            // 3. Search by title + format/country hints (e.g. SHM-CD → JP)
            if hints.format != nil || hints.country != nil {
                if let r = await MusicBrainzService.searchRelease(artist: artist, album: cleanAlbum, format: hints.format, country: hints.country) {
                    return r
                }
            }
            // 4. Search by clean title
            if let r = await MusicBrainzService.searchRelease(artist: artist, album: cleanAlbum) {
                return r
            }
            if cleanAlbum != albumTitle {
                return await MusicBrainzService.searchRelease(artist: artist, album: albumTitle)
            }
            return nil
        }()
        async let mbArtist = MusicBrainzService.searchArtist(name: artist)

        let rel = await mbRelease
        let art = await mbArtist

        release = rel
        artistInfo = art

        // Wikipedia for album — use clean title
        if let slug = rel?.wikipediaSlug {
            albumWiki = await WikipediaService.fetchSummary(slug: slug)
        }
        if albumWiki == nil {
            albumWiki = await WikipediaService.search(query: "\(cleanAlbum) \(artist) album")
        }
        if albumWiki == nil {
            albumWiki = await WikipediaService.search(query: "\(cleanAlbum) (\(artist) album)")
        }
        if albumWiki == nil {
            albumWiki = await WikipediaService.search(query: cleanAlbum)
        }

        // Wikipedia for artist
        if let slug = art?.wikipediaSlug {
            artistWiki = await WikipediaService.fetchSummary(slug: slug)
        }
        if artistWiki == nil {
            artistWiki = await WikipediaService.searchArtist(name: artist)
        }

        // Discogs — prefer catalog from title, then MB catalog, then barcode, then search
        if let catno = catalogFromTitle {
            discogs = await DiscogsService.searchByCatalog(catno)
        }
        if discogs == nil, let catno = rel?.catalogNumber, !catno.isEmpty {
            discogs = await DiscogsService.searchByCatalog(catno)
        }
        if discogs == nil, let barcode = rel?.barcode, !barcode.isEmpty {
            discogs = await DiscogsService.searchByBarcode(barcode)
        }
        if discogs == nil {
            discogs = await DiscogsService.search(artist: artist, album: cleanAlbum)
        }

        loading = false
    }
}
