import SwiftUI

struct StatsView: View {
    let vm: PlayerViewModel
    let onPlayFile: (String) -> Void

    @State private var playStats: [PlayerViewModel.PlayStats] = []
    @State private var history: [PlayHistory.Entry] = []
    @State private var trackDurations: [String: Double] = [:]
    @State private var trackGenres: [String: String] = [:]
    @State private var trackLabels: [String: String] = [:]
    @State private var loading = true

    enum TimePeriod: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        case allTime = "All Time"

        var startDate: Date? {
            let cal = Calendar.current
            switch self {
            case .week: return cal.date(byAdding: .day, value: -7, to: Date())
            case .month: return cal.date(byAdding: .month, value: -1, to: Date())
            case .year: return cal.date(byAdding: .year, value: -1, to: Date())
            case .allTime: return nil
            }
        }
    }
    @State private var period: TimePeriod = .allTime

    private var filteredHistory: [PlayHistory.Entry] {
        guard let start = period.startDate else { return history }
        return history.filter { $0.timestamp >= start }
    }

    private var periodListeningTime: Double {
        filteredHistory.reduce(0) { $0 + $1.duration }
    }

    private var periodPlays: Int { filteredHistory.count }

    private var periodArtists: [ArtistStat] {
        var byArtist: [String: ArtistStat] = [:]
        for entry in filteredHistory {
            let name = entry.artist.isEmpty ? "Unknown" : entry.artist
            if var existing = byArtist[name] {
                existing.totalPlays += 1
                existing.totalTime += entry.duration
                byArtist[name] = existing
            } else {
                byArtist[name] = ArtistStat(name: name, totalPlays: 1, totalTime: entry.duration, trackCount: 1)
            }
        }
        return byArtist.values.sorted { $0.totalTime > $1.totalTime }
    }

    private var periodAlbums: [AlbumStat] {
        var byAlbum: [String: AlbumStat] = [:]
        for entry in filteredHistory {
            let key = "\(entry.artist)|\(entry.album)"
            if var existing = byAlbum[key] {
                existing.totalPlays += 1
                existing.totalTime += entry.duration
                byAlbum[key] = existing
            } else {
                byAlbum[key] = AlbumStat(title: entry.album, artist: entry.artist, totalPlays: 1, totalTime: entry.duration, file: entry.file)
            }
        }
        return byAlbum.values.sorted { $0.totalTime > $1.totalTime }
    }

    private var periodGenres: [GenreStat] {
        var byGenre: [String: Double] = [:]
        for entry in filteredHistory {
            let genre = trackGenres[entry.file] ?? "Unknown"
            byGenre[genre, default: 0] += entry.duration
        }
        return byGenre.map { GenreStat(name: $0.key, totalTime: $0.value) }
            .filter { !$0.name.isEmpty }
            .sorted { $0.totalTime > $1.totalTime }
    }

    private var periodLabels: [LabelStat] {
        var byLabel: [String: Double] = [:]
        for entry in filteredHistory {
            let label = trackLabels[entry.file] ?? ""
            guard !label.isEmpty else { continue }
            byLabel[label, default: 0] += entry.duration
        }
        return byLabel.map { LabelStat(name: $0.key, totalTime: $0.value) }
            .sorted { $0.totalTime > $1.totalTime }
    }

    // Day of week heatmap
    private var dayOfWeekStats: [(day: String, hours: Double)] {
        let cal = Calendar.current
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var byDay = [Int: Double]() // 1=Sun...7=Sat in Calendar, remap to Mon=0
        for entry in filteredHistory {
            let weekday = cal.component(.weekday, from: entry.timestamp) // 1=Sun
            let idx = (weekday + 5) % 7 // Mon=0, Tue=1, ..., Sun=6
            byDay[idx, default: 0] += entry.duration
        }
        return dayNames.enumerated().map { (day: $1, hours: (byDay[$0] ?? 0) / 3600.0) }
    }

    // Hour of day heatmap
    private var hourOfDayStats: [(hour: Int, plays: Int)] {
        let cal = Calendar.current
        var byHour = [Int: Int]()
        for entry in filteredHistory {
            let hour = cal.component(.hour, from: entry.timestamp)
            byHour[hour, default: 0] += 1
        }
        return (0..<24).map { (hour: $0, plays: byHour[$0] ?? 0) }
    }

    var body: some View {
        Group {
            if loading {
                VStack {
                    Spacer()
                    ProgressView("Loading play history...")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if playStats.isEmpty && history.isEmpty {
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
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Period selector
                        periodPicker

                        heroSection

                        // Cards row 1: genres, artists, albums
                        HStack(alignment: .top, spacing: 16) {
                            genreCard
                            topArtistsCard
                            topAlbumsCard
                        }

                        // Cards row 2: labels, day of week, hour of day
                        HStack(alignment: .top, spacing: 16) {
                            topLabelsCard
                            dayOfWeekCard
                            hourOfDayCard
                        }

                        topTracksSection
                        recentSection
                    }
                    .padding(20)
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        var durations: [String: Double] = [:]
        var genres: [String: String] = [:]
        var labels: [String: String] = [:]
        for album in vm.albums {
            let genre = album.genres.first ?? ""
            for track in album.tracks {
                durations[track.file] = track.duration
                genres[track.file] = track.genre.isEmpty ? genre : track.genre
                labels[track.file] = track.label.isEmpty ? album.label : track.label
            }
        }
        trackDurations = durations
        trackGenres = genres
        trackLabels = labels
        playStats = await vm.loadPlayStats()
        history = PlayHistory.loadAll()
        loading = false
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(TimePeriod.allCases, id: \.self) { p in
                Button {
                    period = p
                } label: {
                    Text(p.rawValue)
                        .font(.caption.weight(period == p ? .bold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(period == p ? Color.cyan : Color.clear)
                        .foregroundStyle(period == p ? .white : .secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        let time = period == .allTime ? totalListeningTimeAllTime : periodListeningTime
        let plays = period == .allTime ? totalPlaysAllTime : periodPlays
        let artists = period == .allTime ? allTimeArtistCount : periodArtists.count
        let albums = period == .allTime ? allTimeAlbumCount : periodAlbums.count
        let tracks = period == .allTime ? playStats.count : Set(filteredHistory.map(\.file)).count

        return HStack(spacing: 40) {
            VStack(spacing: 4) {
                Image(systemName: "headphones")
                    .font(.system(size: 28))
                    .foregroundStyle(.cyan)
                Text(formatDurationLarge(time))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text(period == .allTime ? "Total listening time" : "\(period.rawValue) listening time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                statChip(icon: "play.fill", value: "\(plays)", label: "plays")
                statChip(icon: "music.note", value: "\(tracks)", label: "tracks")
                statChip(icon: "person.2.fill", value: "\(artists)", label: "artists")
                statChip(icon: "square.stack.fill", value: "\(albums)", label: "albums")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // All-time stats from stickers (more accurate than history log)
    private var totalListeningTimeAllTime: Double {
        playStats.reduce(0.0) { $0 + (trackDurations[$1.file] ?? 0) * Double($1.playCount) }
    }
    private var totalPlaysAllTime: Int {
        playStats.reduce(0) { $0 + $1.playCount }
    }
    private var allTimeArtistCount: Int {
        Set(playStats.map(\.artist)).count
    }
    private var allTimeAlbumCount: Int {
        Set(playStats.map { "\($0.artist)|\($0.album)" }).count
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
        let stats = period == .allTime ? allTimeGenreStats : periodGenres
        let top = Array(stats.prefix(6))
        let total = top.reduce(0.0) { $0 + $1.totalTime }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Genres")
                .font(.headline)

            ZStack {
                donutChart(slices: top, total: total)
                    .frame(width: 120, height: 120)
                VStack(spacing: 0) {
                    Text("\(stats.count)")
                        .font(.title2.bold())
                    Text("genres")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(top.enumerated()), id: \.element.name) { i, genre in
                    HStack(spacing: 6) {
                        Circle().fill(genreColor(i)).frame(width: 8, height: 8)
                        Text(genre.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(formatDurationShort(genre.totalTime))
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private var allTimeGenreStats: [GenreStat] {
        var byGenre: [String: Double] = [:]
        for stat in playStats {
            let genre = trackGenres[stat.file] ?? "Unknown"
            let time = (trackDurations[stat.file] ?? 0) * Double(stat.playCount)
            byGenre[genre, default: 0] += time
        }
        return byGenre.map { GenreStat(name: $0.key, totalTime: $0.value) }
            .filter { !$0.name.isEmpty }
            .sorted { $0.totalTime > $1.totalTime }
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

    // MARK: - Top Artists

    private var topArtistsCard: some View {
        let stats = period == .allTime ? allTimeArtistStats : periodArtists
        let top = Array(stats.prefix(5))
        let maxTime = top.first?.totalTime ?? 1

        return VStack(alignment: .leading, spacing: 8) {
            Text("Top Artists").font(.headline)
            VStack(spacing: 10) {
                ForEach(top, id: \.name) { artist in
                    HStack(spacing: 10) {
                        ArtistAvatarThumbnail(name: artist.name).frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(artist.name).font(.callout.weight(.medium)).lineLimit(1)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2).fill(.purple.opacity(0.6))
                                    .frame(width: geo.size.width * CGFloat(artist.totalTime / maxTime))
                            }.frame(height: 4)
                        }
                        Text(formatDurationShort(artist.totalTime))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private var allTimeArtistStats: [ArtistStat] {
        var byArtist: [String: ArtistStat] = [:]
        for stat in playStats {
            let name = stat.artist.isEmpty ? "Unknown" : stat.artist
            let time = (trackDurations[stat.file] ?? 0) * Double(stat.playCount)
            if var e = byArtist[name] { e.totalPlays += stat.playCount; e.totalTime += time; e.trackCount += 1; byArtist[name] = e }
            else { byArtist[name] = ArtistStat(name: name, totalPlays: stat.playCount, totalTime: time, trackCount: 1) }
        }
        return byArtist.values.sorted { $0.totalTime > $1.totalTime }
    }

    // MARK: - Top Albums

    private var topAlbumsCard: some View {
        let stats = period == .allTime ? allTimeAlbumStats : periodAlbums
        let top = Array(stats.prefix(5))
        let maxTime = top.first?.totalTime ?? 1

        return VStack(alignment: .leading, spacing: 8) {
            Text("Top Albums").font(.headline)
            VStack(spacing: 10) {
                ForEach(top, id: \.title) { album in
                    HStack(spacing: 10) {
                        CoverView(file: album.file).frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(album.title).font(.callout.weight(.medium)).lineLimit(1)
                            Text(album.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2).fill(.cyan.opacity(0.6))
                                    .frame(width: geo.size.width * CGFloat(album.totalTime / maxTime))
                            }.frame(height: 4)
                        }
                        Text(formatDurationShort(album.totalTime))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private var allTimeAlbumStats: [AlbumStat] {
        var byAlbum: [String: AlbumStat] = [:]
        for stat in playStats {
            let key = "\(stat.artist)|\(stat.album)"
            let time = (trackDurations[stat.file] ?? 0) * Double(stat.playCount)
            if var e = byAlbum[key] { e.totalPlays += stat.playCount; e.totalTime += time; byAlbum[key] = e }
            else { byAlbum[key] = AlbumStat(title: stat.album, artist: stat.artist, totalPlays: stat.playCount, totalTime: time, file: stat.file) }
        }
        return byAlbum.values.sorted { $0.totalTime > $1.totalTime }
    }

    // MARK: - Top Labels

    private var topLabelsCard: some View {
        let stats = period == .allTime ? allTimeLabelStats : periodLabels
        let top = Array(stats.prefix(5))
        let maxTime = top.first?.totalTime ?? 1

        return VStack(alignment: .leading, spacing: 8) {
            Text("Top Labels").font(.headline)
            VStack(spacing: 10) {
                ForEach(top, id: \.name) { label in
                    HStack(spacing: 10) {
                        Image(systemName: "building.2")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(label.name).font(.callout.weight(.medium)).lineLimit(1)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2).fill(.orange.opacity(0.6))
                                    .frame(width: geo.size.width * CGFloat(label.totalTime / maxTime))
                            }.frame(height: 4)
                        }
                        Text(formatDurationShort(label.totalTime))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            if top.isEmpty {
                Text("No label data").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private var allTimeLabelStats: [LabelStat] {
        var byLabel: [String: Double] = [:]
        for stat in playStats {
            let label = trackLabels[stat.file] ?? ""
            guard !label.isEmpty else { continue }
            let time = (trackDurations[stat.file] ?? 0) * Double(stat.playCount)
            byLabel[label, default: 0] += time
        }
        return byLabel.map { LabelStat(name: $0.key, totalTime: $0.value) }
            .sorted { $0.totalTime > $1.totalTime }
    }

    // MARK: - Day of Week

    private var dayOfWeekCard: some View {
        let stats = dayOfWeekStats
        let maxHours = stats.map(\.hours).max() ?? 1

        return VStack(alignment: .leading, spacing: 8) {
            Text("Day of Week").font(.headline)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(stats, id: \.day) { day in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.cyan.opacity(0.6))
                            .frame(width: 24, height: max(4, CGFloat(day.hours / maxHours) * 80))
                        Text(day.day)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0fh", day.hours))
                            .font(.system(size: 8).monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            if !filteredHistory.isEmpty {
                let totalHours = stats.reduce(0) { $0 + $1.hours }
                Text("Avg \(String(format: "%.1f", totalHours / 7))h/day")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Hour of Day

    private var hourOfDayCard: some View {
        let stats = hourOfDayStats
        let maxPlays = stats.map(\.plays).max() ?? 1

        return VStack(alignment: .leading, spacing: 8) {
            Text("Listening Hours").font(.headline)
            Canvas { context, size in
                let barWidth = size.width / 24
                for stat in stats {
                    let height = maxPlays > 0 ? CGFloat(stat.plays) / CGFloat(maxPlays) * (size.height - 16) : 0
                    let rect = CGRect(
                        x: CGFloat(stat.hour) * barWidth + 1,
                        y: size.height - 16 - height,
                        width: barWidth - 2,
                        height: height
                    )
                    let intensity = maxPlays > 0 ? Double(stat.plays) / Double(maxPlays) : 0
                    context.fill(Path(roundedRect: rect, cornerRadius: 2),
                                 with: .color(.purple.opacity(0.3 + 0.7 * intensity)))
                }
                // Hour labels
                for h in stride(from: 0, through: 23, by: 6) {
                    let x = CGFloat(h) * barWidth
                    context.draw(Text("\(h)h").font(.system(size: 8)).foregroundStyle(.secondary),
                                 at: CGPoint(x: x + barWidth / 2, y: size.height - 4))
                }
            }
            .frame(height: 100)

            let peakHour = stats.max(by: { $0.plays < $1.plays })?.hour ?? 0
            Text("Peak listening: \(peakHour):00")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Top Tracks

    private var topTracksSection: some View {
        let maxCount = playStats.first?.playCount ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("Top Tracks").font(.headline)
            ForEach(Array(playStats.prefix(10).enumerated()), id: \.element.file) { index, stat in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.monospaced().bold()).foregroundStyle(.tertiary)
                        .frame(width: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.title).font(.callout).lineLimit(1)
                        Text("\(stat.artist) — \(stat.album)")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(stat.playCount)")
                        .font(.callout.bold().monospaced()).foregroundStyle(.cyan)
                    RoundedRectangle(cornerRadius: 2).fill(.cyan.opacity(0.3))
                        .frame(width: CGFloat(stat.playCount) / CGFloat(maxCount) * 100, height: 16)
                }
                .contentShape(Rectangle())
                .onTapGesture { onPlayFile(stat.file) }
                if index < min(playStats.count, 10) - 1 { Divider().padding(.leading, 32) }
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
            Text("Recently Played").font(.headline)
            ForEach(Array(recent.prefix(8).enumerated()), id: \.element.file) { index, stat in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.title).font(.callout).lineLimit(1)
                        Text("\(stat.artist) — \(stat.album)")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if let last = stat.lastPlayed {
                        Text(relativeDate(last)).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onPlayFile(stat.file) }
                if index < min(recent.count, 8) - 1 { Divider() }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Helpers

    private func formatDurationLarge(_ secs: Double) -> String {
        let h = Int(secs) / 3600; let m = (Int(secs) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func formatDurationShort(_ secs: Double) -> String {
        let h = Int(secs) / 3600; let m = (Int(secs) % 3600) / 60
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
    let file: String
}

private struct GenreStat {
    let name: String
    let totalTime: Double
}

private struct LabelStat {
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
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).clipShape(Circle())
            } else {
                Circle().fill(.quaternary).overlay {
                    Image(systemName: "person.fill").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .task { avatar = await ArtistAvatarService.avatar(for: name) }
    }
}
