import SwiftUI

struct StatsView: View {
    let vm: PlayerViewModel
    let onPlayFile: (String) -> Void

    @State private var playStats: [PlayerViewModel.PlayStats] = []
    @State private var loading = true

    enum StatsTab: String, CaseIterable {
        case topTracks = "Top Tracks"
        case topArtists = "Top Artists"
        case recent = "Recent"
    }
    @State private var tab: StatsTab = .topTracks

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $tab) {
                ForEach(StatsTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .padding(.vertical, 8)

            if loading {
                Spacer()
                ProgressView("Loading play history...")
                    .foregroundStyle(.secondary)
                Spacer()
            } else if playStats.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No play data yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Stats will appear here as you listen to music")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                switch tab {
                case .topTracks:
                    topTracksView
                case .topArtists:
                    topArtistsView
                case .recent:
                    recentView
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        playStats = await vm.loadPlayStats()
        loading = false
    }

    // MARK: - Top Tracks

    private var topTracksView: some View {
        List(Array(playStats.prefix(50).enumerated()), id: \.element.file) { index, stat in
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.title)
                        .font(.body)
                        .lineLimit(1)
                    Text("\(stat.artist) — \(stat.album)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(stat.playCount) plays")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if let last = stat.lastPlayed {
                        Text(relativeDate(last))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Play count bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(.blue.opacity(0.3))
                    .frame(width: barWidth(for: stat), height: 20)
            }
            .contentShape(Rectangle())
            .onTapGesture { onPlayFile(stat.file) }
        }
        .listStyle(.plain)
    }

    // MARK: - Top Artists

    private struct ArtistPlayStat: Identifiable {
        let id: String
        var name: String { id }
        var totalPlays: Int
        var trackCount: Int
        var topTrack: String
    }

    private var artistStats: [ArtistPlayStat] {
        var byArtist: [String: ArtistPlayStat] = [:]
        for stat in playStats {
            let artist = stat.artist.isEmpty ? "Unknown" : stat.artist
            if var existing = byArtist[artist] {
                existing.totalPlays += stat.playCount
                existing.trackCount += 1
                if stat.playCount > (playStats.first(where: { $0.title == existing.topTrack })?.playCount ?? 0) {
                    existing.topTrack = stat.title
                }
                byArtist[artist] = existing
            } else {
                byArtist[artist] = ArtistPlayStat(
                    id: artist,
                    totalPlays: stat.playCount,
                    trackCount: 1,
                    topTrack: stat.title
                )
            }
        }
        return byArtist.values.sorted { $0.totalPlays > $1.totalPlays }
    }

    private var topArtistsView: some View {
        let artists = artistStats
        return List(Array(artists.prefix(30).enumerated()), id: \.element.id) { index, artist in
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .font(.body.bold())
                        .lineLimit(1)
                    Text("\(artist.trackCount) tracks · Top: \(artist.topTrack)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(artist.totalPlays) plays")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                RoundedRectangle(cornerRadius: 2)
                    .fill(.purple.opacity(0.3))
                    .frame(width: artistBarWidth(for: artist, in: artists), height: 20)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Recent

    private var recentView: some View {
        let recent = playStats
            .filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }

        return List(Array(recent.prefix(50).enumerated()), id: \.element.file) { _, stat in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.title)
                        .font(.body)
                        .lineLimit(1)
                    Text("\(stat.artist) — \(stat.album)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let last = stat.lastPlayed {
                        Text(relativeDate(last))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(stat.playCount) plays total")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onPlayFile(stat.file) }
        }
        .listStyle(.plain)
    }

    // MARK: - Helpers

    private func barWidth(for stat: PlayerViewModel.PlayStats) -> CGFloat {
        let maxCount = playStats.first?.playCount ?? 1
        return CGFloat(stat.playCount) / CGFloat(maxCount) * 80
    }

    private func artistBarWidth(for artist: ArtistPlayStat, in all: [ArtistPlayStat]) -> CGFloat {
        let maxCount = all.first?.totalPlays ?? 1
        return CGFloat(artist.totalPlays) / CGFloat(maxCount) * 80
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
