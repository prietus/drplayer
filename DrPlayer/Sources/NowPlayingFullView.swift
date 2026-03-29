import SwiftUI

struct NowPlayingFullView: View {
    let vm: PlayerViewModel
    let onDismiss: () -> Void

    @State private var artworkPaths: [String] = []
    @State private var currentImageIndex = 0
    @State private var currentImage: NSImage?
    @State private var showLyrics = true
    @State private var imageTimer: Timer?

    // Lyrics state
    @State private var syncedLines: [SyncedLine] = []
    @State private var plainLyrics: String? = nil
    @State private var lyricsLoading = false
    @State private var lastFetchedTrack = ""

    private var currentLineIndex: Int? {
        guard !syncedLines.isEmpty else { return nil }
        let elapsed = vm.elapsed
        var best: Int? = nil
        for (i, line) in syncedLines.enumerated() {
            if line.time <= elapsed { best = i } else { break }
        }
        return best
    }

    var body: some View {
        // Content
        VStack(spacing: 0) {
                // Close button - always visible
                HStack {
                    Button(action: onDismiss) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.body.bold())
                        }
                        .padding(10)
                        .background(.black.opacity(0.6))
                        .clipShape(Circle())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Top bar
                topBar
                    .padding(.horizontal)

                Spacer(minLength: 0)

                if showLyrics {
                    lyricsContent
                } else {
                    artworkGallery
                }

                Spacer(minLength: 0)

                // Bottom: song info + progress
                bottomBar
                    .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                backgroundImage
                Color.black.opacity(0.5)
            }
            .ignoresSafeArea()
        }
        .onAppear { startImageCycling() }
        .onDisappear { imageTimer?.invalidate() }
        .onChange(of: vm.currentTitle) {
            loadArtwork()
            fetchLyrics()
        }
        .task {
            loadArtwork()
            fetchLyrics()
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundImage: some View {
        if let img = currentImage {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: showLyrics ? 30 : 0)
                .animation(.easeInOut(duration: 0.8), value: showLyrics)
                .animation(.easeInOut(duration: 1.0), value: currentImageIndex)
        } else {
            Color.black
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Spacer()

            // View toggle
            HStack(spacing: 2) {
                Button {
                    withAnimation { showLyrics = true }
                } label: {
                    Image(systemName: "text.quote")
                        .padding(6)
                        .background(showLyrics ? .white.opacity(0.2) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Button {
                    withAnimation { showLyrics = false }
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .padding(6)
                        .background(!showLyrics ? .white.opacity(0.2) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
            .buttonStyle(.plain)

            Spacer()

            // Audio info
            VStack(alignment: .trailing, spacing: 2) {
                if !vm.audioFormat.isEmpty {
                    Text(vm.audioFormat)
                        .font(.caption2.monospaced())
                }
                if !vm.bitrate.isEmpty && vm.bitrate != "0" {
                    Text("\(vm.bitrate) kbps")
                        .font(.caption2.monospaced())
                }
                if let dr = vm.currentTrackDR, dr > 0 {
                    Text("DR\(dr)")
                        .font(.caption2.bold().monospaced())
                }
            }
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Lyrics

    @ViewBuilder
    private var lyricsContent: some View {
        if !syncedLines.isEmpty {
            GeometryReader { geo in
                let vPad = geo.size.height / 2
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            Spacer().frame(height: vPad)
                            ForEach(syncedLines) { line in
                                let isCurrent = currentLineIndex == line.id
                                let isPast = (currentLineIndex ?? -1) > line.id

                                Text(line.text.isEmpty ? " " : line.text)
                                    .font(isCurrent ? .title.bold() : .title3)
                                    .foregroundStyle(
                                        isCurrent ? .white :
                                        isPast ? .white.opacity(0.25) : .white.opacity(0.5)
                                    )
                                    .shadow(radius: isCurrent ? 8 : 0)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                    .id(line.id)
                                    .animation(.easeInOut(duration: 0.3), value: isCurrent)
                            }
                            Spacer().frame(height: vPad)
                        }
                    }
                    .onChange(of: currentLineIndex) { _, idx in
                        if let idx {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(idx, anchor: .center)
                            }
                        }
                    }
                }
            }
        } else if let plain = plainLyrics {
            ScrollView(showsIndicators: false) {
                Text(plain)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        } else if lyricsLoading {
            ProgressView()
                .tint(.white)
        } else {
            // No lyrics - show cover art prominently
            if let img = currentImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 20)
            }
        }
    }

    // MARK: - Artwork Gallery

    private var artworkGallery: some View {
        VStack(spacing: 12) {
            if let img = currentImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 20)
                    .padding(.horizontal, 40)
                    .animation(.easeInOut(duration: 0.5), value: currentImageIndex)
            }

            if artworkPaths.count > 1 {
                HStack(spacing: 16) {
                    Button {
                        prevImage()
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title2)
                    }
                    Text("\(currentImageIndex + 1) / \(artworkPaths.count)")
                        .font(.caption.monospaced())
                    Button {
                        nextImage()
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                    }
                }
                .foregroundStyle(.white.opacity(0.6))
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Waveform or progress
            if !vm.waveformPeaks.isEmpty && vm.duration > 0 {
                WaveformView(
                    peaks: vm.waveformPeaks,
                    progress: vm.elapsed / vm.duration,
                    playedColor: .white.opacity(0.8),
                    unplayedColor: .white.opacity(0.15)
                )
                .frame(height: 40)
            } else if vm.duration > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15)).frame(height: 3)
                        Capsule().fill(.white.opacity(0.7))
                            .frame(width: geo.size.width * (vm.elapsed / vm.duration), height: 3)
                    }
                }
                .frame(height: 3)
            }

            HStack {
                Text(formatTime(vm.elapsed))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(formatTime(vm.duration))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Song info
            VStack(spacing: 4) {
                Text(vm.currentTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(vm.currentArtist) — \(vm.currentAlbum)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            // Transport
            HStack(spacing: 24) {
                Button { Task { await vm.prev() } } label: {
                    Image(systemName: "backward.fill")
                }
                Button { Task { await vm.togglePlayPause() } } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                }
                Button { Task { await vm.next() } } label: {
                    Image(systemName: "forward.fill")
                }
            }
            .font(.title2)
            .foregroundStyle(.white.opacity(0.8))
            .buttonStyle(.plain)
        }
    }

    // MARK: - Image cycling

    private func loadArtwork() {
        let file = vm.playlist.first(where: { $0.pos == vm.currentPos })?.file ?? ""
        guard !file.isEmpty else { return }
        let musicBase = AppSettings.shared.musicLibraryPath
        let folder = (file as NSString).deletingLastPathComponent
        let albumPath = "\(musicBase)/\(folder)"

        Task.detached {
            let tempAlbum = Album(id: "", title: "", artist: "", folder: folder, date: "", originalDate: "", label: "", musicbrainzAlbumId: "", genres: [])
            let paths = tempAlbum.allArtwork
            await MainActor.run {
                artworkPaths = paths
                currentImageIndex = 0
                loadCurrentImage()
            }
        }
    }

    private func loadCurrentImage() {
        guard !artworkPaths.isEmpty else {
            currentImage = nil
            return
        }
        let idx = currentImageIndex % artworkPaths.count
        let path = artworkPaths[idx]
        Task.detached {
            let resolved = (path as NSString).resolvingSymlinksInPath
            let img = NSImage(contentsOfFile: resolved)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.5)) {
                    currentImage = img
                }
            }
        }
    }

    private func startImageCycling() {
        imageTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in
            guard artworkPaths.count > 1, !showLyrics else { return }
            nextImage()
        }
    }

    private func nextImage() {
        guard !artworkPaths.isEmpty else { return }
        currentImageIndex = (currentImageIndex + 1) % artworkPaths.count
        loadCurrentImage()
    }

    private func prevImage() {
        guard !artworkPaths.isEmpty else { return }
        currentImageIndex = (currentImageIndex - 1 + artworkPaths.count) % artworkPaths.count
        loadCurrentImage()
    }

    // MARK: - Lyrics fetch

    private func fetchLyrics() {
        let key = "\(vm.currentArtist)|\(vm.currentTitle)"
        guard key != "|", key != lastFetchedTrack else { return }
        lastFetchedTrack = key
        syncedLines = []
        plainLyrics = nil
        lyricsLoading = true

        Task {
            let result = await LyricsService.fetchLyrics(
                artist: vm.currentArtist,
                title: vm.currentTitle,
                album: vm.currentAlbum,
                duration: vm.duration
            )
            await MainActor.run {
                lyricsLoading = false
                if let result {
                    if let synced = result.synced, !synced.isEmpty {
                        syncedLines = LyricsService.parseSyncedLyrics(synced)
                    }
                    plainLyrics = result.plain
                }
            }
        }
    }

    private func formatTime(_ s: Double) -> String {
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }
}
