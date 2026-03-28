import SwiftUI

struct ComposerListView: View {
    let composers: [PlayerViewModel.ComposerInfo]
    let allTracks: [Track]
    let onPlay: (Track) -> Void

    @State private var searchText = ""
    @State private var selectedComposer: PlayerViewModel.ComposerInfo?

    private var filteredComposers: [PlayerViewModel.ComposerInfo] {
        guard !searchText.isEmpty else { return composers }
        let q = searchText.lowercased()
        return composers.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        if let composer = selectedComposer {
            ComposerDetailPanel(
                composer: composer,
                tracks: allTracks.filter {
                    $0.composer.lowercased()
                        .folding(options: .diacriticInsensitive, locale: .current)
                    == composer.name.lowercased()
                        .folding(options: .diacriticInsensitive, locale: .current)
                },
                onBack: { selectedComposer = nil },
                onPlay: onPlay
            )
        } else {
            composerListBody
        }
    }

    private var composerListBody: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Buscar compositores...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(filteredComposers.count) compositores")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredComposers) { composer in
                        Button {
                            selectedComposer = composer
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.quarternote.3")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(composer.name)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        Text("\(composer.trackCount) pistas")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !composer.genres.isEmpty {
                                            Text(composer.genres.prefix(3).joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
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

// MARK: - Composer Detail Panel

private struct ComposerDetailPanel: View {
    let composer: PlayerViewModel.ComposerInfo
    let tracks: [Track]
    let onBack: () -> Void
    let onPlay: (Track) -> Void

    @State private var mbInfo: MBArtistInfo?
    @State private var wikiSummary: WikiSummary?
    @State private var lastfm: LastFMArtist?
    @State private var composerImage: NSImage?
    @State private var loading = true
    @State private var showFullImage = false

    private var totalDuration: Double {
        tracks.reduce(0) { $0 + $1.duration }
    }

    private var uniqueAlbums: Int {
        Set(tracks.map(\.album)).count
    }

    private var uniqueArtists: [String] {
        let artists = Set(tracks.map(\.artist).filter { !$0.isEmpty })
        return artists.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Compositores").font(.caption)
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
                    // Header
                    composerHeader.padding()

                    if loading {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Cargando info...").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    } else {
                        infoSections.padding(.horizontal)
                    }

                    Divider().padding(.horizontal).padding(.top, 12)

                    // Library stats
                    libraryStats.padding(.horizontal).padding(.top, 12)

                    Divider().padding(.horizontal).padding(.top, 12)

                    // Track list
                    Text("Composiciones (\(tracks.count) pistas)")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    trackList
                }
            }
        }
        .task { await loadInfo() }
    }

    // MARK: - Header

    private var composerHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            // Photo
            Group {
                if let img = composerImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { showFullImage = true }
                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(width: 140, height: 140)
                        .overlay {
                            Image(systemName: "music.quarternote.3")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .popover(isPresented: $showFullImage) {
                if let img = composerImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 600, maxHeight: 600)
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(composer.name)
                    .font(.largeTitle.bold())

                // MusicBrainz metadata
                if let mb = mbInfo {
                    HStack(spacing: 8) {
                        if !mb.type.isEmpty {
                            metaChip(mb.type, icon: "person.fill")
                        }
                        if !mb.area.isEmpty {
                            metaChip(mb.area, icon: "mappin")
                        }
                        if !mb.beginDate.isEmpty {
                            let period = mb.endDate.isEmpty ? "desde \(mb.beginDate)" : "\(mb.beginDate) – \(mb.endDate)"
                            metaChip(period, icon: "calendar")
                        }
                    }
                }

                // Genres
                if !composer.genres.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(composer.genres.prefix(6)), id: \.self) { genre in
                            Text(genre)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 3).stroke(.secondary, lineWidth: 1))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }

                // Last.fm stats
                if let lfm = lastfm {
                    HStack(spacing: 12) {
                        if !lfm.listeners.isEmpty {
                            Label(formatNumber(lfm.listeners) + " oyentes", systemImage: "headphones")
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
                .padding(.top, 4)
            }

            Spacer()
        }
    }

    private func metaChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundStyle(.secondary)
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
                infoBlock(title: "Biografia") {
                    Text(wiki.extract)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    sourceLabel("Wikipedia")
                }
            } else if let lfm = lastfm, !lfm.summary.isEmpty {
                infoBlock(title: "Biografia") {
                    Text(lfm.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    sourceLabel("Last.fm")
                }
            }

            // Similar artists
            if let lfm = lastfm, !lfm.similarArtists.isEmpty {
                infoBlock(title: "Artistas similares") {
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
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
    }

    private func sourceLabel(_ source: String) -> some View {
        Text("Fuente: \(source)")
            .font(.caption2)
            .foregroundStyle(.quaternary)
            .italic()
    }

    // MARK: - Library Stats

    private var libraryStats: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("En tu biblioteca")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                GridRow {
                    statLabel("Pistas")
                    Text("\(tracks.count)").font(.caption).foregroundStyle(.secondary)
                }
                GridRow {
                    statLabel("Albumes")
                    Text("\(uniqueAlbums)").font(.caption).foregroundStyle(.secondary)
                }
                GridRow {
                    statLabel("Duracion total")
                    Text(formatDuration(totalDuration)).font(.caption).foregroundStyle(.secondary)
                }
                if !uniqueArtists.isEmpty {
                    GridRow {
                        statLabel("Interpretes")
                        Text(uniqueArtists.prefix(5).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
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

    // MARK: - Track List

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(tracks) { track in
                HStack(spacing: 8) {
                    Button { onPlay(track) } label: {
                        Image(systemName: "play.circle")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.callout)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !track.album.isEmpty {
                                Text("·").font(.caption).foregroundStyle(.tertiary)
                                Text(track.album)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .lineLimit(1)
                    }

                    Spacer()

                    if let dr = track.dr, dr > 0 {
                        Text("DR\(dr)")
                            .font(.caption2.bold().monospaced())
                            .foregroundColor(drColor(dr))
                    }

                    if track.duration > 0 {
                        let mins = Int(track.duration) / 60
                        let secs = Int(track.duration) % 60
                        Text(String(format: "%d:%02d", mins, secs))
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                Divider().padding(.leading, 36)
            }
        }
    }

    // MARK: - Helpers

    private func drColor(_ dr: Int) -> Color {
        switch dr {
        case 14...: return .green
        case 10...13: return .yellow
        case 7...9: return .orange
        default: return .red
        }
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
        let searchName = WikipediaService.artistSearchQueries(composer.name).first ?? composer.name

        async let mb = MusicBrainzService.searchArtist(name: searchName)
        async let lfm = LastFMService.fetchArtist(name: searchName)

        let mbResult = await mb
        let lfmResult = await lfm

        mbInfo = mbResult
        lastfm = lfmResult

        if let slug = mbResult?.wikipediaSlug {
            wikiSummary = await WikipediaService.fetchSummary(slug: slug)
        }
        if wikiSummary == nil {
            wikiSummary = await WikipediaService.searchArtist(name: composer.name)
        }

        // Load image
        if let urlStr = wikiSummary?.thumbnailURL, let url = URL(string: urlStr) {
            composerImage = await Self.fetchImage(url: url)
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
