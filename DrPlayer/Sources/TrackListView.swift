import SwiftUI

struct TrackListView: View {
    let tracks: [Track]
    let allAlbums: [Album]
    let onPlay: (Track) -> Void
    let onPlayFile: (String) -> Void

    @State private var searchText = ""
    @State private var sortKey: SortKey = .title
    @State private var sortAscending = true

    enum SortKey: String, CaseIterable {
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case duration = "Duration"
        case composer = "Composer"
    }

    private var filteredAndSorted: [Track] {
        var result = tracks

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q)
                || $0.artist.lowercased().contains(q)
                || $0.album.lowercased().contains(q)
                || $0.composer.lowercased().contains(q)
            }
        }

        result.sort { a, b in
            let cmp: ComparisonResult
            switch sortKey {
            case .title:
                cmp = a.title.localizedCaseInsensitiveCompare(b.title)
            case .artist:
                cmp = a.artist.localizedCaseInsensitiveCompare(b.artist)
            case .album:
                cmp = a.album.localizedCaseInsensitiveCompare(b.album)
            case .duration:
                return sortAscending ? a.duration < b.duration : a.duration > b.duration
            case .composer:
                cmp = a.composer.localizedCaseInsensitiveCompare(b.composer)
            }
            return sortAscending ? cmp == .orderedAscending : cmp == .orderedDescending
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + sort controls
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Search tracks...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Picker("Sort", selection: $sortKey) {
                    ForEach(SortKey.allCases, id: \.self) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                Button {
                    sortAscending.toggle()
                } label: {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(sortAscending ? "Ascending" : "Descending")

                Text("\(filteredAndSorted.count) tracks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Column headers
            HStack(spacing: 0) {
                Text("").frame(width: 28)  // play button
                columnHeader("Title", key: .title, width: nil, flex: true)
                columnHeader("Artist", key: .artist, width: 150)
                columnHeader("Album", key: .album, width: 150)
                columnHeader("Composer", key: .composer, width: 120)
                Text("DR")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
                    .frame(width: 40)
                columnHeader("Dur.", key: .duration, width: 50)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5))

            // Track list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredAndSorted) { track in
                        trackRow(track)
                        Divider().padding(.leading, 36)
                    }
                }
            }
        }
    }

    private func columnHeader(_ label: String, key: SortKey, width: CGFloat?, flex: Bool = false) -> some View {
        Button {
            if sortKey == key {
                sortAscending.toggle()
            } else {
                sortKey = key
                sortAscending = true
            }
        } label: {
            HStack(spacing: 2) {
                Text(label)
                    .font(.caption2.bold())
                if sortKey == key {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
            }
            .foregroundStyle(sortKey == key ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: flex ? .infinity : nil, alignment: .leading)
        .frame(width: flex ? nil : width, alignment: .leading)
    }

    private func trackRow(_ track: Track) -> some View {
        HStack(spacing: 0) {
            Button { onPlay(track) } label: {
                Image(systemName: "play.circle")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .frame(width: 28)

            Text(track.title)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Text(track.album)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Text(track.composer)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            if let dr = track.dr, dr > 0 {
                Text("DR\(dr)")
                    .font(.caption2.bold().monospaced())
                    .foregroundColor(drColor(dr))
                    .frame(width: 40)
            } else {
                Text("")
                    .frame(width: 40)
            }

            if track.duration > 0 {
                let mins = Int(track.duration) / 60
                let secs = Int(track.duration) % 60
                Text(String(format: "%d:%02d", mins, secs))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text("")
                    .frame(width: 50)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func drColor(_ dr: Int) -> Color {
        switch dr {
        case 14...: return .green
        case 10...13: return .yellow
        case 7...9: return .orange
        default: return .red
        }
    }
}
