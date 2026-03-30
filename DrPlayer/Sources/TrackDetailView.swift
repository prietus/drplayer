import SwiftUI

/// Metadata extracted from ffprobe for a track
struct TrackMetadata {
    var tags: [String: String] = [:]
    var codec: String = ""
    var codecLong: String = ""
    var sampleRate: String = ""
    var channels: Int = 0
    var channelLayout: String = ""
    var bitDepth: String = ""
    var duration: String = ""
    var bitrate: String = ""
    var fileSize: String = ""
    var formatName: String = ""
    var sampleFormat: String = ""
}

struct TrackDetailView: View {
    let track: Track
    let allAlbums: [Album]
    let onPlay: () -> Void
    let onEnqueue: () -> Void
    let onPlayFile: (String) -> Void
    let onDismiss: () -> Void
    var onSelectAlbum: ((Album) -> Void)? = nil
    @State private var metadata: TrackMetadata?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                header
                    .padding()

                Divider().padding(.horizontal)

                if loading {
                    ProgressView("Loading...")
                        .padding(40)
                        .frame(maxWidth: .infinity)
                } else if let meta = metadata {
                    // Audio info
                    sectionTitle("Audio")
                    audioSection(meta)

                    Divider().padding(.horizontal)

                    // File info
                    sectionTitle("File")
                    fileSection(meta)

                    // Tags
                    if !meta.tags.isEmpty {
                        Divider().padding(.horizontal)
                        sectionTitle("Tags")
                        tagsSection(meta.tags)
                    }

                    // DR info
                    if let dr = track.dr, dr > 0 {
                        Divider().padding(.horizontal)
                        sectionTitle(String(localized: "Dynamic Range", defaultValue: "Dynamic Range"))
                        drSection(dr)
                    }

                    // Other versions of this track (basic list)
                    let versions = findOtherVersions()
                    if !versions.isEmpty {
                        Divider().padding(.horizontal)
                        sectionTitle(String(
                            localized: "Other versions (%d)",
                            defaultValue: "Other versions (\(versions.count))"
                        ))
                        otherVersionsSection(versions)
                    }
                }

                Spacer().frame(height: 20)
            }
        }
        .task {
            let fullPath = AppSettings.shared.resolveFilePath(track.file)
            let meta = await TrackProbe.probe(path: fullPath)
            metadata = meta
            loading = false
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

                Text(track.title)
                    .font(.title.bold())
                Text(track.artist)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if !track.album.isEmpty {
                    if let onSelectAlbum,
                       let album = allAlbums.first(where: { $0.title == track.album && $0.artist == track.albumArtist }) {
                        Button {
                            onSelectAlbum(album)
                        } label: {
                            Text(track.album)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    } else {
                        Text(track.album)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(action: onEnqueue) {
                        Label("Add to queue", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 6)
            }
            Spacer()
        }
    }

    // MARK: - Sections

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func audioSection(_ meta: TrackMetadata) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            metaRow("Codec", meta.codecLong.isEmpty ? meta.codec : meta.codecLong)
            if !meta.sampleRate.isEmpty {
                let sr = Int(meta.sampleRate) ?? 0
                let display = sr >= 1000 ? String(format: "%.1f kHz", Double(sr) / 1000.0) : "\(sr) Hz"
                metaRow("Sample Rate", display)
            }
            if !meta.bitDepth.isEmpty && meta.bitDepth != "0" {
                metaRow("Bit Depth", "\(meta.bitDepth) bit")
            }
            if !meta.sampleFormat.isEmpty {
                metaRow("Sample Format", meta.sampleFormat)
            }
            metaRow("Channels", meta.channelLayout.isEmpty ? "\(meta.channels)" : "\(meta.channels) (\(meta.channelLayout))")
            if !meta.duration.isEmpty {
                let secs = Double(meta.duration) ?? 0
                let mins = Int(secs) / 60
                let s = Int(secs) % 60
                metaRow("Duration", String(format: "%d:%02d (%.3fs)", mins, s, secs))
            }
            if !meta.bitrate.isEmpty && meta.bitrate != "0" {
                let br = Int(meta.bitrate) ?? 0
                metaRow("Bitrate", "\(br / 1000) kbps")
            }
        }
        .padding(.horizontal)
    }

    private func fileSection(_ meta: TrackMetadata) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            metaRow("Path", track.file)
            if !meta.formatName.isEmpty {
                metaRow("Format", meta.formatName)
            }
            if !meta.fileSize.isEmpty {
                let bytes = Int(meta.fileSize) ?? 0
                metaRow("Size", formatFileSize(bytes))
            }
        }
        .padding(.horizontal)
    }

    /// Tags to hide from the UI (internal/technical IDs)
    private static let hiddenTagPrefixes = [
        "musicbrainz", "acoustid", "script", "replaygain",
        "encoder", "barcode", "asin", "isrc", "catalognumber",
        "media", "totaldiscs", "totaltracks", "tracktotal", "disctotal",
        "releasestatus", "releasetype", "releasecountry",
    ]

    private func tagsSection(_ tags: [String: String]) -> some View {
        let filtered = tags.filter { key, _ in
            let lower = key.lowercased()
            return !Self.hiddenTagPrefixes.contains(where: { lower.hasPrefix($0) })
        }
        return Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            ForEach(filtered.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                metaRow(key, value)
            }
        }
        .padding(.horizontal)
    }

    private func drSection(_ dr: Int) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            GridRow {
                Text("DR Value")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 120, alignment: .trailing)
                HStack(spacing: 6) {
                    Text("DR\(dr)")
                        .font(.caption.bold().monospaced())
                        .foregroundColor(drColor(dr))
                    drBar(dr)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func metaRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes > 1_000_000_000 {
            return String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
        } else if bytes > 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        }
        return String(format: "%.1f KB", Double(bytes) / 1000)
    }

    private func drColor(_ dr: Int) -> Color {
        switch dr {
        case 14...: return .green
        case 10...13: return .yellow
        case 7...9: return .orange
        default: return .red
        }
    }

    private func drBar(_ dr: Int) -> some View {
        let normalized = min(Double(dr) / 20.0, 1.0)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(drColor(dr)).frame(width: geo.size.width * normalized)
            }
        }
        .frame(width: 80, height: 6)
    }

    // MARK: - Other Versions

    private struct TrackVersion: Identifiable {
        let id: String  // file path
        let track: Track
        let album: Album
        let format: String
    }

    /// Normalize a track title for fuzzy matching:
    /// removes parenthesized/bracketed suffixes, "remastered" tags, etc.
    private func normalizeTitle(_ s: String) -> String {
        var cleaned = s
        // Remove trailing parenthesized content: (Remastered 2011), (Live), (Dedicated To...)
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove trailing bracketed content: [Deluxe Edition]
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove " - Remastered" suffix
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

                // Artist match: exact, or one contains the other, or either is empty
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

    private func otherVersionsSection(_ versions: [TrackVersion]) -> some View {
        VStack(spacing: 0) {
            ForEach(versions) { version in
                HStack(spacing: 10) {
                    Button {
                        onPlayFile(version.track.file)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 3) {
                        // Album title
                        Text(version.album.title)
                            .font(.callout)
                            .lineLimit(1)

                        // Technical: format, DR, duration
                        HStack(spacing: 6) {
                            if !version.format.isEmpty {
                                Text(version.format)
                                    .font(.caption2.monospaced().bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(formatColor(version.format).opacity(0.15)))
                                    .foregroundColor(formatColor(version.format))
                            }
                            if let dr = version.track.dr, dr > 0 {
                                HStack(spacing: 3) {
                                    Text("DR\(dr)")
                                        .font(.caption2.bold().monospaced())
                                        .foregroundColor(drColor(dr))
                                    drBar(dr)
                                }
                            }
                            let mins = Int(version.track.duration) / 60
                            let secs = Int(version.track.duration) % 60
                            if version.track.duration > 0 {
                                Text(String(format: "%d:%02d", mins, secs))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        // Release info: label, date, country
                        HStack(spacing: 6) {
                            if !version.album.label.isEmpty {
                                Text(version.album.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !version.track.country.isEmpty {
                                Text(version.track.country)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !version.album.date.isEmpty {
                                Text(version.album.date)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if !version.album.originalDate.isEmpty && version.album.originalDate != version.album.date {
                                Text("(orig. \(version.album.originalDate))")
                                    .font(.caption2)
                                    .foregroundStyle(.quaternary)
                            }
                        }

                        // File path
                        let folder = (version.track.file as NSString).deletingLastPathComponent
                        if !folder.isEmpty {
                            Text(folder)
                                .font(.system(size: 9).monospaced())
                                .foregroundStyle(.quaternary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelectAlbum?(version.album)
                }
                .onHover { h in if h && onSelectAlbum != nil { NSCursor.pointingHand.push() } else if !h { NSCursor.pop() } }

                if version.id != versions.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
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
