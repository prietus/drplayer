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
    let country: String
    var rating: Int = 0  // 0 = unrated, 1-5 stars
    var dr: Int? = nil
}

@Observable
class PlayerViewModel {
    /// Weak reference for app-level access (mini player, menu commands)
    static weak var current: PlayerViewModel?

    var currentTitle = "---"
    var currentArtist = ""
    var currentAlbum = ""
    var currentFile = ""
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
    var radioEnabled = false
    var radioContext: RadioEngine.SeedContext?

    // Sample rate matching state
    var sampleRateMatched = false
    var matchedSampleRate: Double = 0
    var matchedDeviceName: String = ""

    // Background task progress
    var genreEnrichProgress: (done: Int, total: Int) = (0, 0)
    var genreEnrichRunning = false
    var dr14CacheCount = 0
    var waveformCacheCount = 0

    private var mpd: MPDClient
    private var timer: Timer?
    private var outputPollCounter = 0
    private var lastSampleRate: Double = 0
    private var isSwitchingRate = false

    // Play count tracking
    private var lastCountedFile = ""
    private var playMarked = false
    private var userStopped = false

    /// The album containing the currently playing track
    var currentPlayingAlbum: Album? {
        // Match by file path (most precise)
        if !currentFile.isEmpty,
           let album = albums.first(where: { $0.tracks.contains(where: { $0.file == currentFile }) }) {
            return album
        }
        // Fallback: match by album title + artist
        if let album = albums.first(where: { $0.title == currentAlbum && $0.artist == currentArtist }) {
            return album
        }
        // Fallback: match by album title only
        return albums.first(where: { $0.title == currentAlbum })
    }

    private var dbRebuildObserver: Any?

    init() {
        let settings = AppSettings.shared
        self.mpd = MPDClient(host: settings.mpdHost, port: UInt16(settings.mpdPort))

        dbRebuildObserver = NotificationCenter.default.addObserver(
            forName: .mpdDatabaseRebuilt, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.albums = []
            Task { await self.loadLibrary() }
        }
    }

    func start() {
        // Recreate aggregate devices for DACs with name conflicts
        // (aggregates don't persist across reboots)
        ensureAggregateDevices()

        // Register system Now Playing / media key handlers
        NowPlayingBridge.shared.setup(
            onPlayPause: { [weak self] in Task { await self?.togglePlayPause() } },
            onNext: { [weak self] in Task { await self?.next() } },
            onPrev: { [weak self] in Task { await self?.prev() } },
            onSeek: { [weak self] pos in Task { await self?.seek(to: pos) } }
        )

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
                self.currentFile = song["file"] ?? ""
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

                // Play count: mark as played when >50% listened
                if !currentFile.isEmpty && currentFile != self.lastCountedFile {
                    self.playMarked = false
                    self.lastCountedFile = currentFile
                }
                if !self.playMarked && self.duration > 0 && self.elapsed > self.duration * 0.5 && self.state == "play" {
                    self.playMarked = true
                    let fileToCount = currentFile
                    Task { await self.recordPlay(file: fileToCount) }
                }

                // Trigger waveform generation if song changed
                if !currentFile.isEmpty && currentFile != self.waveformFile {
                    self.waveformFile = currentFile
                    self.waveformPeaks = []
                    self.generateWaveform(for: currentFile)
                }

                // Update audio sample provider for visualizers (file-based fallback)
                AudioSampleProvider.shared.update(file: currentFile, elapsed: self.elapsed, playing: self.state == "play")
            }
            // Sample rate matching: disable output → set DAC rate → re-enable
            let mpdState = status["state"] ?? "stop"
            let currentAudioFmt = status["audio"] ?? ""
            if AppSettings.shared.sampleRateMatchingEnabled && mpdState == "play" && !currentAudioFmt.isEmpty {
                await handleSampleRateMatching(audioFormat: currentAudioFmt)
            } else if mpdState == "stop" {
                await MainActor.run {
                    self.sampleRateMatched = false
                    self.matchedSampleRate = 0
                }
                lastSampleRate = 0
            }

            // Poll outputs every ~10 seconds
            outputPollCounter += 1
            if outputPollCounter % 10 == 1 {
                await refreshOutputs()
            }

            // Auto-continue: when queue ends (not user-stopped), start radio
            if mpdState == "stop" && !playlist.isEmpty && !userStopped {
                if !radioEnabled {
                    radioContext = RadioEngine.contextFromPlaylist(playlist)
                    radioEnabled = true
                }
                await continueRadio()
            }
            if mpdState == "play" {
                userStopped = false
            }

            // Update system Now Playing info
            await updateNowPlaying(state: mpdState)
        } catch {
            await MainActor.run {
                self.connected = false
                self.error = "Sin conexion a MPD"
            }
        }
    }

    func updateDB(path: String) async {
        try? await mpd.command("update \"\(path)\"")
        try? await Task.sleep(for: .seconds(2))
        // Re-fetch updated tracks for this folder
        do {
            let allTracks = try await mpd.listAllInfo()
            let grouped = Self.groupIntoAlbums(allTracks)
            await MainActor.run {
                self.albums = grouped
                self.buildVersionIndex()
            }
        } catch {}
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
                self.buildVersionIndex()
            }

            await loadPreferredStickers()

            // Enrich genres in background (rate-limited, cached)
            Task.detached { [weak self] in
                guard let self else { return }
                await MainActor.run { self.genreEnrichRunning = true }
                let snapshot = await MainActor.run { self.albums }
                await GenreEnricher.enrichAllAlbums(snapshot, update: { albumIdx, newGenres in
                    await MainActor.run {
                        guard albumIdx < self.albums.count else { return }
                        var existing = Set(self.albums[albumIdx].genres.map { $0.lowercased() })
                        for genre in newGenres where existing.insert(genre.lowercased()).inserted {
                            self.albums[albumIdx].genres.append(genre)
                        }
                        self.albums[albumIdx].genres.sort()
                    }
                }, progress: { done, total in
                    await MainActor.run {
                        self.genreEnrichProgress = (done, total)
                    }
                })
                await MainActor.run {
                    self.genreEnrichRunning = false
                    self.dr14CacheCount = (try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/.drplayer/dr14").count) ?? 0
                    self.waveformCacheCount = (try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/.drplayer/waveforms").count) ?? 0
                }
            }
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
        } else if state == "stop" && !playlist.isEmpty {
            userStopped = false
            try? await mpd.command("play")
        } else {
            userStopped = false
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
        userStopped = true
        radioEnabled = false
        radioContext = nil
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

    func seek(to position: Double) async {
        try? await mpd.command("seekcur \(Int(position))")
        await refresh()
    }

    // MARK: - System Now Playing

    private var lastNowPlayingFile = ""

    private func updateNowPlaying(state: String) async {
        guard state != "stop" else {
            NowPlayingBridge.shared.clear()
            lastNowPlayingFile = ""
            return
        }

        // Load cover art only when track changes
        var cover: NSImage? = nil
        if currentFile != lastNowPlayingFile {
            lastNowPlayingFile = currentFile
            if let album = currentPlayingAlbum {
                cover = await album.coverImageAsync()
            }
        }

        let title = await MainActor.run { currentTitle }
        let artist = await MainActor.run { currentArtist }
        let album = await MainActor.run { currentAlbum }
        let dur = await MainActor.run { duration }
        let elap = await MainActor.run { elapsed }
        let playing = state == "play"

        NowPlayingBridge.shared.update(
            title: title,
            artist: artist,
            album: album,
            duration: dur,
            elapsed: elap,
            isPlaying: playing,
            file: currentFile,
            coverImage: cover
        )
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

    // MARK: - Bulk Operations

    func enqueueAndPlayAll(files: [String]) async {
        try? await mpd.command("clear")
        for file in files {
            try? await mpd.command("add \"\(file)\"")
        }
        try? await mpd.command("play")
        await refreshPlaylist()
    }

    func loadAllPlayCounts() async -> [String: Int] {
        guard let counts = try? await mpd.findSticker(name: "play_count") else { return [:] }
        return counts.compactMapValues { Int($0) }
    }

    func loadAllFavoriteFiles() async -> Set<String> {
        guard let favs = try? await mpd.findSticker(name: "favorite") else { return [] }
        return Set(favs.filter { $0.value == "1" }.map(\.key))
    }

    // MARK: - Radio

    /// Start radio mode based on an album's metadata
    func startRadio(from album: Album) async {
        radioContext = RadioEngine.contextFromAlbum(album)
        radioEnabled = true
        // Play the seed album first, then add similar tracks
        try? await mpd.command("clear")
        for track in album.tracks {
            try? await mpd.command("add \"\(track.file)\"")
        }
        try? await mpd.command("play")
        await refreshPlaylist()
        // Add radio tracks after the album
        await generateRadioQueue()
    }

    /// Start radio mode based on current playback
    func startRadioFromCurrent() async {
        if !playlist.isEmpty {
            radioContext = RadioEngine.contextFromPlaylist(playlist)
        } else if let album = albums.first(where: { $0.title == currentAlbum }) {
            radioContext = RadioEngine.contextFromAlbum(album)
        }
        guard radioContext != nil else { return }
        radioEnabled = true
        await generateRadioQueue()
    }

    func stopRadio() {
        radioEnabled = false
        radioContext = nil
    }

    /// Generate and enqueue radio tracks
    private func generateRadioQueue() async {
        guard let context = radioContext else { return }
        let currentFiles = Set(playlist.map(\.file))
        let tracks = RadioEngine.generate(from: context, allAlbums: albums, count: 20, excludeFiles: currentFiles)

        for track in tracks {
            try? await mpd.command("add \"\(track.file)\"")
        }
        try? await mpd.command("play")
        await refreshPlaylist()
    }

    /// Called when radio is enabled and playback stops (queue ended)
    private func continueRadio() async {
        // Keep original seed context — don't update from radio-generated tracks
        // to avoid genre drift (e.g. everything converging to "blues")
        try? await mpd.command("clear")
        await generateRadioQueue()
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

    /// Analyze DR14 for a specific album (on demand, not whole library).
    func scanDR14ForAlbum(albumIdx: Int) async {
        let musicBase = AppSettings.shared.musicLibraryPath
        let album = await MainActor.run { albumIdx < self.albums.count ? self.albums[albumIdx] : nil }
        guard let album else { return }

        // Skip if all tracks already have DR
        guard album.tracks.contains(where: { $0.dr == nil }) else { return }

        var trackDRs: [Int] = []

        for (trackIdx, track) in album.tracks.enumerated() {
            if let dr = track.dr {
                trackDRs.append(dr)
                continue
            }

            let fullPath = "\(musicBase)/\(track.file)"
            if let result = await DR14Analyzer.analyze(filePath: fullPath) {
                trackDRs.append(result.dr)
                let dr = result.dr
                await MainActor.run { [weak self] in
                    guard let self,
                          albumIdx < self.albums.count,
                          trackIdx < self.albums[albumIdx].tracks.count else { return }
                    self.albums[albumIdx].tracks[trackIdx].dr = dr
                }
            }
        }

        if let avgDR = DR14Analyzer.albumDR(trackDRs: trackDRs) {
            await MainActor.run { [weak self] in
                guard let self, albumIdx < self.albums.count else { return }
                self.albums[albumIdx].avgDR = avgDR
            }
        }
    }

    // MARK: - Preferred Versions

    /// Set a track as the preferred version (stores in MPD stickers)
    func setPreferredVersion(file: String, title: String, artist: String) async {
        // Store: sticker "preferred" = normalized title key
        try? await mpd.setStickerBool(uri: file, name: "preferred", value: true)
        // Remove preferred from other versions of the same track
        let key = normalizeTrackTitle(title, artist: artist)
        for album in albums {
            for track in album.tracks {
                let trackKey = normalizeTrackTitle(track.title, artist: track.artist)
                if trackKey == key && track.file != file {
                    try? await mpd.setStickerBool(uri: track.file, name: "preferred", value: false)
                }
            }
        }
    }

    /// Check if a track is marked as preferred
    func isPreferred(file: String) async -> Bool {
        let val = try? await mpd.getSticker(uri: file, name: "preferred")
        return val == "1"
    }

    /// Get the preferred version file for a track title, if any
    func preferredVersion(title: String, artist: String) -> String? {
        let key = normalizeTrackTitle(title, artist: artist)
        for album in albums {
            for track in album.tracks {
                let trackKey = normalizeTrackTitle(track.title, artist: track.artist)
                if trackKey == key {
                    // Check sticker synchronously from cache — for Radio use
                    // We'll load preferred stickers at startup
                    if preferredFiles.contains(track.file) {
                        return track.file
                    }
                }
            }
        }
        return nil
    }

    /// Cached set of files marked as preferred
    var preferredFiles: Set<String> = []

    func loadPreferredStickers() async {
        if let stickers = try? await mpd.findSticker(name: "preferred") {
            await MainActor.run {
                self.preferredFiles = Set(stickers.filter { $0.value == "1" }.map(\.key))
            }
        }
    }

    // MARK: - Version Index

    /// Pre-computed index: normalized title → count of other versions
    private(set) var versionIndex: [String: Int] = [:]

    func buildVersionIndex() {
        var titleIndex: [String: Int] = [:]
        for album in albums {
            for track in album.tracks {
                let key = normalizeTrackTitle(track.title, artist: track.artist)
                titleIndex[key, default: 0] += 1
            }
        }
        // Subtract 1 (the track itself) — only count OTHER versions
        versionIndex = titleIndex.mapValues { max(0, $0 - 1) }
    }

    func versionCount(for track: Track) -> Int {
        let key = normalizeTrackTitle(track.title, artist: track.artist)
        return versionIndex[key] ?? 0
    }

    private func normalizeTrackTitle(_ title: String, artist: String) -> String {
        var cleaned = title.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
        // Remove trailing parens/brackets
        while let range = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        while let range = cleaned.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        if let range = cleaned.range(of: #"\s*-\s*remaster.*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        let artistNorm = artist.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        return "\(artistNorm)|\(cleaned)"
    }

    // MARK: - Aggregate Device Management

    /// Ensure aggregate devices exist for any mpd.conf outputs that need them.
    /// Aggregate devices don't persist across reboots, so we recreate on launch.
    private func ensureAggregateDevices() {
        let conf = AppSettings.detectFromMPDConf()
        for output in conf.outputs {
            guard let device = output.device else { continue }
            // Check if this output uses an aggregate name pattern
            if device.hasSuffix(" (Output)") {
                let originalName = String(device.dropLast(" (Output)".count))
                if CoreAudioDevices.hasNameConflict(originalName) {
                    CoreAudioDevices.createOutputAggregate(forDeviceNamed: originalName)
                }
            }
        }
    }

    // MARK: - Sample Rate Matching
    //
    // When the DAC target is configured, automatically switch the device's
    // sample rate to match the source material. The trick: we must cycle
    // the MPD output (disable → set rate → enable) so MPD reopens the
    // device at the new rate. Without this, the existing audio stream
    // breaks when the hardware rate changes underneath it.

    /// Parse the target device sample rate from MPD's audio format string.
    /// PCM: "44100:24:2" → 44100.0
    /// DSD via DoP: "dsd64:2" → 176400.0 (DSD64 needs 176.4kHz PCM carrier)
    private func parseSampleRate(from fmt: String) -> Double? {
        let parts = fmt.split(separator: ":")
        guard let first = parts.first else { return nil }
        let token = String(first).lowercased()

        // DSD format: "dsd64", "dsd128", "dsd256", "dsd512"
        if token.hasPrefix("dsd"), let multiplier = Int(token.dropFirst(3)) {
            // DoP encodes DSD in PCM frames at base rate 44100 * multiplier/64 * 4
            // DSD64 → 176400, DSD128 → 352800, DSD256 → 705600
            return 44100.0 * Double(multiplier) / 64.0 * 4.0
        }

        // Standard PCM: just the sample rate number
        if let rate = Double(token), rate > 0 {
            return rate
        }
        return nil
    }

    /// Handle sample rate switching when audio format changes between tracks.
    /// Sequence: disable output → set DAC rate → settle → re-enable output.
    /// For DSD: rate is the DoP carrier (e.g. DSD64 → 176400 Hz). MPD with
    /// `dop "yes"` wraps DSD data in DoP PCM frames at this rate.
    private func handleSampleRateMatching(audioFormat fmt: String) async {
        guard !isSwitchingRate else { return }

        let isDSD = fmt.lowercased().hasPrefix("dsd")

        guard let sampleRate = parseSampleRate(from: fmt),
              sampleRate > 0 else { return }

        // No change needed if rate is the same
        guard abs(sampleRate - lastSampleRate) > 1 else {
            await MainActor.run {
                self.sampleRateMatched = true
                self.matchedSampleRate = sampleRate
            }
            return
        }

        let settings = AppSettings.shared
        guard let deviceID = CoreAudioDevices.device(forUID: settings.sampleRateDeviceUID) else { return }

        // Find the MPD output that targets our DAC
        let dacDevice = CoreAudioDevices.listOutputDevices().first { $0.uid == settings.sampleRateDeviceUID }
        let dacName = dacDevice?.name ?? ""

        // Find which MPD output to cycle (match by device name)
        let mpdOutput = await MainActor.run { () -> MPDClient.AudioOutput? in
            audioOutputs.first { $0.name == dacName || $0.attributes["device"] == dacName }
                ?? audioOutputs.first { $0.enabled }
        }
        guard let output = mpdOutput else { return }

        isSwitchingRate = true
        let isFirstTrack = lastSampleRate == 0
        let wasDSD = lastSampleRate > 100000

        print("[SampleRate] \(CoreAudioDevices.formatRate(lastSampleRate)) → \(CoreAudioDevices.formatRate(sampleRate))\(isDSD ? " (DSD/DoP)" : "")")

        // Step 1: Disable output so MPD releases the device
        if !isFirstTrack {
            try? await mpd.command("disableoutput \(output.id)")
            // Wait for MPD to fully release the CoreAudio device
            try? await Task.sleep(for: .milliseconds(500))
        }

        // Step 2: Set DAC to the target rate BEFORE MPD reopens
        // PCM: actual sample rate (44100, 96000, etc.)
        // DSD: DoP carrier rate (176400 for DSD64, 352800 for DSD128, etc.)
        let rateSet = CoreAudioDevices.setDeviceSampleRate(deviceID, sampleRate: sampleRate)
        if !rateSet {
            // Some DACs need a second attempt after the device is fully released
            try? await Task.sleep(for: .milliseconds(500))
            CoreAudioDevices.setDeviceSampleRate(deviceID, sampleRate: sampleRate)
        }

        // Step 3: Wait for DAC to stabilize at new rate, then re-enable output
        if !isFirstTrack {
            // Verify the rate actually changed before reopening
            try? await Task.sleep(for: .milliseconds(500))
            try? await mpd.command("enableoutput \(output.id)")
        }

        lastSampleRate = sampleRate
        isSwitchingRate = false

        await MainActor.run {
            self.sampleRateMatched = true
            self.matchedSampleRate = sampleRate
            self.matchedDeviceName = dacName
        }

        // Refresh outputs to reflect the change
        await refreshOutputs()
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

    // MARK: - Ratings

    func setRating(track: Track, rating: Int) async {
        let clamped = max(0, min(5, rating))
        try? await mpd.setSticker(uri: track.file, name: "rating", value: String(clamped))
        await MainActor.run {
            if let albumIdx = albums.firstIndex(where: { $0.tracks.contains(where: { $0.file == track.file }) }),
               let trackIdx = albums[albumIdx].tracks.firstIndex(where: { $0.file == track.file }) {
                albums[albumIdx].tracks[trackIdx].rating = clamped
            }
        }
    }

    func loadRatings(for album: inout Album) async {
        for i in album.tracks.indices {
            let uri = album.tracks[i].file
            if let val = try? await mpd.getSticker(uri: uri, name: "rating"), let r = Int(val) {
                album.tracks[i].rating = r
            }
        }
    }

    // MARK: - Play Count Tracking

    private func recordPlay(file: String) async {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        try? await mpd.incrementSticker(uri: file, name: "play_count")
        try? await mpd.setSticker(uri: file, name: "last_played", value: timestamp)
        // Append to local history log
        PlayHistory.append(file: file, title: currentTitle, artist: currentArtist, album: currentAlbum, duration: duration)
    }

    struct PlayStats {
        let file: String
        let title: String
        let artist: String
        let album: String
        let playCount: Int
        let lastPlayed: Date?
    }

    func loadPlayStats() async -> [PlayStats] {
        guard let counts = try? await mpd.findSticker(name: "play_count") else { return [] }
        let lastPlayedMap = (try? await mpd.findSticker(name: "last_played")) ?? [:]

        // Build a file→track lookup from loaded albums
        var trackLookup: [String: Track] = [:]
        let albums = await MainActor.run { self.albums }
        for album in albums {
            for track in album.tracks {
                trackLookup[track.file] = track
            }
        }

        var stats: [PlayStats] = []
        for (file, countStr) in counts {
            guard let count = Int(countStr), count > 0 else { continue }
            let track = trackLookup[file]
            let lastPlayed = lastPlayedMap[file].flatMap { Int($0) }.map { Date(timeIntervalSince1970: Double($0)) }
            stats.append(PlayStats(
                file: file,
                title: track?.title ?? (file as NSString).lastPathComponent,
                artist: track?.artist ?? "",
                album: track?.album ?? "",
                playCount: count,
                lastPlayed: lastPlayed
            ))
        }
        return stats.sorted { $0.playCount > $1.playCount }
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

    struct LabelInfo: Identifiable {
        let id: String  // normalized name
        let name: String
        let albumCount: Int
        let trackCount: Int
        let albums: [Album]
    }

    var allLabels: [LabelInfo] {
        var map: [String: (name: String, albums: Set<String>, albumList: [Album], trackCount: Int)] = [:]
        for album in albums {
            let label = album.label.isEmpty ? "Unknown" : album.label
            let key = Self.normalizeForGrouping(label)
            if map[key] == nil {
                map[key] = (name: label, albums: [], albumList: [], trackCount: 0)
            }
            if !map[key]!.albums.contains(album.id) {
                map[key]!.albums.insert(album.id)
                map[key]!.albumList.append(album)
            }
            map[key]!.trackCount += album.tracks.count
        }
        return map.map { key, info in
            LabelInfo(id: key, name: info.name, albumCount: info.albums.count,
                      trackCount: info.trackCount, albums: info.albumList)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
            musicbrainzAlbumId: dict["MUSICBRAINZ_ALBUMID"] ?? "",
            country: dict["RELEASECOUNTRY"] ?? ""
        )
    }

    private static func groupIntoAlbums(_ tracks: [[String: String]]) -> [Album] {
        struct AlbumAccum {
            var artist: String
            var album: String
            var date: String
            var originalDate: String
            var label: String
            var catalogNumber: String
            var country: String
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
                    catalogNumber: track["CATALOGNUMBER"] ?? "",
                    country: track["RELEASECOUNTRY"] ?? "",
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
                catalogNumber: info.catalogNumber,
                country: info.country,
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
