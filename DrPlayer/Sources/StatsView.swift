import SwiftUI

struct StatsView: View {
    let vm: PlayerViewModel
    let onPlayFile: (String) -> Void

    @State private var playStats: [PlayerViewModel.PlayStats] = []
    @State private var loading = true

    // Computed from playStats + library
    private var totalListeningTime: Double {
        var trackDurations: [String: Double] = [:]
        for album in vm.albums {
            for track in album.tracks {
                trackDurations[track.file] = track.duration
            }
        }
        return playStats.reduce(0.0) { total, stat in
            total + (trackDurations[stat.file] ?? 0) * Double(stat.playCount)
        }
    }

    private var totalPlays: Int {
        playStats.reduce(0) { $0 + $1.playCount }
    }

    private var uniqueTracks: Int { playStats.count }

    private var artistStats: [ArtistStat] {
        var byArtist: [String: ArtistStat] = [:]
        var trackDurations: [String: Double] = [:]
        for album in vm.albums {
            for track in album.tracks { trackDurations[track.file] = track.duration }
        }
        for stat in playStats {
            let artist = stat.artist.isEmpty ? "Unknown" : stat.artist
            let time = (trackDurations[stat.file] ?? 0) * Double(stat.playCount)
            if var existing = byArtist[artist] {
                existing.totalPlays += stat.playCount
                existing.totalTime += time
                existing.trackCount += 1
                byArtist[artist] = existing
            } else {
                byArtist[artist] = ArtistStat(name: artist, totalPlays: stat.playCount, totalTime: time, trackCount: 1)
            }
        }
        return byArtist.values.sorted { $0.totalTime > $1.totalTime }
    }

    private var albumStats: [AlbumStat] {
        var byAlbum: [String: AlbumStat] = [:]
        var trackDurations: [String: Double] = [:]
        for album in vm.albums {
            for track in album.tracks { trackDurations[track.file] = track.duration }
        }
        for stat in playStats {
            let key = "\(stat.artist)|\(stat.album)"
            let time = (trackDurations[stat.file] ?? 0) * Double(stat.playCount)
            if var existing = byAlbum[key] {
                existing.totalPlays += stat.playCount
                existing.totalTime += time
                byAlbum[key] = existing
            } else {
                byAlbum[key] = AlbumStat(title: stat.album, artist: stat.artist, totalPlays: stat.playCount, totalTime: time, file: stat.file)
            }
        }
        return byAlbum.values.sorted { $0.totalTime > $1.totalTime }
    }

    private var genreStats: [GenreStat] {
        var byGenre: [String: Double] = [:]
        var trackDurations: [String: Double] = [:]
        var trackGenres: [String: String] = [:]
        for album in vm.albums {
            let genre = album.genres.first ?? ""
            for track in album.tracks {
                trackDurations[track.file] = track.duration
                trackGenres[track.file] = track.genre.isEmpty ? genre : track.genre
            }
        }
        for stat in playStats {
            let genre = trackGenres[stat.file] ?? "Unknown"
            let time = (trackDurations[stat.file] ?? 0) * Double(stat.playCount)
            byGenre[genre, default: 0] += time
        }
        return byGenre.map { GenreStat(name: $0.key, totalTime: $0.value) }
            .filter { !$0.name.isEmpty }
            .sorted { $0.totalTime > $1.totalTime }
    }

    var body: some View {
        if loading {
            VStack {
                Spacer()
                ProgressView("Loading play history...")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .task { await reload() }
        } else if playStats.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "chart.bar")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No play data yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Stats will appear here as you listen to music")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .task { await reload() }
        } else {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero: total listening time
                    heroSection

                    // Cards row
                    HStack(alignment: .top, spacing: 16) {
                        genreCard
                        topArtistsCard
                        topAlbumsCard
                    }

                    // Top tracks list
                    topTracksSection

                    // Recent
                    recentSection
                }
                .padding(20)
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        loading = true
        playStats = await vm.loadPlayStats()
        loading = false
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(spacing: 40) {
            // Total time
            VStack(spacing: 4) {
                Image(systemName: "headphones")
                    .font(.system(size: 28))
                    .foregroundStyle(.cyan)
                Text(formatDurationLarge(totalListeningTime))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("Total listening time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Stats chips
            VStack(alignment: .leading, spacing: 8) {
                statChip(icon: "play.fill", value: "\(totalPlays)", label: "plays")
                statChip(icon: "music.note", value: "\(uniqueTracks)", label: "tracks played")
                statChip(icon: "person.2.fill", value: "\(artistStats.count)", label: "artists")
                statChip(icon: "square.stack.fill", value: "\(albumStats.count)", label: "albums")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private func statChip(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.cyan)
                .frame(width: 16)
            Text(value)
                .font(.callout.bold().monospaced())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Genre Donut

    private var genreCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Genres")
                .font(.headline)

            let top = Array(genreStats.prefix(6))
            let total = top.reduce(0.0) { $0 + $1.totalTime }

            ZStack {
                // Donut chart
                donutChart(slices: top, total: total)
                    .frame(width: 120, height: 120)

                VStack(spacing: 0) {
                    Text("\(top.count)")
                        .font(.title2.bold())
                    Text("genres")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            // Legend
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(top.enumerated()), id: \.element.name) { i, genre in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(genreColor(i))
                            .frame(width: 8, height: 8)
                        Text(genre.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(formatDurationShort(genre.totalTime))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private func donutChart(slices: [GenreStat], total: Double) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let innerRadius = radius * 0.6
            var startAngle = Angle.degrees(-90)

            for (i, slice) in slices.enumerated() {
                let fraction = total > 0 ? slice.totalTime / total : 0
                let endAngle = startAngle + Angle.degrees(360 * fraction)

                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
                path.closeSubpath()

                context.fill(path, with: .color(genreColor(i)))
                startAngle = endAngle
            }
        }
    }

    private func genreColor(_ index: Int) -> Color {
        let colors: [Color] = [.cyan, .purple, .blue, .indigo, .teal, .mint]
        return colors[index % colors.count]
    }

    // MARK: - Top Artists Card

    private var topArtistsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Artists")
                .font(.headline)

            let top = Array(artistStats.prefix(5))
            let maxTime = top.first?.totalTime ?? 1

            VStack(spacing: 10) {
                ForEach(top, id: \.name) { artist in
                    HStack(spacing: 10) {
                        ArtistAvatarThumbnail(name: artist.name)
                            .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(artist.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.purple.opacity(0.6))
                                    .frame(width: geo.size.width * CGFloat(artist.totalTime / maxTime))
                            }
                            .frame(height: 4)
                        }

                        Text(formatDurationShort(artist.totalTime))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Top Albums Card

    private var topAlbumsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Albums")
                .font(.headline)

            let top = Array(albumStats.prefix(5))
            let maxTime = top.first?.totalTime ?? 1

            VStack(spacing: 10) {
                ForEach(top, id: \.title) { album in
                    HStack(spacing: 10) {
                        CoverView(file: album.file)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(album.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(album.artist)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.cyan.opacity(0.6))
                                    .frame(width: geo.size.width * CGFloat(album.totalTime / maxTime))
                            }
                            .frame(height: 4)
                        }

                        Text(formatDurationShort(album.totalTime))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Top Tracks

    private var topTracksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Tracks")
                .font(.headline)

            let maxCount = playStats.first?.playCount ?? 1

            ForEach(Array(playStats.prefix(10).enumerated()), id: \.element.file) { index, stat in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.title)
                            .font(.callout)
                            .lineLimit(1)
                        Text("\(stat.artist) — \(stat.album)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(stat.playCount)")
                        .font(.callout.bold().monospaced())
                        .foregroundStyle(.cyan)

                    // Proportional bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.cyan.opacity(0.3))
                        .frame(width: CGFloat(stat.playCount) / CGFloat(maxCount) * 100, height: 16)
                }
                .contentShape(Rectangle())
                .onTapGesture { onPlayFile(stat.file) }

                if index < min(playStats.count, 10) - 1 {
                    Divider().padding(.leading, 32)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Recent

    private var recentSection: some View {
        let recent = playStats
            .filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Recently Played")
                .font(.headline)

            ForEach(Array(recent.prefix(8).enumerated()), id: \.element.file) { index, stat in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.title)
                            .font(.callout)
                            .lineLimit(1)
                        Text("\(stat.artist) — \(stat.album)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let last = stat.lastPlayed {
                        Text(relativeDate(last))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onPlayFile(stat.file) }

                if index < min(recent.count, 8) - 1 {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Helpers

    private func formatDurationLarge(_ secs: Double) -> String {
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func formatDurationShort(_ secs: Double) -> String {
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)min"
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Data Types

private struct ArtistStat {
    let name: String
    var totalPlays: Int
    var totalTime: Double
    var trackCount: Int
}

private struct AlbumStat {
    let title: String
    let artist: String
    var totalPlays: Int
    var totalTime: Double
    let file: String  // any file from this album, for cover art
}

private struct GenreStat {
    let name: String
    let totalTime: Double
}

// MARK: - Artist Avatar Thumbnail

private struct ArtistAvatarThumbnail: View {
    let name: String
    @State private var avatar: NSImage?

    var body: some View {
        Group {
            if let img = avatar {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .task {
            avatar = await ArtistAvatarService.avatar(for: name)
        }
    }
}
