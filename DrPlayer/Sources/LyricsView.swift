import SwiftUI

struct LyricsView: View {
    let vm: PlayerViewModel

    @State private var syncedLines: [SyncedLine] = []
    @State private var plainLyrics: String? = nil
    @State private var instrumental = false
    @State private var loading = false
    @State private var lastFetchedTrack = ""
    @State private var noLyrics = false

    private var currentLineIndex: Int? {
        guard !syncedLines.isEmpty else { return nil }
        let elapsed = vm.elapsed
        var best: Int? = nil
        for (i, line) in syncedLines.enumerated() {
            if line.time <= elapsed {
                best = i
            } else {
                break
            }
        }
        return best
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Lyrics")
                    .font(.headline)
                Spacer()
                if !syncedLines.isEmpty {
                    Text("Synced")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if plainLyrics != nil {
                    Text("Unsynced")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // Content
            if loading {
                Spacer()
                ProgressView()
                    .padding()
                Spacer()
            } else if instrumental {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "pianokeys")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Instrumental")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if noLyrics {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.xmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No lyrics available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if !syncedLines.isEmpty {
                syncedView
            } else if let plain = plainLyrics {
                ScrollView {
                    Text(plain)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer()
            }
        }
        .background(.ultraThinMaterial.opacity(0.5))
        .onChange(of: vm.currentTitle) {
            fetchIfNeeded()
        }
        .onAppear {
            fetchIfNeeded()
        }
    }

    // MARK: - Synced karaoke view

    private var syncedView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(syncedLines) { line in
                        let isCurrent = currentLineIndex == line.id
                        let isPast = (currentLineIndex ?? -1) > line.id

                        Text(line.text.isEmpty ? " " : line.text)
                            .font(isCurrent ? .title3.bold() : .body)
                            .foregroundStyle(
                                isCurrent ? .primary :
                                isPast ? .tertiary : .secondary
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, isCurrent ? 6 : 2)
                            .id(line.id)
                            .animation(.easeInOut(duration: 0.3), value: isCurrent)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: currentLineIndex) { _, newIndex in
                if let idx = newIndex {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Fetch

    private func fetchIfNeeded() {
        let trackKey = "\(vm.currentArtist)|\(vm.currentTitle)"
        guard !trackKey.isEmpty, trackKey != "|", trackKey != lastFetchedTrack else { return }
        lastFetchedTrack = trackKey

        syncedLines = []
        plainLyrics = nil
        instrumental = false
        noLyrics = false
        loading = true

        Task {
            let result = await LyricsService.fetchLyrics(
                artist: vm.currentArtist,
                title: vm.currentTitle,
                album: vm.currentAlbum,
                duration: vm.duration
            )

            await MainActor.run {
                loading = false
                if let result {
                    instrumental = result.instrumental
                    if let synced = result.synced, !synced.isEmpty {
                        syncedLines = LyricsService.parseSyncedLyrics(synced)
                    }
                    plainLyrics = result.plain
                    noLyrics = syncedLines.isEmpty && plainLyrics == nil && !instrumental
                } else {
                    noLyrics = true
                }
            }
        }
    }
}
