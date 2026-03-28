import SwiftUI

struct SearchResult {
    var albums: [Album] = []
    var artists: [(name: String, albumCount: Int, trackCount: Int)] = []
    var tracks: [Track] = []
}

struct SearchView: View {
    @Binding var searchText: String
    let allAlbums: [Album]
    let onSelectAlbum: (Album) -> Void
    let onPlayTrack: (Track) -> Void
    let onEnqueueTrack: (Track) -> Void
    let onDismiss: () -> Void

    @State private var results = SearchResult()
    @State private var searching = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Buscar artistas, álbumes, pistas...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($searchFocused)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            // Results
            if searchText.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Escribe para buscar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if searching {
                Spacer()
                ProgressView()
                Spacer()
            } else if results.albums.isEmpty && results.artists.isEmpty && results.tracks.isEmpty {
                Spacer()
                Text("Sin resultados para \"\(searchText)\"")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Artists
                        if !results.artists.isEmpty {
                            sectionHeader("Artistas", count: results.artists.count)
                            ForEach(results.artists.prefix(10), id: \.name) { artist in
                                artistRow(artist)
                            }
                        }

                        // Albums
                        if !results.albums.isEmpty {
                            sectionHeader("Álbumes", count: results.albums.count)
                            ForEach(results.albums.prefix(20), id: \.id) { album in
                                albumRow(album)
                            }
                        }

                        // Tracks
                        if !results.tracks.isEmpty {
                            sectionHeader("Pistas", count: results.tracks.count)
                            ForEach(results.tracks.prefix(30), id: \.id) { track in
                                trackRow(track)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
                searchFocused = true
                performSearch()
            }
        }
        .onChange(of: searchText) {
            performSearch()
        }
    }

    // MARK: - Search

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else {
            results = SearchResult()
            return
        }

        searching = true

        // Search locally in loaded albums (fast)
        var matchedAlbums: [Album] = []
        var artistMap: [String: (albums: Set<String>, tracks: Int)] = [:]
        var matchedTracks: [Track] = []

        for album in allAlbums {
            let albumMatches = album.title.lowercased().contains(query)
            let artistMatches = album.artist.lowercased().contains(query)
            let genreMatches = album.genres.contains { $0.lowercased().contains(query) }

            if albumMatches || artistMatches || genreMatches {
                matchedAlbums.append(album)
            }

            // Collect artist info
            if artistMatches {
                var info = artistMap[album.artist] ?? (albums: [], tracks: 0)
                info.albums.insert(album.id)
                info.tracks += album.tracks.count
                artistMap[album.artist] = info
            }

            // Search tracks
            for track in album.tracks {
                if track.title.lowercased().contains(query) ||
                   track.artist.lowercased().contains(query) {
                    matchedTracks.append(track)
                    // Also add artist
                    let tArtist = track.artist.isEmpty ? album.artist : track.artist
                    if tArtist.lowercased().contains(query) {
                        var info = artistMap[tArtist] ?? (albums: [], tracks: 0)
                        info.albums.insert(album.id)
                        info.tracks += 1
                        artistMap[tArtist] = info
                    }
                }
            }
        }

        let artists = artistMap.map { (name: $0.key, albumCount: $0.value.albums.count, trackCount: $0.value.tracks) }
            .sorted { $0.trackCount > $1.trackCount }

        results = SearchResult(
            albums: matchedAlbums,
            artists: artists,
            tracks: matchedTracks
        )
        searching = false
    }

    // MARK: - Row views

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Text("(\(count))")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private func artistRow(_ artist: (name: String, albumCount: Int, trackCount: Int)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(artist.name)
                    .fontWeight(.medium)
                Text("\(artist.albumCount) álbumes · \(artist.trackCount) pistas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            // Filter search to this artist
            searchText = artist.name
        }
    }

    private func albumRow(_ album: Album) -> some View {
        HStack(spacing: 12) {
            AlbumThumb(album: album)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                Text(album.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !album.format.isEmpty {
                Text(album.format)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            if let dr = album.avgDR {
                Text("DR\(dr)")
                    .font(.caption2.bold().monospaced())
                    .foregroundColor(drColor(dr))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onSelectAlbum(album) }
    }

    private func trackRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            Button {
                onPlayTrack(track)
            } label: {
                Image(systemName: "play.circle")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !track.album.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(track.album)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
            }
            Spacer()

            Button {
                onEnqueueTrack(track)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)

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
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func drColor(_ dr: Int) -> Color {
        switch dr {
        case 14...: return .green
        case 10...13: return .yellow
        case 7...9: return .orange
        default: return .red
        }
    }
}

// Small album thumbnail for search results
struct AlbumThumb: View {
    let album: Album
    @State private var cover: NSImage?

    var body: some View {
        Group {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .task(id: album.id) {
            let a = album
            cover = await a.coverImageAsync()
        }
    }
}
