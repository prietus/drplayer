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
    @State private var showRelease = true
    @State private var showDiscogs = false
    @State private var showCredits = false
    @State private var showMembers = false

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            if loading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Cargando...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Album Wikipedia article (priority)
                if let wiki = albumWiki {
                    wikiSection(title: "Sobre el álbum", summary: wiki)
                }

                // Artist Wikipedia article (only if different from album article)
                if let wiki = artistWiki,
                   wiki.pageURL != albumWiki?.pageURL {
                    wikiSection(title: "Sobre \(artistInfo?.name ?? artist)", summary: wiki)
                }

                // Collapsible: Release details
                if let rel = release {
                    collapsibleSection("Lanzamiento", isExpanded: $showRelease) {
                        releaseSection(rel)
                    }
                }

                // Collapsible: Discogs edition details
                if let dg = discogs {
                    collapsibleSection("Edicion fisica (Discogs)", isExpanded: $showDiscogs) {
                        discogsSection(dg)
                    }
                }

                // Collapsible: Credits
                if let rel = release, !rel.credits.isEmpty {
                    collapsibleSection("Créditos", isExpanded: $showCredits) {
                        creditsSection(rel.credits)
                    }
                }

                // Collapsible: Band members
                if let info = artistInfo, !info.members.isEmpty {
                    collapsibleSection("Miembros", isExpanded: $showMembers) {
                        membersSection(info)
                    }
                }

                if release == nil && albumWiki == nil && artistWiki == nil {
                    Text("Sin información adicional")
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

    // MARK: - Load

    private func loadInfo() async {
        // MusicBrainz: prefer direct lookup by ID, fallback to text search
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

        // Fetch Wikipedia articles for album
        if let slug = rel?.wikipediaSlug {
            albumWiki = await WikipediaService.fetchSummary(slug: slug)
        }
        if albumWiki == nil {
            // Try with artist name first (best for disambiguation: "A Night at the Opera Queen album")
            albumWiki = await WikipediaService.search(query: "\(albumTitle) \(artist) album")
        }
        if albumWiki == nil {
            // Try "Album (artist album)" pattern: "A Night at the Opera (Queen album)"
            albumWiki = await WikipediaService.search(query: "\(albumTitle) (\(artist) album)")
        }
        if albumWiki == nil {
            // Try exact album title (works for unique titles like "Storia di un minuto")
            albumWiki = await WikipediaService.search(query: albumTitle)
        }

        // Fetch Wikipedia for artist
        if let slug = art?.wikipediaSlug {
            artistWiki = await WikipediaService.fetchSummary(slug: slug)
        }
        if artistWiki == nil {
            artistWiki = await WikipediaService.searchArtist(name: artist)
        }

        // Discogs: search by catalog number (from MB), barcode, or artist+album
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

    // MARK: - Sections

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
                    Text("Leer más en Wikipedia ↗")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func releaseSection(_ rel: MBRelease) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                if !rel.label.isEmpty {
                    infoRow("Sello", rel.label)
                }
                if !rel.catalogNumber.isEmpty {
                    infoRow("Catálogo", rel.catalogNumber)
                }
                if !rel.date.isEmpty {
                    infoRow("Fecha", rel.date)
                }
                if !rel.country.isEmpty {
                    infoRow("País", rel.country)
                }
                if !rel.barcode.isEmpty {
                    infoRow("Código de barras", rel.barcode)
                }
                if !rel.status.isEmpty {
                    infoRow("Estado", rel.status)
                }
                if !rel.genres.isEmpty {
                    infoRow("Géneros (MB)", rel.genres.joined(separator: ", "))
                }
            }

            // External links for this specific release
            HStack(spacing: 12) {
                if !rel.id.isEmpty {
                    linkButton("MusicBrainz", url: "https://musicbrainz.org/release/\(rel.id)", icon: "circle.grid.3x3")
                }
                if !rel.catalogNumber.isEmpty {
                    linkButton("Buscar en Discogs", url: "https://www.discogs.com/search/?type=release&catno=\(rel.catalogNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")", icon: "record.circle")
                } else if !rel.barcode.isEmpty {
                    linkButton("Buscar en Discogs", url: "https://www.discogs.com/search/?type=release&barcode=\(rel.barcode)", icon: "record.circle")
                }
            }
            .padding(.top, 4)

            Text("Fuente: MusicBrainz")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .italic()
        }
    }

    private func linkButton(_ label: String, url: String, icon: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption2)
            }
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }

    private func discogsSection(_ dg: DiscogsRelease) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                if !dg.label.isEmpty {
                    infoRow("Sello", dg.label)
                }
                if !dg.catalogNumber.isEmpty {
                    infoRow("Catalogo", dg.catalogNumber)
                }
                if dg.year > 0 {
                    infoRow("Año", String(dg.year))
                }
                if !dg.country.isEmpty {
                    infoRow("Pais", dg.country)
                }
                if !dg.formats.isEmpty {
                    infoRow("Formato", dg.formats.joined(separator: ", "))
                }
                if !dg.styles.isEmpty {
                    infoRow("Estilos", dg.styles.joined(separator: ", "))
                }
                if let price = dg.lowestPrice {
                    infoRow("Precio min.", "$\(price)")
                }
            }

            if !dg.notes.isEmpty {
                Text(dg.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.top, 2)
            }

            HStack(spacing: 12) {
                linkButton("Ver en Discogs", url: dg.url, icon: "record.circle")
            }
            .padding(.top, 4)

            Text("Fuente: Discogs")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .italic()
        }
    }

    private func creditsSection(_ credits: [(name: String, role: String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Group by role
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
                HStack(alignment: .top, spacing: 4) {
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
        }
    }

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
}
