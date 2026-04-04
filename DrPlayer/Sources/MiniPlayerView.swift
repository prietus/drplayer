import SwiftUI

struct MiniPlayerView: View {
    let vm: PlayerViewModel
    var onClose: () -> Void = {}

    @State private var showQueue = false
    @State private var showLyrics = false

    // Lyrics state
    @State private var syncedLines: [SyncedLine] = []
    @State private var plainLyrics: String? = nil
    @State private var lyricsLoading = false
    @State private var lastLyricsTrack = ""

    private var currentLineIndex: Int? {
        guard !syncedLines.isEmpty else { return nil }
        let elapsed = vm.elapsed
        var best: Int? = nil
        for (i, line) in syncedLines.enumerated() {
            if line.time <= elapsed { best = i } else { break }
        }
        return best
    }

    private let miniWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            // Main compact bar
            playerBar

            // Expandable panels
            if showQueue {
                Divider()
                queuePanel
            }

            if showLyrics {
                Divider()
                lyricsPanel
            }
        }
        .frame(width: miniWidth)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: vm.currentFile) {
            if showLyrics { fetchLyrics() }
        }
    }

    // MARK: - Player Bar

    private var playerBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                // Cover art
                coverArt
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.currentTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    if !vm.currentArtist.isEmpty {
                        Text(vm.currentArtist)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if !vm.currentAlbum.isEmpty {
                        Text(vm.currentAlbum)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            // Progress bar
            if vm.duration > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .frame(height: 3)
                        Capsule()
                            .fill(.white.opacity(0.7))
                            .frame(width: max(0, geo.size.width * (vm.elapsed / vm.duration)), height: 3)
                    }
                }
                .frame(height: 3)
            }

            // Transport + utility row
            HStack {
                // Transport controls
                HStack(spacing: 16) {
                    Button { Task { await vm.prev() } } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 11))
                    }
                    Button { Task { await vm.togglePlayPause() } } label: {
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13))
                            .frame(width: 14)
                    }
                    Button { Task { await vm.next() } } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 11))
                    }
                }

                Spacer()

                // Time
                if vm.duration > 0 {
                    Text("\(formatTime(vm.elapsed)) / \(formatTime(vm.duration))")
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Utility buttons
                HStack(spacing: 12) {
                    Button { withAnimation(.easeInOut(duration: 0.2)) {
                        showQueue.toggle()
                        if showQueue { showLyrics = false }
                    } } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 10))
                            .foregroundStyle(showQueue ? .white : .secondary)
                    }

                    Button { withAnimation(.easeInOut(duration: 0.2)) {
                        showLyrics.toggle()
                        if showLyrics { showQueue = false; fetchLyrics() }
                    } } label: {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 10))
                            .foregroundStyle(showLyrics ? .white : .secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    // MARK: - Queue Panel

    private var queuePanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.playlist) { track in
                        HStack(spacing: 8) {
                            if track.pos == vm.currentPos {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white)
                                    .frame(width: 16)
                            } else {
                                Text("\(track.pos + 1)")
                                    .font(.system(size: 9).monospaced())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 16)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.system(size: 11, weight: track.pos == vm.currentPos ? .semibold : .regular))
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(formatTime(track.duration))
                                .font(.system(size: 9).monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(track.pos == vm.currentPos ? .white.opacity(0.1) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await vm.playTrack(track.pos) }
                        }
                        .id(track.pos)
                    }
                }
            }
            .frame(height: 200)
            .onAppear {
                if let pos = vm.currentPos {
                    proxy.scrollTo(pos, anchor: .center)
                }
            }
            .onChange(of: vm.currentPos) {
                if let pos = vm.currentPos {
                    withAnimation { proxy.scrollTo(pos, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Lyrics Panel

    private var lyricsPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if lyricsLoading {
                    ProgressView()
                        .padding(20)
                } else if !syncedLines.isEmpty {
                    LazyVStack(spacing: 4) {
                        ForEach(syncedLines) { line in
                            let isCurrent = currentLineIndex == line.id
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: isCurrent ? 13 : 11, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(isCurrent ? .white : .secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 2)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                } else if let plain = plainLyrics {
                    Text(plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    Text("No lyrics found")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(20)
                }
            }
            .frame(height: 200)
            .onChange(of: currentLineIndex) {
                if let idx = currentLineIndex {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var coverArt: some View {
        if vm.state == "stop" && vm.currentTitle == "---" {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
        } else {
            CoverView(file: vm.playlist.first(where: { $0.pos == vm.currentPos })?.file ?? "")
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func fetchLyrics() {
        let key = "\(vm.currentArtist)-\(vm.currentTitle)"
        guard key != lastLyricsTrack else { return }
        lastLyricsTrack = key
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
                    if let synced = result.synced {
                        syncedLines = parseSyncedLyrics(synced)
                    }
                    plainLyrics = result.plain
                }
            }
        }
    }

    private func parseSyncedLyrics(_ lrc: String) -> [SyncedLine] {
        var lines: [SyncedLine] = []
        for (i, line) in lrc.components(separatedBy: "\n").enumerated() {
            // [mm:ss.xx] text
            guard line.hasPrefix("["),
                  let closeBracket = line.firstIndex(of: "]") else { continue }
            let timeStr = String(line[line.index(after: line.startIndex)..<closeBracket])
            let text = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
            let parts = timeStr.split(separator: ":")
            guard parts.count == 2,
                  let mins = Double(parts[0]),
                  let secs = Double(parts[1]) else { continue }
            lines.append(SyncedLine(id: i, time: mins * 60 + secs, text: text))
        }
        return lines
    }
}
