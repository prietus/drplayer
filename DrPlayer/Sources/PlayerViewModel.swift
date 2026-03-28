import SwiftUI

struct Track: Identifiable {
    let id: String
    let title: String
    let artist: String
    let albumArtist: String
    let album: String
    let file: String
    let pos: Int
    let duration: Double
    let genre: String
    let date: String
    let trackNumber: String
    let disc: String
    let composer: String
    let performer: String
    let conductor: String
    let label: String
    let originalDate: String
    let musicbrainzTrackId: String
    let musicbrainzAlbumId: String
    var isFavorite: Bool = false
    var dr: Int? = nil
}

@Observable
class PlayerViewModel {
    var currentTitle = "---"
    var currentArtist = ""
    var currentAlbum = ""
    var state = "stop"
    var playlist: [Track] = []
    var albums: [Album] = []
    var currentPos: Int? = nil
    var connected = false
    var error: String? = nil
    var audioFormat = ""
    var elapsed: Double = 0
    var duration: Double = 0
    var bitrate = ""
    var currentTrackDR: Int? = nil
    var waveformPeaks: [Float] = []
    var waveformFile: String = ""
    var audioOutputs: [MPDClient.AudioOutput] = []

    private var mpd: MPDClient
    private var timer: Timer?
    private var outputPollCounter = 0

    init() {
        let settings = AppSettings.shared
        self.mpd = MPDClient(host: settings.mpdHost, port: UInt16(settings.mpdPort))
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Poll less frequently when stopped
            Task { await self.refresh() }
        }
        Task {
            await refreshOutputs()
            await refresh()
            if albums.isEmpty {
                await loadLibrary()
            }
        }
    }

    func stop() {
        timer?.invalidate()
    }

    /// Reconnect to MPD with current settings (call after host/port change)
    func reconnect() {
        let settings = AppSettings.shared
        mpd = MPDClient(host: settings.mpdHost, port: UInt16(settings.mpdPort))
        lastPlaylistVersion = ""
        Task {
            await refresh()
            await loadLibrary()
        }
    }

    func refreshOutputs() async {
        if let outs = try? await mpd.outputs() {
            await MainActor.run { self.audioOutputs = outs }
        }
    }

    func toggleOutput(_ id: Int) async {
        try? await mpd.toggleOutput(id)
        await refreshOutputs()
    }

    private var lastPlaylistVersion = ""

    func refresh() async {
        do {
            let status = try await mpd.status()
            let song = try await mpd.currentSong()

            // Only fetch playlist if it changed (MPD tracks this with "playlist" version)
            let plVersion = status["playlist"] ?? ""
            let pl: [[String: String]]
            if plVersion != lastPlaylistVersion {
                pl = try await mpd.playlistInfo()
                lastPlaylistVersion = plVersion
            } else {
                pl = [] // empty means no update needed
            }

            let currentFile = song["file"] ?? ""

            await MainActor.run {
                self.state = status["state"] ?? "stop"
                self.currentTitle = song["Title"] ?? song["file"] ?? "---"
                self.currentArtist = song["Artist"] ?? ""
                self.currentAlbum = song["Album"] ?? ""
                self.currentPos = Int(song["Pos"] ?? "")
                self.audioFormat = status["audio"] ?? ""
                self.elapsed = Double(status["elapsed"] ?? "") ?? 0
                self.duration = Double(status["duration"] ?? "") ?? 0
                self.bitrate = status["bitrate"] ?? ""
                // DR14: check cache or compute in background
                if !currentFile.isEmpty {
                    self.analyzeDR14(for: currentFile)
                }
                self.connected = true
                self.error = nil
                if !pl.isEmpty {
                    self.playlist = Self.parseTracks(pl)
                }

                // Trigger waveform generation if song changed
                if !currentFile.isEmpty && currentFile != self.waveformFile {
                    self.waveformFile = currentFile
                    self.waveformPeaks = []
                    self.generateWaveform(for: currentFile)
                }
            }
            // Poll outputs every ~10 seconds
            outputPollCounter += 1
            if outputPollCounter % 10 == 1 {
                await refreshOutputs()
            }
        } catch {
            await MainActor.run {
                self.connected = false
                self.error = "Sin conexion a MPD"
            }
        }
    }

    func loadLibrary() async {
        try? await mpd.command("update")
        try? await Task.sleep(for: .seconds(2))

        // Fetch all tracks from MPD database
        do {
            let allTracks = try await mpd.listAllInfo()
            let grouped = Self.groupIntoAlbums(allTracks)

            let pl = try await mpd.playlistInfo()

            await MainActor.run {
                self.albums = grouped
                self.playlist = Self.parseTracks(pl)
            }

            // Background DR14 scan for all tracks
            await scanDR14InBackground()
        } catch {
            await MainActor.run {
                self.error = "Error cargando biblioteca"
            }
        }

        await refresh()
    }

    var isPlaying: Bool { state == "play" }

    func togglePlayPause() async {
        if isPlaying {
            try? await mpd.command("pause 1")
        } else {
            try? await mpd.command("pause 0")
        }
        await refresh()
    }

    func play() async {
        try? await mpd.command("play")
        await refresh()
    }

    func pause() async {
        try? await mpd.command("pause")
        await refresh()
    }

    func stopPlayback() async {
        try? await mpd.command("stop")
        await refresh()
    }

    func next() async {
        try? await mpd.command("next")
        await refresh()
    }

    func prev() async {
        try? await mpd.command("previous")
        await refresh()
    }

    func playTrack(_ pos: Int) async {
        try? await mpd.command("play \(pos)")
        await refresh()
    }

    /// Clear queue and play a specific album
    func playAlbum(_ album: Album) async {
        try? await mpd.command("clear")
        try? await mpd.command("add \"\(album.folder)\"")
        try? await mpd.command("play")

        // Refresh playlist
        if let pl = try? await mpd.playlistInfo() {
            await MainActor.run {
                self.playlist = Self.parseTracks(pl)
            }
        }
        await refresh()
    }

    // MARK: - Helpers

    // MARK: - Queue management

    /// Add album to end of queue without clearing
    func enqueueAlbum(_ album: Album) async {
        try? await mpd.command("add \"\(album.folder)\"")
        await refreshPlaylist()
    }

    /// Add a single track to end of queue
    func enqueueTrack(file: String) async {
        try? await mpd.command("add \"\(file)\"")
        await refreshPlaylist()
    }

    /// Add a single track to end of queue and play it immediately
    func enqueueAndPlay(file: String) async {
        // addid returns the id of the added song, and we can get its position
        let lines = try? await mpd.send("addid \"\(file)\"")
        if let idLine = lines?.first(where: { $0.hasPrefix("Id:") }),
           let songId = idLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) {
            try? await mpd.command("playid \(songId)")
        }
        await refreshPlaylist()
        await refresh()
    }

    /// Remove a track from the queue by position
    func removeFromQueue(pos: Int) async {
        try? await mpd.command("delete \(pos)")
        await refreshPlaylist()
    }

    /// Clear the entire queue
    func clearQueue() async {
        try? await mpd.command("clear")
        await refreshPlaylist()
    }

    private func refreshPlaylist() async {
        if let pl = try? await mpd.playlistInfo() {
            await MainActor.run {
                self.playlist = Self.parseTracks(pl)
            }
        }
    }

    // MARK: - DR14 Analysis

    private var dr14File: String = "" // track file currently being analyzed

    private func analyzeDR14(for file: String) {
        guard file != dr14File else { return }
        dr14File = file
        let musicBase = AppSettings.shared.musicLibraryPath
        let fullPath = "\(musicBase)/\(file)"
        Task.detached {
            let result = await DR14Analyzer.analyze(filePath: fullPath)
            await MainActor.run { [weak self] in
                guard let self, self.dr14File == file else { return }
                if let result {
                    self.currentTrackDR = result.dr
                }
            }
        }
    }

    /// Background scan: compute DR14 for all tracks.
    /// Updates album model incrementally as results come in.
    private func scanDR14InBackground() async {
        let musicBase = AppSettings.shared.musicLibraryPath
        let snapshot = await MainActor.run { self.albums }

        for (albumIdx, album) in snapshot.enumerated() {
            var trackDRs: [Int] = []
            var anyComputed = false

            for (trackIdx, track) in album.tracks.enumerated() {
                if let dr = track.dr {
                    trackDRs.append(dr)
                    continue
                }

                let fullPath = "\(musicBase)/\(track.file)"
                if let result = await DR14Analyzer.analyze(filePath: fullPath) {
                    trackDRs.append(result.dr)
                    anyComputed = true
                    let dr = result.dr
                    await MainActor.run { [weak self] in
                        guard let self,
                              albumIdx < self.albums.count,
                              trackIdx < self.albums[albumIdx].tracks.count else { return }
                        self.albums[albumIdx].tracks[trackIdx].dr = dr
                    }
                }
            }

            if anyComputed, let avgDR = DR14Analyzer.albumDR(trackDRs: trackDRs) {
                await MainActor.run { [weak self] in
                    guard let self, albumIdx < self.albums.count else { return }
                    if self.albums[albumIdx].avgDR == nil {
                        self.albums[albumIdx].avgDR = avgDR
                    }
                }
            }
        }
    }

    // MARK: - Waveform

    private func generateWaveform(for file: String) {
        let musicBase = AppSettings.shared.musicLibraryPath
        let fullPath = "\(musicBase)/\(file)"
        Task.detached {
            let peaks = await WaveformGenerator.generatePeaks(for: fullPath)
            await MainActor.run { [weak self] in
                guard let self, self.waveformFile == file else { return }
                self.waveformPeaks = peaks
            }
        }
    }

    // MARK: - Favorites

    func toggleFavorite(track: Track) async {
        let newVal = !track.isFavorite
        try? await mpd.setStickerBool(uri: track.file, name: "favorite", value: newVal)
        // Update local state
        await MainActor.run {
            if let albumIdx = albums.firstIndex(where: { $0.tracks.contains(where: { $0.file == track.file }) }),
               let trackIdx = albums[albumIdx].tracks.firstIndex(where: { $0.file == track.file }) {
                albums[albumIdx].tracks[trackIdx].isFavorite = newVal
            }
        }
    }

    func loadFavorites(for album: inout Album) async {
        for i in album.tracks.indices {
            let uri = album.tracks[i].file
            if let val = try? await mpd.getSticker(uri: uri, name: "favorite"), val == "1" {
                album.tracks[i].isFavorite = true
            }
        }
    }

    // MARK: - Aggregated browsing data

    struct ArtistInfo: Identifiable {
        let id: String  // normalized name
        let name: String
        let albumCount: Int
        let trackCount: Int
        let albums: [Album]
    }

    struct ComposerInfo: Identifiable {
        let id: String
        let name: String
        let trackCount: Int
        let genres: [String]
    }

    /// Normalize a name for grouping: lowercase, strip diacritics, fix broken encoding
    private static func normalizeForGrouping(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .precomposedStringWithCanonicalMapping
    }

    var allArtists: [ArtistInfo] {
        var map: [String: (name: String, albums: Set<String>, albumList: [Album], trackCount: Int)] = [:]
        for album in albums {
            let key = Self.normalizeForGrouping(album.artist)
            if map[key] == nil {
                map[key] = (name: album.artist, albums: [], albumList: [], trackCount: 0)
            }
            if !map[key]!.albums.contains(album.id) {
                map[key]!.albums.insert(album.id)
                map[key]!.albumList.append(album)
            }
            map[key]!.trackCount += album.tracks.count
        }
        return map.map { key, info in
            ArtistInfo(id: key, name: info.name, albumCount: info.albums.count,
                       trackCount: info.trackCount, albums: info.albumList)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var allComposers: [ComposerInfo] {
        var map: [String: (name: String, trackCount: Int, genres: Set<String>)] = [:]
        for album in albums {
            for track in album.tracks where !track.composer.isEmpty {
                let key = Self.normalizeForGrouping(track.composer)
                if map[key] == nil {
                    map[key] = (name: track.composer, trackCount: 0, genres: [])
                }
                map[key]!.trackCount += 1
                if !track.genre.isEmpty {
                    map[key]!.genres.insert(track.genre)
                }
            }
        }
        return map.map { key, info in
            ComposerInfo(id: key, name: info.name, trackCount: info.trackCount,
                         genres: info.genres.sorted())
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var allTracks: [Track] {
        albums.flatMap(\.tracks)
    }

    // MARK: - Parsing

    private static func parseTracks(_ pl: [[String: String]]) -> [Track] {
        pl.compactMap { dict in
            guard let pos = dict["Pos"], let posInt = Int(pos) else { return nil }
            return Self.makeTrack(id: pos, pos: posInt, dict: dict)
        }
    }

    private static func makeTrack(id: String, pos: Int, dict: [String: String]) -> Track {
        Track(
            id: id,
            title: dict["Title"] ?? dict["file"] ?? "?",
            artist: dict["Artist"] ?? "",
            albumArtist: dict["AlbumArtist"] ?? "",
            album: dict["Album"] ?? "",
            file: dict["file"] ?? "",
            pos: pos,
            duration: Double(dict["duration"] ?? dict["Time"] ?? "") ?? 0,
            genre: dict["Genre"] ?? "",
            date: dict["Date"] ?? "",
            trackNumber: dict["Track"] ?? "",
            disc: dict["Disc"] ?? "",
            composer: dict["Composer"] ?? "",
            performer: dict["Performer"] ?? "",
            conductor: dict["Conductor"] ?? "",
            label: dict["Label"] ?? "",
            originalDate: dict["OriginalDate"] ?? "",
            musicbrainzTrackId: dict["MUSICBRAINZ_TRACKID"] ?? "",
            musicbrainzAlbumId: dict["MUSICBRAINZ_ALBUMID"] ?? ""
        )
    }

    private static func groupIntoAlbums(_ tracks: [[String: String]]) -> [Album] {
        struct AlbumAccum {
            var artist: String
            var album: String
            var date: String
            var originalDate: String
            var label: String
            var musicbrainzAlbumId: String
            var genres: Set<String>
            var composers: Set<String>
            var tracks: [[String: String]]
        }

        var folderMap: [String: AlbumAccum] = [:]

        for track in tracks {
            guard let file = track["file"] else { continue }
            var folder = (file as NSString).deletingLastPathComponent
            if folder.lowercased().hasSuffix(".cue") {
                folder = (folder as NSString).deletingLastPathComponent
            }
            if folderMap[folder] == nil {
                folderMap[folder] = AlbumAccum(
                    artist: track["AlbumArtist"] ?? track["Artist"] ?? "",
                    album: track["Album"] ?? folder,
                    date: track["Date"] ?? "",
                    originalDate: track["OriginalDate"] ?? "",
                    label: track["Label"] ?? "",
                    musicbrainzAlbumId: track["MUSICBRAINZ_ALBUMID"] ?? "",
                    genres: [],
                    composers: [],
                    tracks: []
                )
            }
            if let genre = track["Genre"], !genre.isEmpty {
                let parsed = Self.parseGenres(genre)
                for g in parsed { folderMap[folder]?.genres.insert(g) }
            }
            if let composer = track["Composer"], !composer.isEmpty {
                folderMap[folder]?.composers.insert(composer)
            }
            folderMap[folder]?.tracks.append(track)
        }

        return folderMap.map { folder, info in
            Album(
                id: folder,
                title: info.album,
                artist: info.artist,
                folder: folder,
                date: info.date,
                originalDate: info.originalDate,
                label: info.label,
                musicbrainzAlbumId: info.musicbrainzAlbumId,
                genres: info.genres.sorted(),
                composers: info.composers.sorted(),
                tracks: info.tracks.enumerated().map { idx, dict in
                    Self.makeTrack(id: "\(folder)-\(idx)", pos: idx, dict: dict)
                }
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Split compound genres like "Rock / Art Rock / Pop Rock" or "Pop Rock, Classic Rock"
    private static func parseGenres(_ raw: String) -> [String] {
        let separators: [String] = [" / ", ", ", "/", ";"]
        var parts = [raw]

        for sep in separators {
            var newParts: [String] = []
            for part in parts {
                if part.contains(sep) {
                    newParts.append(contentsOf: part.components(separatedBy: sep))
                } else {
                    newParts.append(part)
                }
            }
            parts = newParts
        }

        return parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "*")) }
            .filter { !$0.isEmpty }
            .map { genre in
                genre.split(separator: " ")
                    .map { word in
                        let w = String(word)
                        if w.count <= 2 && w.uppercased() == w { return w }
                        return w.prefix(1).uppercased() + w.dropFirst()
                    }
                    .joined(separator: " ")
            }
    }
}
