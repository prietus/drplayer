import SwiftUI

struct LabelListView: View {
    let labels: [PlayerViewModel.LabelInfo]
    let onSelectLabel: (PlayerViewModel.LabelInfo) -> Void
    let onPlayFile: (String) -> Void

    @State private var searchText = ""
    @State private var selectedLabel: PlayerViewModel.LabelInfo?

    private var filteredLabels: [PlayerViewModel.LabelInfo] {
        guard !searchText.isEmpty else { return labels }
        let q = searchText.lowercased()
        return labels.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        if let label = selectedLabel {
            LabelDetailPanel(
                label: label,
                onBack: { selectedLabel = nil },
                onSelectAlbum: { _ in onSelectLabel(label) },
                onPlayFile: onPlayFile
            )
        } else {
            labelListBody
        }
    }

    private var labelListBody: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search labels...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(filteredLabels.count) labels")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredLabels) { label in
                        Button {
                            selectedLabel = label
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.2")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(label.name)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("\(label.albumCount) albums · \(label.trackCount) tracks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
    }
}

// MARK: - Label Detail Panel

private struct LabelDetailPanel: View {
    let label: PlayerViewModel.LabelInfo
    let onBack: () -> Void
    let onSelectAlbum: (Album) -> Void
    let onPlayFile: (String) -> Void

    private var allGenres: [String] {
        let genres = label.albums.flatMap(\.genres)
        var seen = Set<String>()
        return genres.filter { seen.insert($0.lowercased()).inserted }
    }
    private var formats: [String] {
        let fmts = label.albums.compactMap { $0.format.isEmpty ? nil : $0.format }
        return Array(Set(fmts)).sorted()
    }
    private var avgDR: Int? {
        let drs = label.albums.compactMap(\.avgDR)
        guard !drs.isEmpty else { return nil }
        return drs.reduce(0, +) / drs.count
    }
    private var dateRange: String {
        let dates = label.albums.map(\.date).filter { !$0.isEmpty }.sorted()
        guard let first = dates.first else { return "" }
        let last = dates.last ?? first
        return first == last ? first : "\(first) – \(last)"
    }
    private var artists: [String] {
        var seen = Set<String>()
        return label.albums.compactMap { a in
            let key = a.artist.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return a.artist
        }.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Back button
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Labels")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

                // Header
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label.name)
                            .font(.largeTitle.bold())
                        Text("\(label.albumCount) albums · \(label.trackCount) tracks")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        // Stats
                        VStack(alignment: .leading, spacing: 4) {
                            if !dateRange.isEmpty {
                                Text("Years: \(dateRange)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let dr = avgDR {
                                HStack(spacing: 4) {
                                    Text("Avg DR\(dr)")
                                        .font(.caption.bold().monospaced())
                                        .foregroundColor(drColor(dr))
                                }
                            }
                            if !formats.isEmpty {
                                Text("Formats: \(formats.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)

                        // Artists on this label
                        if !artists.isEmpty {
                            Text("Artists: \(artists.prefix(10).joined(separator: ", "))\(artists.count > 10 ? "..." : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    Spacer()
                }
                .padding()

                // Genre tags
                if !allGenres.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(allGenres.prefix(20), id: \.self) { genre in
                            Text(genre.uppercased())
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().stroke(.secondary.opacity(0.3), lineWidth: 1))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }

                Divider().padding(.horizontal)

                // Albums from this label
                LazyVStack(spacing: 0) {
                    ForEach(label.albums.sorted { $0.date < $1.date }) { album in
                        Button {
                            onSelectAlbum(album)
                        } label: {
                            HStack(spacing: 12) {
                                // Cover
                                AsyncAlbumCover(album: album)
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.title)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(album.artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !album.date.isEmpty {
                                            Text(album.date)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    HStack(spacing: 6) {
                                        if !album.format.isEmpty {
                                            Text(album.format)
                                                .font(.caption2.monospaced().bold())
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(RoundedRectangle(cornerRadius: 3).fill(formatColor(album.format).opacity(0.15)))
                                                .foregroundColor(formatColor(album.format))
                                        }
                                        if let dr = album.avgDR, dr > 0 {
                                            Text("DR\(dr)")
                                                .font(.caption2.bold().monospaced())
                                                .foregroundColor(drColor(dr))
                                        }
                                        Text("\(album.tracks.count) tracks")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 76)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func drColor(_ dr: Int) -> Color {
        switch dr {
        case 14...: return .green
        case 10...13: return .yellow
        case 7...9: return .orange
        default: return .red
        }
    }

    private func formatColor(_ format: String) -> Color {
        let f = format.uppercased()
        if f.contains("DSF") || f.contains("DFF") || f.contains("DSD") { return .green }
        if f.contains("FLAC") || f.contains("WAV") || f.contains("AIFF") { return .blue }
        if f.contains("MQA") { return .purple }
        if f.contains("MP3") || f.contains("AAC") { return .orange }
        return .secondary
    }
}

// MARK: - Async Album Cover

private struct AsyncAlbumCover: View {
    let album: Album
    @State private var image: NSImage?

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
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .task {
            image = await album.coverImageAsync()
        }
    }
}
