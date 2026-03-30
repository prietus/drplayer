import SwiftUI

struct PlayerView: View {
    @State private var vm = PlayerViewModel()
    @State private var selectedAlbum: Album? = nil
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var albumFilter: AlbumFilter? = nil
    @State private var lastAlbumId: String? = nil
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var showFullPlayer = false
    @State private var showVisualizer = false
    @State private var showSetup = !AppSettings.shared.hasCompletedSetup
    @State private var browseMode: BrowseMode = .albums

    enum BrowseMode: String, CaseIterable {
        case albums = "Albums"
        case artists = "Artists"
        case labels = "Labels"
        case tracks = "Tracks"
        case composers = "Composers"
        case producers = "Producers"
        case smart = "Smart"
        case stats = "Stats"
    }

    enum AlbumFilter {
        case genre(String)
        case label(String)
        case country(String)

        var displayName: String {
            switch self {
            case .genre(let v): return v.uppercased()
            case .label(let v): return v
            case .country(let v): return v
            }
        }

        var icon: String {
            switch self {
            case .genre: return "tag.fill"
            case .label: return "building.2"
            case .country: return "globe"
            }
        }

        func matches(_ album: Album) -> Bool {
            switch self {
            case .genre(let g):
                let lower = g.lowercased()
                return album.genres.contains { $0.lowercased() == lower }
            case .label(let l):
                let lower = l.lowercased()
                return album.label.lowercased() == lower
                    || album.tracks.contains { $0.label.lowercased() == lower }
            case .country(let c):
                let upper = c.uppercased()
                return album.tracks.contains { $0.country.uppercased() == upper }
            }
        }
    }

    private var filteredAlbums: [Album] {
        guard let filter = albumFilter else { return vm.albums }
        return vm.albums.filter { filter.matches($0) }
    }

    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            // Now playing bar
            NowPlayingBar(vm: vm, showSearch: $showSearch, showLyrics: $showLyrics, showQueue: $showQueue, showVisualizer: $showVisualizer, onTapCover: { showFullPlayer = true }, onTapAlbum: {
                // Navigate to the album of the currently playing track
                if let album = vm.currentPlayingAlbum {
                    Task {
                        var a = album
                        await vm.loadFavorites(for: &a)
                        selectedAlbum = a
                    }
                }
            })

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
                            Label("Load library", systemImage: "arrow.down.circle")
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
                            HStack(spacing: 2) {
                                ForEach(BrowseMode.allCases, id: \.self) { mode in
                                    if mode == .composers && vm.allComposers.isEmpty {
                                        EmptyView()
                                    } else {
                                        Button {
                                            browseMode = mode
                                        } label: {
                                            Text(mode.rawValue)
                                                .font(.caption.weight(browseMode == mode ? .bold : .regular))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(browseMode == mode ? ThemeManager.shared.current.accent : Color.clear)
                                                .foregroundStyle(browseMode == mode ? .white : .secondary)
                                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if let filter = albumFilter, browseMode == .albums {
                                HStack(spacing: 4) {
                                    Image(systemName: filter.icon)
                                        .font(.caption2)
                                    Text(filter.displayName)
                                        .font(.caption2.bold())
                                    Button {
                                        albumFilter = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(libraryStats)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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
                        case .labels:
                            LabelListView(
                                labels: vm.allLabels,
                                onSelectLabel: { label in
                                    albumFilter = .label(label.name)
                                    browseMode = .albums
                                    if let first = label.albums.first {
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
                        case .artists:
                            ArtistListView(
                                artists: vm.allArtists,
                                onSelectArtist: { artist in
                                    // Show this artist's albums in album grid
                                    albumFilter = nil
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
                                },
                                onSelectAlbum: { album in
                                    lastAlbumId = album.id
                                    Task {
                                        var a = album
                                        await vm.loadFavorites(for: &a)
                                        selectedAlbum = a
                                    }
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
                        case .producers:
                            ProducerListView(
                                albums: vm.albums,
                                onSelectAlbum: { album in
                                    lastAlbumId = album.id
                                    Task {
                                        var a = album
                                        await vm.loadFavorites(for: &a)
                                        selectedAlbum = a
                                    }
                                },
                                onPlayFile: { file in
                                    Task { await vm.enqueueAndPlay(file: file) }
                                }
                            )
                        case .smart:
                            SmartPlaylistView(
                                vm: vm,
                                onPlayFile: { file in
                                    Task { await vm.enqueueAndPlay(file: file) }
                                }
                            )
                        case .stats:
                            StatsView(
                                vm: vm,
                                onPlayFile: { file in
                                    Task { await vm.enqueueAndPlay(file: file) }
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
                        versionCountFor: { vm.versionCount(for: $0) },
                        onSetPreferred: { file in
                            Task {
                                if let t = vm.albums.flatMap(\.tracks).first(where: { $0.file == file }) {
                                    await vm.setPreferredVersion(file: file, title: t.title, artist: t.artist)
                                    await vm.loadPreferredStickers()
                                }
                            }
                        },
                        preferredFiles: vm.preferredFiles,
                        onBack: { selectedAlbum = nil },
                        onToggleFavorite: { track in
                            Task { await vm.toggleFavorite(track: track) }
                        },
                        onSelectGenre: { genre in
                            albumFilter = .genre(genre)
                            selectedAlbum = nil
                        },
                        onSearch: { query in
                            searchText = query
                            showSearch = true
                        },
                        onSelectLabel: { label in
                            albumFilter = .label(label)
                            selectedAlbum = nil
                        },
                        onSelectCountry: { country in
                            albumFilter = .country(country)
                            selectedAlbum = nil
                        },
                        onScanDR: { albumIdx in
                            await vm.scanDR14ForAlbum(albumIdx: albumIdx)
                        },
                        onUpdateDB: { path in
                            await vm.updateDB(path: path)
                        }
                    )
                    .id(album.id)
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

            // Oscilloscope visualizer
            if showVisualizer && vm.isPlaying {
                OscilloscopeView()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
            }

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

    private var libraryStats: String {
        let albumCount = vm.albums.count
        let trackCount = vm.albums.reduce(0) { $0 + $1.tracks.count }
        return "\(albumCount) albums · \(trackCount) tracks"
    }
}

// MARK: - Now Playing Bar

struct NowPlayingBar: View {
    let vm: PlayerViewModel
    @Binding var showSearch: Bool
    @Binding var showLyrics: Bool
    @Binding var showQueue: Bool
    @Binding var showVisualizer: Bool
    var onTapCover: () -> Void = {}
    var onTapAlbum: (() -> Void)? = nil

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
                            if let onTapAlbum {
                                Button(action: onTapAlbum) {
                                    Text(vm.currentAlbum)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                            } else {
                                Text(vm.currentAlbum)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Spacer()

                // Audio info + signal path
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if !vm.audioFormat.isEmpty {
                            Text(formatAudio(vm.audioFormat))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
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

                    SignalPathIndicator(vm: vm)
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
            }
            .font(.title3)
            .buttonStyle(.plain)

            Spacer().frame(height: 2)

            // Utility buttons
            HStack(spacing: 16) {
                Button { showSearch.toggle() } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(showSearch ? ThemeManager.shared.current.accent : .secondary)
                }
                .help("Search")

                Button { showLyrics.toggle() } label: {
                    Image(systemName: "quote.bubble")
                        .foregroundColor(showLyrics ? ThemeManager.shared.current.accent : .secondary)
                }
                .help("Lyrics")

                Button { showQueue.toggle() } label: {
                    Image(systemName: "list.bullet")
                        .foregroundColor(showQueue ? ThemeManager.shared.current.accent : .secondary)
                }
                .help("Play queue (\(vm.playlist.count) tracks)")

                Button { showVisualizer.toggle() } label: {
                    Image(systemName: "waveform.path")
                        .foregroundColor(showVisualizer ? ThemeManager.shared.current.accent : .secondary)
                }
                .help("Oscilloscope")

                Button {
                    if vm.radioEnabled {
                        vm.stopRadio()
                    } else {
                        Task { await vm.startRadioFromCurrent() }
                    }
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(vm.radioEnabled ? .green : .secondary)
                }
                .help(vm.radioEnabled ? "Radio active — click to disable" : "Start radio based on current track")

                BackgroundTasksIndicator(vm: vm)
            }
            .font(.caption)
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
            let mult = rate.dropFirst(3)
            return "DSD\(mult) DoP \(ch)"
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
