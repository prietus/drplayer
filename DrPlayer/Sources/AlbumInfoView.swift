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
                    Text("Cargando...")
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
                    wikiSection(title: "Sobre el album", summary: wiki)
                }

                // Artist Wikipedia (only if different article)
                if let wiki = artistWiki,
                   wiki.pageURL != albumWiki?.pageURL {
                    wikiSection(title: "Sobre \(artistInfo?.name ?? artist)", summary: wiki)
                }

                // ─── CAPA 3: "Nerd mode / archivista" ───

                if release != nil || discogs != nil || artistInfo != nil {
                    Divider().padding(.vertical, 4)

                    Text("Detalles")
                        .font(.caption2.bold())
                        .foregroundStyle(.quaternary)
                        .textCase(.uppercase)
                }

                // MusicBrainz release details
                if let rel = release {
                    collapsibleSection("Lanzamiento (MusicBrainz)", isExpanded: $showFullRelease) {
                        releaseSection(rel)
                    }
                }

                // Discogs edition
                if let dg = discogs {
                    collapsibleSection("Edicion fisica (Discogs)", isExpanded: $showDiscogs) {
                        discogsSection(dg)
                    }
                }

                // Credits
                if let rel = release, !rel.credits.isEmpty {
                    collapsibleSection("Creditos", isExpanded: $showCredits) {
                        creditsSection(rel.credits)
                    }
                }

                // Band members
                if let info = artistInfo, !info.members.isEmpty {
                    collapsibleSection("Miembros", isExpanded: $showMembers) {
                        membersSection(info)
                    }
                }

                if release == nil && albumWiki == nil && artistWiki == nil && discogs == nil {
                    Text("Sin informacion adicional")
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
                    Text("Leer mas en Wikipedia")
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
                if !rel.label.isEmpty { infoRow("Sello", rel.label) }
                if !rel.catalogNumber.isEmpty { infoRow("Catalogo", rel.catalogNumber) }
                if !rel.date.isEmpty { infoRow("Fecha", rel.date) }
                if !rel.country.isEmpty { infoRow("Pais", rel.country) }
                if !rel.barcode.isEmpty { infoRow("Codigo de barras", rel.barcode) }
                if !rel.status.isEmpty { infoRow("Estado", rel.status) }
                if !rel.genres.isEmpty { infoRow("Generos", rel.genres.joined(separator: ", ")) }
            }
            sourceLabel("MusicBrainz")
        }
    }

    private func discogsSection(_ dg: DiscogsRelease) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                if !dg.label.isEmpty { infoRow("Sello", dg.label) }
                if !dg.catalogNumber.isEmpty { infoRow("Catalogo", dg.catalogNumber) }
                if dg.year > 0 { infoRow("Año", String(dg.year)) }
                if !dg.country.isEmpty { infoRow("Pais", dg.country) }
                if !dg.formats.isEmpty { infoRow("Formato", dg.formats.joined(separator: ", ")) }
                if !dg.styles.isEmpty { infoRow("Estilos", dg.styles.joined(separator: ", ")) }
                if let price = dg.lowestPrice { infoRow("Precio min.", "$\(price)") }
            }

            if !dg.notes.isEmpty {
                Text(dg.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.top, 2)
            }

            HStack(spacing: 8) {
                miniLink("Ver en Discogs", url: dg.url)
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
                        Text("· desde \(info.beginDate)")
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
        Text("Fuente: \(source)")
            .font(.caption2)
            .foregroundStyle(.quaternary)
            .italic()
    }

    // MARK: - Load

    private func loadInfo() async {
        async let mbRelease: MBRelease? = {
            if !musicbrainzAlbumId.isEmpty {
                return await MusicBrainzService.fetchRelease(id: musicbrainzAlbumId)
            }
            return await MusicBrainzService.searchRelease(artist: artist, album: albumTitle)
        }()
        async let mbArtist = MusicBrainzService.searchArtist(name: artist)

        let rel = await mbRelease
        let art = await mbArtist

        release = rel
        artistInfo = art

        // Wikipedia for album
        if let slug = rel?.wikipediaSlug {
            albumWiki = await WikipediaService.fetchSummary(slug: slug)
        }
        if albumWiki == nil {
            albumWiki = await WikipediaService.search(query: "\(albumTitle) \(artist) album")
        }
        if albumWiki == nil {
            albumWiki = await WikipediaService.search(query: "\(albumTitle) (\(artist) album)")
        }
        if albumWiki == nil {
            albumWiki = await WikipediaService.search(query: albumTitle)
        }

        // Wikipedia for artist
        if let slug = art?.wikipediaSlug {
            artistWiki = await WikipediaService.fetchSummary(slug: slug)
        }
        if artistWiki == nil {
            artistWiki = await WikipediaService.searchArtist(name: artist)
        }

        // Discogs
        if let catno = rel?.catalogNumber, !catno.isEmpty {
            discogs = await DiscogsService.searchByCatalog(catno)
        }
        if discogs == nil, let barcode = rel?.barcode, !barcode.isEmpty {
            discogs = await DiscogsService.searchByBarcode(barcode)
        }
        if discogs == nil {
            discogs = await DiscogsService.search(artist: artist, album: albumTitle)
        }

        loading = false
    }
}
