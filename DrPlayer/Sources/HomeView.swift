import SwiftUI

struct HomeView: View {
    let vm: PlayerViewModel
    let onSelectAlbum: (Album) -> Void
    let onPlayFile: (String) -> Void

    @State private var recentAlbums: [Album] = []
    @State private var genreSections: [(genre: String, albums: [Album])] = []
    @State private var unplayedAlbums: [Album] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if loading {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    Spacer()
                } else {
                    if !recentAlbums.isEmpty {
                        albumRow(title: "Recently Played", albums: recentAlbums)
                    }

                    ForEach(genreSections.indices, id: \.self) { i in
                        albumRow(title: genreSections[i].genre, albums: genreSections[i].albums)
                    }

                    if !unplayedAlbums.isEmpty {
                        albumRow(title: "Not Played Yet", albums: unplayedAlbums)
                    }

                    Spacer(minLength: 20)
                }
            }
            .padding(.vertical, 16)
        }
        .task {
            await buildSections()
        }
    }

    private func buildSections() async {
        let albums = vm.albums
        let history = await Task.detached { PlayHistory.loadAll() }.value

        // Index albums by folder for fast lookup
        let albumsByFolder = Dictionary(uniqueKeysWithValues: albums.map { ($0.folder, $0) })

        // Recent albums: deduplicate by folder, most recent first
        var seenFolders = Set<String>()
        var recent: [Album] = []
        for entry in history.reversed() {
            let folder = (entry.file as NSString).deletingLastPathComponent
            if seenFolders.insert(folder).inserted, let album = albumsByFolder[folder] {
                recent.append(album)
            }
            if recent.count >= 20 { break }
        }

        // Count plays per folder and genre listening time
        var folderPlays: [String: Int] = [:]
        var genreTime: [String: Double] = [:]
        var playedFolders = Set<String>()

        for entry in history {
            let folder = (entry.file as NSString).deletingLastPathComponent
            folderPlays[folder, default: 0] += 1
            playedFolders.insert(folder)
            if let album = albumsByFolder[folder] {
                for genre in album.genres {
                    let g = genre.trimmingCharacters(in: .whitespaces)
                    if !g.isEmpty {
                        genreTime[g, default: 0] += entry.duration
                    }
                }
            }
        }

        // Top genres
        let topGenres = genreTime.sorted { $0.value > $1.value }
            .prefix(8)
            .map(\.key)

        var sections: [(genre: String, albums: [Album])] = []
        for genre in topGenres {
            let genreLower = genre.lowercased()
            let matching = albums
                .filter { $0.genres.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == genreLower } }
                .sorted { (folderPlays[$0.folder] ?? 0) > (folderPlays[$1.folder] ?? 0) }
                .prefix(12)
            if matching.count >= 2 {
                sections.append((genre: genre, albums: Array(matching)))
            }
        }

        // Unplayed
        let unplayed = Array(albums.filter { !playedFolders.contains($0.folder) }.shuffled().prefix(12))

        await MainActor.run {
            recentAlbums = recent
            genreSections = sections
            unplayedAlbums = unplayed
            loading = false
        }
    }

    @ViewBuilder
    private func albumRow(title: String, albums: [Album]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(albums, id: \.id) { album in
                        AlbumCell(album: album, isPlaying: album.title == vm.currentAlbum)
                            .frame(width: 140)
                            .onTapGesture { onSelectAlbum(album) }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}
