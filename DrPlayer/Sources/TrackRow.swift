import SwiftUI

struct TrackRow: View {
    let track: Track
    let index: Int
    let albumArtist: String
    let isCurrentTrack: Bool
    let versionCount: Int  // pre-computed, no search on render
    let allAlbums: [Album] // only used when popover opens
    let onTap: () -> Void
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    let onPlayFile: (String) -> Void
    let onSetPreferred: ((String) -> Void)?
    let preferredFiles: Set<String>  // files marked as preferred
    var onEnqueue: (() -> Void)? = nil

    @State private var showVersions = false
    @State private var showDRComparison = false

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
        if versionCount > 0 {
            Button {
                showVersions.toggle()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                    Text("\(versionCount)")
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
                versionsPopover(findOtherVersions()) // only computed on click
            }
        }
    }

    private func versionsPopover(_ versions: [TrackVersion]) -> some View {
        // Include current track in ranking
        let allVersions = [(track: track, album: allAlbums.first(where: { $0.tracks.contains(where: { $0.file == track.file }) }) ?? Album(id: "", title: track.album, artist: track.artist, folder: "", date: "", originalDate: "", label: "", musicbrainzAlbumId: "", genres: []))]
            + versions.map { (track: $0.track, album: $0.album) }
        let ranked = AudioQualityScore.rankVersions(allVersions)

        return VStack(alignment: .leading, spacing: 0) {
            Text("Comparar versiones")
                .font(.headline)
                .padding(.bottom, 8)

            ForEach(Array(ranked.enumerated()), id: \.offset) { idx, item in
                let isCurrentTrack = item.track.file == track.file

                HStack(spacing: 8) {
                    // Badge
                    Image(systemName: item.score.badge.rawValue)
                        .font(.caption)
                        .foregroundColor(badgeColor(item.score.badge))
                        .frame(width: 16)

                    // Play button (not for current track)
                    if !isCurrentTrack {
                        Button {
                            onPlayFile(item.track.file)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.callout)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .frame(width: 18)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(item.album.title)
                                .font(.callout)
                                .fontWeight(item.isBest ? .bold : .regular)
                                .lineLimit(1)
                            if item.isBest {
                                Text("MEJOR")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(.green.opacity(0.15)))
                            }
                            if isCurrentTrack {
                                Text("ACTUAL")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(.blue.opacity(0.15)))
                            }
                        }
                        HStack(spacing: 6) {
                            // Format badge
                            if !item.album.format.isEmpty {
                                Text(item.album.format)
                                    .font(.caption2.monospaced().bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(formatColor(item.album.format).opacity(0.15)))
                                    .foregroundColor(formatColor(item.album.format))
                            }
                            if !item.album.date.isEmpty {
                                Text(item.album.date)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if let dr = item.track.dr, dr > 0 {
                                Text("DR\(dr)")
                                    .font(.caption2.bold().monospaced())
                                    .foregroundColor(drColor(dr))
                            } else {
                                Text("DR?")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.quaternary)
                            }
                            // Quality score
                            Text("\(item.score.total)pts")
                                .font(.system(size: 9, weight: .medium).monospaced())
                                .foregroundStyle(.quaternary)
                        }
                    }

                    Spacer()

                    // "Set as preferred" button
                    if let onSetPreferred {
                        Button {
                            onSetPreferred(item.track.file)
                            showVersions = false
                        } label: {
                            Image(systemName: isPreferred(item.track) ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(isPreferred(item.track) ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isPreferred(item.track) ? "Version preferida" : "Usar como version preferida")
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .background(item.isBest ? Color.green.opacity(0.05) :
                           item.score.badge == .warning ? Color.red.opacity(0.03) : Color.clear)
                .cornerRadius(4)

                if idx < ranked.count - 1 {
                    Divider()
                }
            }
        }
        .padding(12)
        .frame(minWidth: 320, maxWidth: 420)
    }

    private func isPreferred(_ t: Track) -> Bool {
        preferredFiles.contains(t.file)
    }

    private func badgeColor(_ badge: AudioQualityScore.Badge) -> Color {
        switch badge {
        case .best: return .green
        case .good: return .secondary
        case .warning: return .orange
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
            Button {
                showDRComparison.toggle()
            } label: {
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
            .buttonStyle(.plain)
            .help("Comparar DR con otras ediciones en Loudness War DB")
            .popover(isPresented: $showDRComparison, arrowEdge: .bottom) {
                DRComparisonPopover(
                    artist: track.artist.isEmpty ? track.albumArtist : track.artist,
                    album: track.album,
                    myDR: dr
                )
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
