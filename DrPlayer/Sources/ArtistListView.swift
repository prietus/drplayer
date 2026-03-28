import SwiftUI

struct ArtistListView: View {
    let artists: [PlayerViewModel.ArtistInfo]
    let onSelectArtist: (PlayerViewModel.ArtistInfo) -> Void
    let onPlayFile: (String) -> Void

    @State private var searchText = ""
    @State private var selectedArtist: PlayerViewModel.ArtistInfo?

    private var filteredArtists: [PlayerViewModel.ArtistInfo] {
        guard !searchText.isEmpty else { return artists }
        let q = searchText.lowercased()
        return artists.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        if let artist = selectedArtist {
            ArtistDetailPanel(
                artist: artist,
                onBack: { selectedArtist = nil },
                onSelectAlbum: { _ in onSelectArtist(artist) },
                onPlayFile: onPlayFile
            )
        } else {
            artistListBody
        }
    }

    private var artistListBody: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search artists...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(filteredArtists.count) artists")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredArtists) { artist in
                        Button {
                            selectedArtist = artist
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artist.name)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("\(artist.albumCount) albums · \(artist.trackCount) tracks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
    }
}

// MARK: - Artist Detail Panel

private struct ArtistDetailPanel: View {
    let artist: PlayerViewModel.ArtistInfo
    let onBack: () -> Void
    let onSelectAlbum: (Album) -> Void
    let onPlayFile: (String) -> Void

    @State private var mbInfo: MBArtistInfo?
    @State private var wikiSummary: WikiSummary?
    @State private var lastfm: LastFMArtist?
    @State private var loading = true

    // Library computed stats
    private var totalDuration: Double {
        artist.albums.flatMap(\.tracks).reduce(0) { $0 + $1.duration }
    }
    private var allGenres: [String] {
        let genres = artist.albums.flatMap(\.genres)
        var seen = Set<String>()
        return genres.filter { seen.insert($0.lowercased()).inserted }
    }
    private var formats: [String] {
        let fmts = artist.albums.compactMap { $0.format.isEmpty ? nil : $0.format }
        return Array(Set(fmts)).sorted()
    }
    private var avgDR: Int? {
        let drs = artist.albums.compactMap(\.avgDR)
        guard !drs.isEmpty else { return nil }
        return drs.reduce(0, +) / drs.count
    }
    private var dateRange: String {
        let dates = artist.albums.map(\.date).filter { !$0.isEmpty }.sorted()
        guard let first = dates.first else { return "" }
        let last = dates.last ?? first
        return first == last ? first : "\(first) – \(last)"
    }

    @State private var artistImage: NSImage?
    @State private var showFullImage = false

    private var imageURLString: String? {
        wikiSummary?.thumbnailURL ?? lastfm?.imageURL
    }

    private var fullImageURLString: String? {
        wikiSummary?.originalImageURL ?? imageURLString
    }

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Artists").font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    artistHeader.padding()

                    if loading {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Loading...").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    } else {
                        infoSections.padding(.horizontal)
                    }

                    Divider().padding(.horizontal).padding(.top, 12)

                    // Library stats grid
                    libraryStatsSection
                        .padding(.horizontal)
                        .padding(.top, 12)

                    Divider().padding(.horizontal).padding(.top, 12)

                    // Discography
                    Text("Discography (\(artist.albumCount) albums)")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    AlbumGridView(
                        albums: artist.albums,
                        currentAlbum: "",
                        onSelect: onSelectAlbum,
                        scrollToAlbumId: nil
                    )
                }
            }
        }
        .task { await loadInfo() }
    }

    // MARK: - Header

    private var artistHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            // Photo (clickable for full-res)
            Group {
                if let img = artistImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { showFullImage = true }
                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                } else {
                    artistPlaceholder
                }
            }
            .popover(isPresented: $showFullImage) {
                if let img = artistImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 600, maxHeight: 600)
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.largeTitle.bold())

                // MusicBrainz metadata chips
                if let mb = mbInfo {
                    HStack(spacing: 8) {
                        if !mb.type.isEmpty { metaChip(mb.type, icon: "person.fill") }
                        if !mb.area.isEmpty { metaChip(mb.area, icon: "mappin") }
                        if !mb.beginDate.isEmpty {
                            let period = mb.endDate.isEmpty ? "since \(mb.beginDate)" : "\(mb.beginDate) – \(mb.endDate)"
                            metaChip(period, icon: "calendar")
                        }
                    }
                }

                // Tags from Last.fm or library genres
                let tags = lastfm?.tags ?? []
                let displayTags = tags.isEmpty ? allGenres : tags
                if !displayTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(displayTags.prefix(6)), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 3).stroke(.secondary, lineWidth: 1))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }

                // Last.fm global stats
                if let lfm = lastfm {
                    HStack(spacing: 12) {
                        if !lfm.listeners.isEmpty {
                            Label(formatNumber(lfm.listeners) + " listeners", systemImage: "headphones")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        if !lfm.playcount.isEmpty {
                            Label(formatNumber(lfm.playcount) + " plays", systemImage: "play.fill")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 2)
                }

                // External links
                externalLinks.padding(.top, 4)
            }

            Spacer()
        }
    }

    private var artistPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .frame(width: 140, height: 140)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
            }
    }

    private func metaChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - External Links

    private var externalLinks: some View {
        HStack(spacing: 12) {
            if let wiki = wikiSummary, !wiki.pageURL.isEmpty {
                linkButton("Wikipedia", url: wiki.pageURL, icon: "book")
            }
            if let lfm = lastfm, !lfm.url.isEmpty {
                linkButton("Last.fm", url: lfm.url, icon: "music.note")
            }
            if let mb = mbInfo {
                linkButton("MusicBrainz", url: "https://musicbrainz.org/artist/\(mb.id)", icon: "circle.grid.3x3")
            }
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

    // MARK: - Info Sections

    @ViewBuilder
    private var infoSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Biography
            if let wiki = wikiSummary {
                infoBlock(title: "Biography") {
                    Text(wiki.extract)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    sourceLabel("Wikipedia")
                }
            } else if let lfm = lastfm, !lfm.summary.isEmpty {
                infoBlock(title: "Biography") {
                    Text(lfm.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    sourceLabel("Last.fm")
                }
            }

            // Members
            if let mb = mbInfo, !mb.members.isEmpty {
                infoBlock(title: "Members") {
                    ForEach(mb.members, id: \.name) { member in
                        HStack(spacing: 4) {
                            Text(member.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !member.role.isEmpty {
                                Text("(\(member.role))")
                                    .font(.caption)
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

            // Similar artists
            if let lfm = lastfm, !lfm.similarArtists.isEmpty {
                infoBlock(title: "Similar artists") {
                    Text(lfm.similarArtists.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    sourceLabel("Last.fm")
                }
            }
        }
    }

    private func infoBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Library Stats

    private var libraryStatsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("In your library")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                GridRow {
                    statLabel("Albums")
                    Text("\(artist.albumCount)").font(.caption).foregroundStyle(.secondary)
                }
                GridRow {
                    statLabel("Tracks_label")
                    Text("\(artist.trackCount)").font(.caption).foregroundStyle(.secondary)
                }
                GridRow {
                    statLabel("Total duration")
                    Text(formatDuration(totalDuration)).font(.caption).foregroundStyle(.secondary)
                }
                if !dateRange.isEmpty {
                    GridRow {
                        statLabel("Period")
                        Text(dateRange).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !formats.isEmpty {
                    GridRow {
                        statLabel("Formats")
                        Text(formats.joined(separator: ", "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                if let dr = avgDR {
                    GridRow {
                        statLabel("Average DR")
                        HStack(spacing: 4) {
                            Text("DR\(dr)")
                                .font(.caption.bold().monospaced())
                                .foregroundColor(drColor(dr))
                            drBar(dr)
                        }
                    }
                }
            }
        }
    }

    private func statLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(width: 100, alignment: .trailing)
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

    // MARK: - Helpers

    private func sourceLabel(_ source: String) -> some View {
        Text("Source: \(source)")
            .font(.caption2)
            .foregroundStyle(.quaternary)
            .italic()
    }

    private func formatNumber(_ str: String) -> String {
        guard let n = Int(str) else { return str }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return str
    }

    private func formatDuration(_ secs: Double) -> String {
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        if h > 0 { return "\(h)h \(m)min" }
        return "\(m) min"
    }

    // MARK: - Loading

    private func loadInfo() async {
        // Search the primary artist name (handles compound names like "B.B. King & Eric Clapton")
        let searchName = WikipediaService.artistSearchQueries(artist.name).first ?? artist.name

        async let mb = MusicBrainzService.searchArtist(name: searchName)
        async let lfm = LastFMService.fetchArtist(name: searchName)

        let mbResult = await mb
        let lfmResult = await lfm

        mbInfo = mbResult
        lastfm = lfmResult

        // Wikipedia: try MB slug first, then smart artist search
        if let slug = mbResult?.wikipediaSlug {
            wikiSummary = await WikipediaService.fetchSummary(slug: slug)
        }
        if wikiSummary == nil {
            wikiSummary = await WikipediaService.searchArtist(name: artist.name)
        }

        // Load artist image with proper User-Agent
        if let urlStr = wikiSummary?.thumbnailURL ?? lfmResult?.imageURL,
           let url = URL(string: urlStr) {
            artistImage = await Self.fetchImage(url: url)
        }

        loading = false
    }

    private static func fetchImage(url: URL) async -> NSImage? {
        var request = URLRequest(url: url)
        request.setValue("DrPlayer/1.0 (music player; contact@drplayer.app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }
}
