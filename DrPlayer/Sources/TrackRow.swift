import SwiftUI

struct TrackRow: View {
    let track: Track
    let index: Int
    let albumArtist: String
    let isCurrentTrack: Bool
    let allAlbums: [Album]
    let onTap: () -> Void
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    let onPlayFile: (String) -> Void
    var onEnqueue: (() -> Void)? = nil

    @State private var showVersions = false

    var body: some View {
        HStack(spacing: 8) {
            // Play button
            Button(action: onPlay) {
                Image(systemName: isCurrentTrack ? "speaker.wave.2.fill" : "play.circle")
                    .font(.caption)
                    .foregroundColor(isCurrentTrack ? .accentColor : .gray)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help("Reproducir")

            // Track number
            trackNumber

            // Title + artist
            titleAndArtist

            Spacer()

            // Versions badge
            versionsBadge

            // Queue button
            enqueueButton
            // DR badge
            drBadge
            // Favorite
            favoriteButton
            // Duration
            durationLabel
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .background(isCurrentTrack ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private var trackNumber: some View {
        let num = track.trackNumber.isEmpty ? String(index + 1) : track.trackNumber
        return Text(num)
            .font(.caption.monospaced())
            .foregroundStyle(.tertiary)
            .frame(width: 24, alignment: .trailing)
    }

    private var titleAndArtist: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(track.title)
                .fontWeight(isCurrentTrack ? .bold : .regular)
                .lineLimit(1)
            if !track.artist.isEmpty && track.artist != albumArtist {
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Versions Badge

    @ViewBuilder
    private var versionsBadge: some View {
        let versions = findOtherVersions()
        if !versions.isEmpty {
            Button {
                showVersions.toggle()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                    Text("\(versions.count)")
                        .font(.caption2.bold())
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(.blue.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Otras versiones de este track")
            .popover(isPresented: $showVersions, arrowEdge: .bottom) {
                versionsPopover(versions)
            }
        }
    }

    private func versionsPopover(_ versions: [TrackVersion]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Otras versiones")
                .font(.headline)
                .padding(.bottom, 8)

            ForEach(versions) { version in
                HStack(spacing: 8) {
                    Button {
                        onPlayFile(version.track.file)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Reproducir esta version")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(version.album.title)
                            .font(.callout)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if !version.format.isEmpty {
                                Text(version.format)
                                    .font(.caption2.monospaced().bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(.blue.opacity(0.15)))
                                    .foregroundColor(.blue)
                            }
                            if !version.album.date.isEmpty {
                                Text(version.album.date)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if let dr = version.track.dr, dr > 0 {
                                Text("DR\(dr)")
                                    .font(.caption2.bold().monospaced())
                                    .foregroundColor(drColor(dr))
                            }
                            if version.track.duration > 0 {
                                let mins = Int(version.track.duration) / 60
                                let secs = Int(version.track.duration) % 60
                                Text(String(format: "%d:%02d", mins, secs))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                if version.id != versions.last?.id {
                    Divider()
                }
            }
        }
        .padding(12)
        .frame(minWidth: 280, maxWidth: 360)
    }

    // MARK: - Version matching

    private struct TrackVersion: Identifiable {
        let id: String
        let track: Track
        let album: Album
        let format: String
    }

    private func normalizeTitle(_ s: String) -> String {
        var cleaned = s
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        if let range = cleaned.range(of: #"\s*-\s*remaster.*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        return cleaned.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    private func findOtherVersions() -> [TrackVersion] {
        let titleNorm = normalizeTitle(track.title)
        let artistNorm = track.artist.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        var versions: [TrackVersion] = []

        for album in allAlbums {
            for t in album.tracks {
                guard t.file != track.file else { continue }

                let tTitle = normalizeTitle(t.title)
                guard tTitle == titleNorm else { continue }

                let tArtist = t.artist.lowercased()
                    .folding(options: .diacriticInsensitive, locale: .current)
                let artistMatch = tArtist == artistNorm
                    || tArtist.contains(artistNorm)
                    || artistNorm.contains(tArtist)
                    || tArtist.isEmpty
                    || artistNorm.isEmpty

                if artistMatch {
                    versions.append(TrackVersion(
                        id: t.file,
                        track: t,
                        album: album,
                        format: album.format
                    ))
                }
            }
        }

        return versions.sorted { a, b in
            if a.format != b.format { return a.format < b.format }
            return a.album.title < b.album.title
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var enqueueButton: some View {
        if let onEnqueue {
            Button(action: onEnqueue) {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .help("Añadir a la cola")
        }
    }

    @ViewBuilder
    private var drBadge: some View {
        if let dr = track.dr, dr > 0 {
            Text("DR\(dr)")
                .font(.caption2.bold().monospaced())
                .foregroundColor(drColor(dr))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(drColor(dr).opacity(0.15))
                )
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

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                .font(.caption)
                .foregroundColor(track.isFavorite ? .red : .gray)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var durationLabel: some View {
        if track.duration > 0 {
            let mins = Int(track.duration) / 60
            let secs = Int(track.duration) % 60
            Text(String(format: "%d:%02d", mins, secs))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
