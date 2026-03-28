import SwiftUI

struct PlayerView: View {
    @State private var vm = PlayerViewModel()
    @State private var selectedAlbum: Album? = nil
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var genreFilter: String? = nil
    @State private var lastAlbumId: String? = nil
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var showFullPlayer = false
    @State private var showSetup = !AppSettings.shared.hasCompletedSetup
    @State private var browseMode: BrowseMode = .albums

    enum BrowseMode: String, CaseIterable {
        case albums = "Albumes"
        case artists = "Artistas"
        case tracks = "Pistas"
        case composers = "Compositores"
    }

    private var filteredAlbums: [Album] {
        guard let genre = genreFilter else { return vm.albums }
        let lower = genre.lowercased()
        return vm.albums.filter { album in
            album.genres.contains { $0.lowercased() == lower }
        }
    }

    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            // Now playing bar
            NowPlayingBar(vm: vm, showSearch: $showSearch, showLyrics: $showLyrics, showQueue: $showQueue, onTapCover: { showFullPlayer = true })

            Divider()

            // Main content - using ZStack to preserve scroll positions
            HStack(spacing: 0) {
            ZStack {
                // Layer 0: Empty state
                if vm.albums.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "music.note.house")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Button {
                            Task { await vm.loadLibrary() }
                        } label: {
                            Label("Cargar biblioteca", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                }

                // Layer 1: Browsing panels (always alive once loaded)
                if !vm.albums.isEmpty {
                    VStack(spacing: 0) {
                        // Browse mode selector + genre filter
                        HStack(spacing: 12) {
                            Picker("", selection: $browseMode) {
                                ForEach(BrowseMode.allCases, id: \.self) { mode in
                                    if mode == .composers && vm.allComposers.isEmpty {
                                        EmptyView()
                                    } else {
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 400)

                            if let genre = genreFilter, browseMode == .albums {
                                HStack(spacing: 4) {
                                    Image(systemName: "tag.fill")
                                        .font(.caption2)
                                    Text(genre.uppercased())
                                        .font(.caption2.bold())
                                    Button {
                                        genreFilter = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)

                        // Content based on browse mode
                        switch browseMode {
                        case .albums:
                            AlbumGridView(
                                albums: filteredAlbums,
                                currentAlbum: vm.currentAlbum,
                                onSelect: { album in
                                    lastAlbumId = album.id
                                    Task {
                                        var a = album
                                        await vm.loadFavorites(for: &a)
                                        selectedAlbum = a
                                    }
                                },
                                scrollToAlbumId: lastAlbumId
                            )
                        case .artists:
                            ArtistListView(
                                artists: vm.allArtists,
                                onSelectArtist: { artist in
                                    // Show this artist's albums in album grid
                                    genreFilter = nil
                                    browseMode = .albums
                                    // Use first album as selection
                                    if let first = artist.albums.first {
                                        lastAlbumId = first.id
                                        Task {
                                            var a = first
                                            await vm.loadFavorites(for: &a)
                                            selectedAlbum = a
                                        }
                                    }
                                },
                                onPlayFile: { file in
                                    Task { await vm.enqueueAndPlay(file: file) }
                                }
                            )
                        case .tracks:
                            TrackListView(
                                tracks: vm.allTracks,
                                allAlbums: vm.albums,
                                onPlay: { track in
                                    Task { await vm.enqueueAndPlay(file: track.file) }
                                },
                                onPlayFile: { file in
                                    Task { await vm.enqueueAndPlay(file: file) }
                                }
                            )
                        case .composers:
                            ComposerListView(
                                composers: vm.allComposers,
                                allTracks: vm.allTracks,
                                onPlay: { track in
                                    Task { await vm.enqueueAndPlay(file: track.file) }
                                }
                            )
                        }
                    }
                    .opacity(selectedAlbum == nil && !showSearch ? 1 : 0)
                    .allowsHitTesting(selectedAlbum == nil && !showSearch)
                }

                // Layer 2: Album detail
                if let album = selectedAlbum {
                    AlbumDetailView(
                        album: album,
                        allAlbums: vm.albums,
                        currentPos: vm.currentPos,
                        currentAlbumTitle: vm.currentAlbum,
                        onPlayAlbum: {
                            Task { await vm.playAlbum(album) }
                        },
                        onEnqueueAlbum: {
                            Task { await vm.enqueueAlbum(album) }
                        },
                        onStartRadio: {
                            Task { await vm.startRadio(from: album) }
                        },
                        onPlayTrack: { idx in
                            Task {
                                guard idx < album.tracks.count else { return }
                                let track = album.tracks[idx]
                                await vm.enqueueAndPlay(file: track.file)
                            }
                        },
                        onEnqueueTrack: { track in
                            Task { await vm.enqueueTrack(file: track.file) }
                        },
                        onPlayFile: { file in
                            Task { await vm.enqueueAndPlay(file: file) }
                        },
                        onBack: { selectedAlbum = nil },
                        onToggleFavorite: { track in
                            Task { await vm.toggleFavorite(track: track) }
                        },
                        onSelectGenre: { genre in
                            genreFilter = genre
                            selectedAlbum = nil
                        },
                        onSearch: { query in
                            searchText = query
                            showSearch = true
                        }
                    )
                    .opacity(showSearch ? 0 : 1)
                    .allowsHitTesting(!showSearch)
                }

                // Layer 3: Search (always alive once shown)
                if showSearch || !searchText.isEmpty {
                    SearchView(
                        searchText: $searchText,
                        allAlbums: vm.albums,
                        onSelectAlbum: { album in
                            Task {
                                var a = album
                                await vm.loadFavorites(for: &a)
                                selectedAlbum = a
                                showSearch = false
                            }
                        },
                        onPlayTrack: { track in
                            Task { await vm.enqueueAndPlay(file: track.file) }
                        },
                        onEnqueueTrack: { track in
                            Task { await vm.enqueueTrack(file: track.file) }
                        },
                        onDismiss: { showSearch = false }
                    )
                    .opacity(showSearch ? 1 : 0)
                    .allowsHitTesting(showSearch)
                }
            } // end ZStack

            // Lyrics panel
            if showLyrics {
                LyricsView(vm: vm)
                    .frame(width: 320)
            }
            // Queue panel
            if showQueue {
                QueueView(vm: vm)
                    .frame(width: 300)
            }
            } // end HStack

            if let error = vm.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(4)
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }

        // Full screen now playing overlay
        if showFullPlayer {
            NowPlayingFullView(vm: vm, onDismiss: { withAnimation { showFullPlayer = false } })
                .transition(.move(edge: .bottom))
                .onExitCommand { withAnimation { showFullPlayer = false } }
        }
        } // end ZStack
        .sheet(isPresented: $showSetup) {
            FirstRunSetupView {
                showSetup = false
                vm.reconnect()
            }
            .interactiveDismissDisabled()
        }
    }
}

// MARK: - Now Playing Bar

struct NowPlayingBar: View {
    let vm: PlayerViewModel
    @Binding var showSearch: Bool
    @Binding var showLyrics: Bool
    @Binding var showQueue: Bool
    var onTapCover: () -> Void = {}

    var body: some View {
        VStack(spacing: 6) {
            // Song info row
            HStack(alignment: .top, spacing: 12) {
                // Cover art for current song
                currentCover
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture(perform: onTapCover)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.currentTitle)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if !vm.currentArtist.isEmpty {
                            Text(vm.currentArtist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !vm.currentAlbum.isEmpty {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(vm.currentAlbum)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                // Audio info + signal path
                HStack(spacing: 8) {
                    SignalPathIndicator(vm: vm)

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(vm.connected ? .green : .red)
                                .frame(width: 6, height: 6)
                            if !vm.audioFormat.isEmpty {
                                Text(formatAudio(vm.audioFormat))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !vm.bitrate.isEmpty && vm.bitrate != "0" {
                            Text("\(vm.bitrate) kbps")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        if let dr = vm.currentTrackDR, dr > 0 {
                            Text("DR\(dr)")
                                .font(.caption2.bold().monospaced())
                                .foregroundStyle(drColor(dr))
                        }
                    }
                }
            }

            // Waveform / Progress bar
            if vm.duration > 0 {
                VStack(spacing: 2) {
                    if !vm.waveformPeaks.isEmpty {
                        WaveformView(
                            peaks: vm.waveformPeaks,
                            progress: vm.elapsed / vm.duration,
                            playedColor: .white.opacity(0.8),
                            unplayedColor: .white.opacity(0.2)
                        )
                        .frame(height: 32)
                    } else {
                        // Fallback flat bar while waveform loads
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.quaternary)
                                    .frame(height: 4)
                                Capsule()
                                    .fill(.white.opacity(0.7))
                                    .frame(width: max(0, geo.size.width * (vm.elapsed / vm.duration)), height: 4)
                            }
                        }
                        .frame(height: 4)
                    }

                    HStack {
                        Text(formatTime(vm.elapsed))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text(formatTime(vm.duration))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Transport controls
            HStack(spacing: 20) {
                Button { Task { await vm.prev() } } label: {
                    Image(systemName: "backward.fill")
                }
                Button { Task { await vm.togglePlayPause() } } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 20)
                }
                Button { Task { await vm.stopPlayback() } } label: {
                    Image(systemName: "stop.fill")
                }
                Button { Task { await vm.next() } } label: {
                    Image(systemName: "forward.fill")
                }

                Spacer().frame(width: 8)

                Button { showSearch.toggle() } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(showSearch ? .accentColor : .primary)
                }
                .help("Buscar")

                Button { showLyrics.toggle() } label: {
                    Image(systemName: "quote.bubble")
                        .foregroundColor(showLyrics ? .accentColor : .primary)
                }
                .help("Letras")

                Button { showQueue.toggle() } label: {
                    Image(systemName: "list.bullet")
                        .foregroundColor(showQueue ? .accentColor : .primary)
                }
                .help("Cola de reproducción (\(vm.playlist.count) pistas)")

                Button {
                    if vm.radioEnabled {
                        vm.stopRadio()
                    } else {
                        Task { await vm.startRadioFromCurrent() }
                    }
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(vm.radioEnabled ? .green : .primary)
                }
                .help(vm.radioEnabled ? "Radio activa — click para desactivar" : "Iniciar radio basada en lo que suena")
            }
            .font(.title3)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var currentCover: some View {
        if vm.state == "stop" && vm.currentTitle == "---" {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
        } else {
            // Try to find cover from current file's folder
            CoverView(file: vm.playlist.first(where: { $0.pos == vm.currentPos })?.file ?? "")
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func drColor(_ dr: Int) -> Color {
        switch dr {
        case 14...: return .green
        case 10...13: return .yellow
        case 7...9: return .orange
        default: return .red
        }
    }

    private func formatAudio(_ format: String) -> String {
        // MPD returns "44100:16:2" or "dsd64:2" etc.
        let parts = format.split(separator: ":")
        guard parts.count >= 2 else { return format }

        let rate = String(parts[0])
        let channels = parts.count >= 3 ? String(parts[2]) : String(parts[1])
        let ch = channels == "2" ? "stereo" : channels == "1" ? "mono" : "\(channels)ch"

        if rate.hasPrefix("dsd") {
            return "\(rate) \(ch)"
        }

        if let sampleRate = Int(rate) {
            let bits = parts.count >= 3 ? String(parts[1]) : ""
            let kHz = Double(sampleRate) / 1000.0
            let kHzStr = kHz.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fkHz", kHz)
                : String(format: "%.1fkHz", kHz)
            if !bits.isEmpty {
                return "\(kHzStr)/\(bits)bit \(ch)"
            }
            return "\(kHzStr) \(ch)"
        }

        return format
    }
}

// MARK: - Cover thumbnail for now playing

struct CoverView: View {
    let file: String
    @State private var image: NSImage?
    @State private var loaded = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .task(id: file) {
            guard !file.isEmpty else { return }
            let f = file
            image = await Task.detached {
                CoverView.findCover(for: f)
            }.value
        }
    }

    nonisolated private static func findCover(for file: String) -> NSImage? {
        let musicBase = AppSettings.shared.musicLibraryPath
        let folder = (file as NSString).deletingLastPathComponent
        let albumPath = "\(musicBase)/\(folder)"
        return Album.findCover(in: albumPath)
    }
}
