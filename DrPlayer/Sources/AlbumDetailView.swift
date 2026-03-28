import SwiftUI

struct AlbumDetailView: View {
    @State var album: Album
    let allAlbums: [Album]
    let currentPos: Int?
    let currentAlbumTitle: String
    let onPlayAlbum: () -> Void
    let onEnqueueAlbum: () -> Void
    let onStartRadio: () -> Void
    let onPlayTrack: (Int) -> Void
    let onEnqueueTrack: (Track) -> Void
    let onPlayFile: (String) -> Void
    let versionCountFor: (Track) -> Int
    let onSetPreferred: ((String) -> Void)?
    let preferredFiles: Set<String>
    let onBack: () -> Void
    let onToggleFavorite: (Track) -> Void
    let onSelectGenre: (String) -> Void
    let onSearch: (String) -> Void

    @State private var cover: NSImage?
    @State private var artworkCount = 0
    @State private var artworkPaths: [String] = []
    @State private var showArtwork = false
    @State private var selectedTrack: Track? = nil

    var isThisAlbumPlaying: Bool {
        currentAlbumTitle == album.title
    }

    var body: some View {
        if let track = selectedTrack {
            TrackDetailView(
                track: track,
                allAlbums: allAlbums,
                onPlay: {
                    if let idx = album.tracks.firstIndex(where: { $0.id == track.id }) {
                        onPlayTrack(idx)
                    }
                },
                onEnqueue: { onEnqueueTrack(track) },
                onPlayFile: onPlayFile,
                onDismiss: { selectedTrack = nil }
            )
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Back button
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Biblioteca")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

                // Header: cover + metadata
                albumHeader
                    .padding()

                // Genre tags
                if !album.genres.isEmpty {
                    genreTags
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }

                // Artwork gallery
                if artworkPaths.count > 1 {
                    artworkSection
                }

                // Other editions
                let editions = findOtherEditions()
                if !editions.isEmpty {
                    otherEditionsSection(editions)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                Divider()
                    .padding(.horizontal)

                // Track list
                trackList
                    .padding(.top, 8)
            }
        }
        .task {
            let a = album
            cover = await a.coverImageAsync()
            let paths = await Task.detached { a.allArtwork }.value
            artworkPaths = paths
            artworkCount = paths.count
        }
        } // end else
    }

    // MARK: - Album Header

    private var albumHeader: some View {
        HStack(alignment: .top, spacing: 20) {
            // Album info (left)
            VStack(alignment: .leading, spacing: 6) {
                if !album.date.isEmpty {
                    clickableText(album.date, font: .subheadline, color: .secondary)
                }
                Text(album.title)
                    .font(.largeTitle.bold())
                    .lineLimit(3)
                clickableText(album.artist, font: .title3, color: .secondary)

                // Action buttons
                HStack(spacing: 10) {
                    Button(action: onPlayAlbum) {
                        Label("Reproducir", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button(action: onEnqueueAlbum) {
                        Label("Añadir a cola", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button(action: onStartRadio) {
                        Label("Radio", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Generar playlist basada en este album")
                }
                .padding(.top, 8)

                // Metadata grid
                metadataGrid
                    .padding(.top, 12)
            }
            .frame(minWidth: 200)

            // Center: MusicBrainz + Wikipedia info
            AlbumInfoView(artist: album.artist, albumTitle: album.title, musicbrainzAlbumId: album.musicbrainzAlbumId)
                .frame(maxWidth: .infinity)

            // Cover art (right)
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 240, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 200, height: 200)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
    }

    // MARK: - Metadata Grid

    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            if !album.formattedDuration.isEmpty {
                GridRow {
                    Text("Duración")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(album.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GridRow {
                Text("Pistas")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("\(album.tracks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !album.format.isEmpty {
                GridRow {
                    Text("Formato")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(album.format)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            if let dr = album.avgDR, dr > 0 {
                GridRow {
                    Text("Rango Dinámico")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 4) {
                        Text("DR\(dr)")
                            .font(.caption.bold().monospaced())
                            .foregroundColor(drColor(dr))
                        drBar(dr)
                    }
                }
            }
            if artworkCount > 0 {
                GridRow {
                    Text("Imágenes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(artworkCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Genre Tags

    private var genreTags: some View {
        FlowLayout(spacing: 6) {
            ForEach(album.genres, id: \.self) { genre in
                Button {
                    onSelectGenre(genre)
                } label: {
                    Text(genre.uppercased())
                        .font(.caption2.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.secondary, lineWidth: 1)
                        )
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
    }

    // MARK: - Clickable text helper

    private func clickableText(_ text: String, font: Font, color: Color) -> some View {
        Button { onSearch(text) } label: {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .underline(false)
        }
        .buttonStyle(.plain)
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }

    // MARK: - Artwork Gallery

    private var artworkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showArtwork.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showArtwork ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.caption)
                    Text("Artwork (\(artworkPaths.count) imágenes)")
                        .font(.caption.bold())
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 8)

            if showArtwork {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        ForEach(artworkPaths, id: \.self) { path in
                            ArtworkThumbnail(path: path)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Other Editions

    private func normalizeForMatch(_ s: String) -> String {
        // Remove parenthesized suffixes like "(UiCY-40190)", "(Remastered 2011)", etc.
        var cleaned = s
        // Remove trailing parenthesized content
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove trailing bracketed content
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        return cleaned.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    private func findOtherEditions() -> [Album] {
        let titleNorm = normalizeForMatch(album.title)
        let artistNorm = album.artist.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        return allAlbums.filter { other in
            guard other.id != album.id else { return false }
            let otherArtist = other.artist.lowercased()
                .folding(options: .diacriticInsensitive, locale: .current)
            guard otherArtist == artistNorm else { return false }
            let otherTitle = normalizeForMatch(other.title)
            return otherTitle == titleNorm
        }
        .sorted { $0.format < $1.format }
    }

    @State private var otherEditionCovers: [String: NSImage] = [:]

    private func otherEditionsSection(_ editions: [Album]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Otras ediciones")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(editions, id: \.id) { edition in
                HStack(spacing: 10) {
                    // Cover thumbnail
                    Group {
                        if let img = otherEditionCovers[edition.id] {
                            Image(nsImage: img)
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
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .task {
                        let e = edition
                        let img = await e.coverImageAsync()
                        if let img { otherEditionCovers[edition.id] = img }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(edition.title)
                            .font(.callout)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if !edition.format.isEmpty {
                                Text(edition.format)
                                    .font(.caption2.monospaced().bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(.blue.opacity(0.15)))
                                    .foregroundColor(.blue)
                            }
                            if !edition.date.isEmpty {
                                Text(edition.date)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if let dr = edition.avgDR, dr > 0 {
                                Text("DR\(dr)")
                                    .font(.caption2.bold().monospaced())
                                    .foregroundColor(drColor(dr))
                            }
                            Text("\(edition.tracks.count) pistas")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Button {
                        onPlayFile(edition.tracks.first?.file ?? "")
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reproducir esta edicion")
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                .onTapGesture {
                    // Navigate to this edition
                    // We can reuse the current view by swapping album
                    album = edition
                    selectedTrack = nil
                    // Reload cover
                    Task {
                        let a = edition
                        cover = await a.coverImageAsync()
                        let paths = await Task.detached { a.allArtwork }.value
                        artworkPaths = paths
                        artworkCount = paths.count
                    }
                }
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
        }
    }

    // MARK: - DR helpers

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
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(drColor(dr))
                    .frame(width: geo.size.width * normalized)
            }
        }
        .frame(width: 60, height: 6)
    }

    // MARK: - Track List

    private var trackList: some View {
        VStack(spacing: 0) {
            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { idx, track in
                TrackRow(
                    track: track,
                    index: idx,
                    albumArtist: album.artist,
                    isCurrentTrack: isThisAlbumPlaying && currentPos == idx,
                    versionCount: versionCountFor(track),
                    allAlbums: allAlbums,
                    onTap: { selectedTrack = track },
                    onPlay: { onPlayTrack(idx) },
                    onToggleFavorite: {
                        onToggleFavorite(track)
                        if let i = album.tracks.firstIndex(where: { $0.id == track.id }) {
                            album.tracks[i].isFavorite.toggle()
                        }
                    },
                    onPlayFile: onPlayFile,
                    onSetPreferred: onSetPreferred,
                    preferredFiles: preferredFiles,
                    onEnqueue: { onEnqueueTrack(track) }
                )

                if idx < album.tracks.count - 1 {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
    }
}

// MARK: - Flow Layout for tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
