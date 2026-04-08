import SwiftUI

struct AlbumDetailView: View {
    @State var album: Album
    let allAlbums: [Album]
    let currentPos: Int?
    let currentAlbumTitle: String
    var currentFile: String = ""
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
    let onSetRating: (Track, Int) -> Void
    let onSelectGenre: (String) -> Void
    let onSearch: (String) -> Void
    var onSelectLabel: ((String) -> Void)? = nil
    var onSelectCountry: ((String) -> Void)? = nil
    var onSelectFormat: ((String) -> Void)? = nil
    var onSelectProducer: ((String) -> Void)? = nil
    var onScanDR: ((Int) async -> Void)? = nil
    var onUpdateDB: ((String) async -> Void)? = nil

    @State private var cover: NSImage?
    @State private var artworkCount = 0
    @State private var artworkPaths: [String] = []
    @State private var showArtwork = false
    @State private var selectedTrack: Track? = nil
    @State private var showEditionComparison = false
    @State private var showCoverZoom = false
    @State private var mbRelease: MBRelease?
    @State private var dgRelease: DiscogsRelease?

    var isThisAlbumPlaying: Bool {
        currentAlbumTitle == album.title
    }

    /// Live album from ViewModel (updates reactively when DR is analyzed)
    private var liveAlbum: Album {
        allAlbums.first(where: { $0.id == album.id }) ?? album
    }

    /// Live tracks from ViewModel (updates reactively when DR is analyzed)
    private var liveTracks: [Track] {
        liveAlbum.tracks
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
                onDismiss: { selectedTrack = nil },
                onSelectAlbum: { targetAlbum in
                    selectedTrack = nil
                    album = targetAlbum
                    Task {
                        let a = targetAlbum
                        cover = await a.coverImageAsync()
                        let paths = await Task.detached { a.allArtwork }.value
                        artworkPaths = paths
                        artworkCount = paths.count
                    }
                }
            )
        } else if showEditionComparison {
            EditionComparisonView(
                album: album,
                allAlbums: allAlbums,
                onPlayFile: onPlayFile,
                onSetPreferred: onSetPreferred,
                preferredFiles: preferredFiles,
                onBack: { showEditionComparison = false },
                onScanDR: onScanDR,
                onSelectLabel: onSelectLabel
            )
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Back button
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Library")
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
        .task(id: album.id) {
            await loadReleaseInfo()
        }
        .task(id: album.id) {
            // Auto-scan DR for all tracks when opening an album
            if let onScanDR, let idx = allAlbums.firstIndex(where: { $0.id == album.id }) {
                await onScanDR(idx)
            }
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
                HStack(spacing: 6) {
                    Button(action: onPlayAlbum) {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .help("Play album")

                    Button(action: onEnqueueAlbum) {
                        Image(systemName: "text.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Add to queue")

                    Button(action: onStartRadio) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Generate playlist based on this album")

                    Button { showEditionComparison = true } label: {
                        Image(systemName: "arrow.triangle.swap")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Compare editions")

                    Menu {
                        Button {
                            let path = (AppSettings.shared.resolveFilePath(album.folder) as NSString).resolvingSymlinksInPath
                            NSWorkspace.shared.open(
                                [URL(fileURLWithPath: path)],
                                withApplicationAt: URL(fileURLWithPath: "/Applications/MusicBrainz Picard.app"),
                                configuration: NSWorkspace.OpenConfiguration()
                            )
                        } label: {
                            Label("Open in Picard", systemImage: "tag")
                        }

                        Button {
                            let path = (AppSettings.shared.resolveFilePath(album.folder) as NSString).resolvingSymlinksInPath
                            NSWorkspace.shared.open(
                                [URL(fileURLWithPath: path)],
                                withApplicationAt: URL(fileURLWithPath: "/Applications/DrDoctor.app"),
                                configuration: NSWorkspace.OpenConfiguration()
                            )
                        } label: {
                            Label("Open in Dr. Doctor", systemImage: "waveform.badge.magnifyingglass")
                        }

                        Button {
                            Task {
                                // Clear cached API data so it re-fetches with new tags
                                mbRelease = nil
                                dgRelease = nil
                                await onUpdateDB?(album.folder)
                                // Reload release info with updated metadata
                                await loadReleaseInfo()
                            }
                        } label: {
                            Label("Refresh tags", systemImage: "arrow.trianglehead.clockwise")
                        }

                        Button {
                            Task {
                                CoverArtService.clearCache(artist: album.artist, album: album.title)
                                cover = await album.coverImageAsync()
                            }
                        } label: {
                            Label("Retry cover art", systemImage: "photo")
                        }

                        Divider()

                        Button {
                            let path = (AppSettings.shared.resolveFilePath(album.folder) as NSString).resolvingSymlinksInPath
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.top, 8)

                // Metadata grid
                metadataGrid
                    .padding(.top, 12)
            }
            .frame(minWidth: 200)

            // Center: MusicBrainz + Wikipedia info
            AlbumInfoView(artist: album.artist, albumTitle: album.title, musicbrainzAlbumId: album.musicbrainzAlbumId, fileLabel: album.label)
                .frame(maxWidth: .infinity)

            // Cover art (right) — click to enlarge
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 240, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 8)
                    .onTapGesture { showCoverZoom = true }
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    .popover(isPresented: $showCoverZoom) {
                        Image(nsImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 600, maxHeight: 600)
                            .padding(8)
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 200, height: 200)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                            Button {
                                Task {
                                    CoverArtService.clearCache(artist: album.artist, album: album.title)
                                    cover = await album.coverImageAsync()
                                }
                            } label: {
                                Label("Retry", systemImage: "arrow.trianglehead.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
            }
        }
    }

    // MARK: - Metadata Grid

    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            if !album.formattedDuration.isEmpty {
                GridRow {
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(album.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GridRow {
                Text("Tracks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("\(album.tracks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !album.format.isEmpty {
                GridRow {
                    Text("Format")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let onSelectFormat {
                        Button { onSelectFormat(album.format) } label: {
                            Text(album.format)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    } else {
                        Text(album.format)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let dr = liveAlbum.avgDR, dr > 0 {
                GridRow {
                    Text("Dynamic Range")
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
            // Release identification: label, catalog, country
            if let label = releaseLabel, !label.isEmpty {
                GridRow {
                    Text("Label")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let onSelectLabel {
                        Button { onSelectLabel(label) } label: {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    } else {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let catalog = releaseCatalog, !catalog.isEmpty {
                GridRow {
                    Text("Catalog")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(catalog)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            if let country = releaseCountry, !country.isEmpty {
                GridRow {
                    Text("Country")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let onSelectCountry {
                        Button { onSelectCountry(country) } label: {
                            Text(country)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    } else {
                        Text(country)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Producer / Engineer / Mastering from MusicBrainz credits
            if let mb = mbRelease {
                if !mb.producers.isEmpty {
                    GridRow {
                        Text("Producer")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        creditLinks(mb.producers)
                    }
                }
                if !mb.engineers.isEmpty {
                    GridRow {
                        Text("Engineer")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        creditLinks(mb.engineers)
                    }
                }
                if !mb.masteringEngineers.isEmpty {
                    GridRow {
                        Text("Mastering")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        creditLinks(mb.masteringEngineers)
                    }
                }
            }
            if artworkCount > 0 {
                GridRow {
                    Text("Images")
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
                    Text("Artwork (\(artworkPaths.count) images)")
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
            Text("Other editions")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(editions, id: \.id) { edition in
                Button {
                    album = edition
                    selectedTrack = nil
                    Task {
                        let a = edition
                        cover = await a.coverImageAsync()
                        let paths = await Task.detached { a.allArtwork }.value
                        artworkPaths = paths
                        artworkCount = paths.count
                    }
                } label: {
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
                                Text("\(edition.tracks.count) tracks")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                .contextMenu {
                    Button {
                        onPlayFile(edition.tracks.first?.file ?? "")
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    Button {
                        for track in edition.tracks {
                            onEnqueueTrack(track)
                        }
                    } label: {
                        Label("Add to queue", systemImage: "text.badge.plus")
                    }
                    Divider()
                    Button {
                        let path = (AppSettings.shared.resolveFilePath(edition.folder) as NSString).resolvingSymlinksInPath
                        NSWorkspace.shared.open(
                            [URL(fileURLWithPath: path)],
                            withApplicationAt: URL(fileURLWithPath: "/Applications/DrDoctor.app"),
                            configuration: NSWorkspace.OpenConfiguration()
                        )
                    } label: {
                        Label("Analyze in Dr. Doctor", systemImage: "waveform.badge.magnifyingglass")
                    }
                    Button {
                        let currentPath = (AppSettings.shared.resolveFilePath(album.folder) as NSString).resolvingSymlinksInPath
                        let editionPath = (AppSettings.shared.resolveFilePath(edition.folder) as NSString).resolvingSymlinksInPath
                        openInDrDoctor([currentPath, editionPath])
                    } label: {
                        Label("Compare with current", systemImage: "arrow.left.arrow.right")
                    }
                }
                .overlay(alignment: .trailing) {
                    Menu {
                        Button {
                            onPlayFile(edition.tracks.first?.file ?? "")
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        Button {
                            for track in edition.tracks {
                                onEnqueueTrack(track)
                            }
                        } label: {
                            Label("Add to queue", systemImage: "text.badge.plus")
                        }
                        Divider()
                        Button {
                            let path = (AppSettings.shared.resolveFilePath(edition.folder) as NSString).resolvingSymlinksInPath
                            NSWorkspace.shared.open(
                                [URL(fileURLWithPath: path)],
                                withApplicationAt: URL(fileURLWithPath: "/Applications/DrDoctor.app"),
                                configuration: NSWorkspace.OpenConfiguration()
                            )
                        } label: {
                            Label("Analyze in Dr. Doctor", systemImage: "waveform.badge.magnifyingglass")
                        }
                        Button {
                            let currentPath = (AppSettings.shared.resolveFilePath(album.folder) as NSString).resolvingSymlinksInPath
                            let editionPath = (AppSettings.shared.resolveFilePath(edition.folder) as NSString).resolvingSymlinksInPath
                            openInDrDoctor([currentPath, editionPath])
                        } label: {
                            Label("Compare with current", systemImage: "arrow.left.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.trailing, 8)
                }
            }
        }
    }

    // MARK: - Release Info

    private var releaseLabel: String? {
        // Prefer file tag — it reflects the actual pressing the user owns
        if !album.label.isEmpty { return album.label }
        // Fall back to API sources matched by catalog number
        if let mb = mbRelease, !mb.label.isEmpty, !mb.catalogNumber.isEmpty {
            return mb.label
        }
        if let dg = dgRelease, !dg.label.isEmpty, !dg.catalogNumber.isEmpty {
            return dg.label
        }
        return mbRelease?.label ?? dgRelease?.label
    }

    /// Whether MusicBrainz found the exact pressing (matching file label and catalog)
    private var mbMatchesEdition: Bool {
        guard let mb = mbRelease else { return true }
        // Check label match
        let labelMatch: Bool
        let cleanedLabel = cleanLabel(album.label)
        if cleanedLabel.isEmpty || mb.label.isEmpty {
            labelMatch = true
        } else {
            labelMatch = mb.label.localizedCaseInsensitiveContains(cleanedLabel)
                || cleanedLabel.localizedCaseInsensitiveContains(mb.label)
        }
        // Check catalog match — if file has a catalog in its title, it must match MB's catalog
        if let fileCatno = extractCatalog(album.title), !fileCatno.isEmpty, !mb.catalogNumber.isEmpty {
            let normalizedFile = fileCatno.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").lowercased()
            let normalizedMB = mb.catalogNumber.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").lowercased()
            if normalizedFile != normalizedMB && !normalizedMB.contains(normalizedFile) && !normalizedFile.contains(normalizedMB) {
                return false
            }
        }
        return labelMatch
    }

    /// Strip common prefixes from label tags: (P), (C), ℗, ©
    private func cleanLabel(_ label: String) -> String {
        var cleaned = label
        // Remove (P), (C), ℗, © prefixes
        cleaned = cleaned.replacingOccurrences(of: #"^\(P\)\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^\(C\)\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^[℗©]\s*"#, with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Open paths in DrDoctor using `open -a` (single invocation, no double-launch)
    private func openInDrDoctor(_ paths: [String]) {
        var pid: pid_t = 0
        let args = ["/usr/bin/open", "-a", "DrDoctor"] + paths
        var cArgs = args.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        posix_spawn(&pid, "/usr/bin/open", nil, nil, &cArgs, environ)
    }

    private var releaseCatalog: String? {
        let mb = mbMatchesEdition ? mbRelease?.catalogNumber : nil
        return mb ?? dgRelease?.catalogNumber
    }

    private var releaseCountry: String? {
        let mb = mbMatchesEdition ? mbRelease?.country : nil
        return mb ?? dgRelease?.country
    }

    /// Clean album title for API searches
    private func cleanTitleForSearch(_ title: String) -> String {
        var cleaned = title
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201C}\u{201D}\u{00AB}\u{00BB}"))
        if let range = cleaned.range(of: #"^\d{4}\s+"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        if let range = cleaned.range(of: #"\s+(SHM-CD|SHM-SACD|HDCD|MQA-CD|XRCD|K2HD|HQCD|Blu-spec CD|UHQCD).*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        if let range = cleaned.range(of: #"\s+(Legacy|Anniversary|Collector|Limited|Special)\s+(Collection|Edition).*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        if let range = cleaned.range(of: #"\s*-\s*(remaster|deluxe|bonus).*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        if let range = cleaned.range(of: #"\s*-\s*(CD|Disc)\s.*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        if let range = cleaned.range(of: #"\s+\d{4}\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Extract catalog number from album title parentheses.
    private func extractCatalog(_ title: String) -> String? {
        let patterns = [
            #"\(([A-Z]{2,}[\s-]?\d[\w\s-]*)\)"#,
            #"\((\d+[\s-][A-Z][\w\s-]*)\)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range(at: 1), in: title) {
                let candidate = String(title[range])
                let lower = candidate.lowercased()
                if lower.contains("remaster") || lower.contains("deluxe") ||
                   lower.contains("live") || lower.contains("edition") { continue }
                return candidate
            }
        }
        return nil
    }

    /// Detect MusicBrainz format/country hints from album format and title keywords
    private func detectHints() -> (format: String?, country: String?) {
        let fmt = album.format.uppercased()
        let title = album.title.lowercased()
        // DSF/DSD files → SACD
        if fmt.contains("DSF") || fmt.contains("DFF") || fmt.contains("DSD") {
            return ("sacd", "JP")
        }
        // Title keywords
        if title.contains("shm-sacd") || title.contains("shm sacd") { return ("sacd", "JP") }
        if title.contains("shm-cd") || title.contains("shm cd") || title.contains("uhqcd") ||
           title.contains("blu-spec") || title.contains("hqcd") { return ("cd", "JP") }
        if title.contains("sacd") { return ("sacd", nil) }
        if title.contains("xrcd") || title.contains("k2hd") { return (nil, "JP") }
        if title.contains("vinyl") || title.contains(" lp") { return ("Vinyl", nil) }
        return (nil, nil)
    }

    private func loadReleaseInfo() async {
        let cleanAlbum = cleanTitleForSearch(album.title)
        let catalogFromTitle = extractCatalog(album.title)
        let hints = detectHints()

        // MusicBrainz: use file label to find the correct pressing
        let tagLabel = cleanLabel(album.label)
        var mb: MBRelease?
        if !album.musicbrainzAlbumId.isEmpty {
            mb = await MusicBrainzService.fetchRelease(id: album.musicbrainzAlbumId)
        }
        // Try catalog + label first (e.g. "8397" + "Analogue Productions")
        if mb == nil, let catno = catalogFromTitle, !tagLabel.isEmpty {
            mb = await MusicBrainzService.searchByCatalog(artist: album.artist, catno: catno, label: tagLabel)
        }
        if mb == nil, let catno = catalogFromTitle {
            mb = await MusicBrainzService.searchByCatalog(artist: album.artist, catno: catno)
        }
        if mb == nil, hints.format != nil || hints.country != nil {
            mb = await MusicBrainzService.searchRelease(artist: album.artist, album: cleanAlbum, format: hints.format, country: hints.country, label: tagLabel.isEmpty ? nil : tagLabel)
        }
        if mb == nil, !tagLabel.isEmpty {
            mb = await MusicBrainzService.searchRelease(artist: album.artist, album: cleanAlbum, label: tagLabel)
        }
        if mb == nil {
            mb = await MusicBrainzService.searchRelease(artist: album.artist, album: cleanAlbum)
        }
        if mb == nil && cleanAlbum != album.title {
            mb = await MusicBrainzService.searchRelease(artist: album.artist, album: album.title)
        }
        mbRelease = mb

        // Discogs: use file label + MB country to find the correct pressing
        let mbCountry = mb?.country
        let dgLabel = tagLabel.isEmpty ? nil : tagLabel
        var dg: DiscogsRelease?
        if let catno = catalogFromTitle {
            dg = await DiscogsService.searchByCatalog(catno, country: mbCountry, label: dgLabel, format: hints.format)
        }
        if dg == nil, let catno = mb?.catalogNumber, !catno.isEmpty {
            dg = await DiscogsService.searchByCatalog(catno, country: mbCountry, label: dgLabel, format: hints.format)
        }
        if dg == nil, let barcode = mb?.barcode, !barcode.isEmpty {
            dg = await DiscogsService.searchByBarcode(barcode, country: mbCountry)
        }
        if dg == nil {
            dg = await DiscogsService.search(artist: album.artist, album: cleanAlbum)
        }
        dgRelease = dg

        // If Discogs found a more specific catalog number, retry MusicBrainz with it
        if let dg, !dg.catalogNumber.isEmpty,
           dg.catalogNumber != mb?.catalogNumber {
            if let better = await MusicBrainzService.searchByCatalog(artist: album.artist, catno: dg.catalogNumber) {
                mbRelease = better
            }
        }
    }

    // MARK: - DR helpers

    @ViewBuilder
    private func creditLinks(_ names: [String]) -> some View {
        if let onSelectProducer {
            FlowLayout(spacing: 0) {
                ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                    Button { onSelectProducer(name) } label: {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                    if i < names.count - 1 {
                        Text(", ")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } else {
            Text(names.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
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
        let tracks = liveTracks
        return VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                TrackRow(
                    track: track,
                    index: idx,
                    albumArtist: album.artist,
                    isCurrentTrack: track.file == currentFile,
                    versionCount: versionCountFor(track),
                    allAlbums: allAlbums,
                    onTap: { selectedTrack = track },
                    onPlay: { onPlayTrack(idx) },
                    onSetRating: { rating in
                        onSetRating(track, rating)
                        if let i = album.tracks.firstIndex(where: { $0.id == track.id }) {
                            album.tracks[i].rating = rating
                        }
                    },
                    onPlayFile: onPlayFile,
                    onSetPreferred: onSetPreferred,
                    preferredFiles: preferredFiles,
                    onEnqueue: { onEnqueueTrack(track) },
                    onSelectAlbum: { targetAlbum in
                        album = targetAlbum
                        selectedTrack = nil
                        Task {
                            let a = targetAlbum
                            cover = await a.coverImageAsync()
                            let paths = await Task.detached { a.allArtwork }.value
                            artworkPaths = paths
                            artworkCount = paths.count
                        }
                    }
                )

                if idx < tracks.count - 1 {
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
