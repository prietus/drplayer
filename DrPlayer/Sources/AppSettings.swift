import Foundation

@Observable
class AppSettings {
    static let shared = AppSettings()

    var musicLibraryPath: String {
        didSet { UserDefaults.standard.set(musicLibraryPath, forKey: "musicLibraryPath") }
    }
    var mpdHost: String {
        didSet { UserDefaults.standard.set(mpdHost, forKey: "mpdHost") }
    }
    var mpdPort: Int {
        didSet { UserDefaults.standard.set(mpdPort, forKey: "mpdPort") }
    }
    var hasCompletedSetup: Bool {
        didSet { UserDefaults.standard.set(hasCompletedSetup, forKey: "hasCompletedSetup") }
    }
    var lastfmApiKey: String {
        didSet { UserDefaults.standard.set(lastfmApiKey, forKey: "lastfmApiKey") }
    }
    var discogsKey: String {
        didSet { UserDefaults.standard.set(discogsKey, forKey: "discogsKey") }
    }
    var discogsSecret: String {
        didSet { UserDefaults.standard.set(discogsSecret, forKey: "discogsSecret") }
    }

    /// UID of the DAC device for automatic sample rate switching, empty = disabled
    var sampleRateDeviceUID: String {
        didSet { UserDefaults.standard.set(sampleRateDeviceUID, forKey: "sampleRateDeviceUID") }
    }

    /// Whether automatic sample rate matching is enabled
    var sampleRateMatchingEnabled: Bool { !sampleRateDeviceUID.isEmpty }

    /// Standard mpd.conf search paths
    static let mpdConfPaths = [
        NSString(string: "~/.mpd/mpd.conf").expandingTildeInPath,
        NSString(string: "~/.mpdconf").expandingTildeInPath,
        "/etc/mpd.conf",
        "/usr/local/etc/mpd.conf",
        "/opt/homebrew/etc/mpd.conf"
    ]

    private init() {
        let defaults = UserDefaults.standard
        let detected = Self.detectFromMPDConf()

        // Always prefer music_directory from mpd.conf (source of truth for MPD)
        self.musicLibraryPath = detected.musicDir
            ?? defaults.string(forKey: "musicLibraryPath")
            ?? NSString(string: "~/.mpd/music").expandingTildeInPath as String
        self.mpdHost = detected.host
            ?? defaults.string(forKey: "mpdHost")
            ?? "localhost"
        self.mpdPort = detected.port
            ?? { let p = defaults.integer(forKey: "mpdPort"); return p > 0 ? p : nil }()
            ?? 6600
        self.hasCompletedSetup = defaults.bool(forKey: "hasCompletedSetup")
        self.lastfmApiKey = defaults.string(forKey: "lastfmApiKey") ?? ""
        self.discogsKey = defaults.string(forKey: "discogsKey") ?? ""
        self.discogsSecret = defaults.string(forKey: "discogsSecret") ?? ""
        self.sampleRateDeviceUID = defaults.string(forKey: "sampleRateDeviceUID") ?? ""
    }

    /// Resolved, symlink-aware music base path
    var resolvedMusicPath: String {
        (musicLibraryPath as NSString).resolvingSymlinksInPath
    }

    /// Resolve an MPD-relative file path to absolute filesystem path
    func resolveFilePath(_ mpdRelativePath: String) -> String {
        "\(musicLibraryPath)/\(mpdRelativePath)"
    }

    // MARK: - Dependency detection

    /// Known search paths for binaries
    private static let binarySearchPaths = [
        "/opt/homebrew/bin",     // Homebrew Apple Silicon
        "/usr/local/bin",        // Homebrew Intel / manual installs
        "/usr/bin",              // System
        "/bin",
        "/opt/local/bin",        // MacPorts
    ]

    /// Find a binary by name, checking PATH first then known locations
    static func findBinary(_ name: String) -> String? {
        // Check PATH via `which`
        let pipe = Pipe()
        let task = Foundation.Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }

        // Fallback: check known paths
        let fm = FileManager.default
        for dir in binarySearchPaths {
            let path = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Cached paths to ffmpeg and ffprobe
    static let ffmpegPath: String? = findBinary("ffmpeg")
    static let ffprobePath: String? = findBinary("ffprobe")
    static let mpdPath: String? = findBinary("mpd")

    struct DependencyStatus {
        let mpd: String?       // path or nil if missing
        let ffmpeg: String?
        let ffprobe: String?
        let mpdConf: String?   // path to mpd.conf or nil

        var allSatisfied: Bool {
            mpd != nil && ffmpeg != nil && ffprobe != nil
        }

        var missing: [String] {
            var m: [String] = []
            if mpd == nil { m.append("mpd") }
            if ffmpeg == nil { m.append("ffmpeg") }
            if ffprobe == nil { m.append("ffprobe") }
            return m
        }
    }

    static func checkDependencies() -> DependencyStatus {
        let conf = detectFromMPDConf()
        return DependencyStatus(
            mpd: mpdPath,
            ffmpeg: ffmpegPath,
            ffprobe: ffprobePath,
            mpdConf: conf.confPath
        )
    }

    // MARK: - mpd.conf generation

    /// Generate a basic mpd.conf for first-time setup
    static func generateMPDConf(musicDir: String, host: String, port: Int) -> String {
        let home = NSHomeDirectory()
        return """
        music_directory     "\(musicDir)"
        follow_outside_symlinks "yes"
        follow_inside_symlinks  "yes"
        playlist_directory  "\(home)/.mpd/playlists"
        db_file             "\(home)/.mpd/database"
        state_file          "\(home)/.mpd/state"
        sticker_file        "\(home)/.mpd/sticker.sql"
        log_file            "\(home)/.mpd/log"

        bind_to_address     "\(host)"
        port                "\(port)"

        auto_update         "yes"
        replaygain          "off"

        audio_output {
            type            "osx"
            name            "Default Output"
            mixer_type      "none"
        }
        """
    }

    /// Write mpd.conf and create required directories
    static func installMPDConf(musicDir: String, host: String, port: Int) throws {
        let home = NSHomeDirectory()
        let mpdDir = "\(home)/.mpd"
        let fm = FileManager.default

        // Create directories
        try fm.createDirectory(atPath: mpdDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: "\(mpdDir)/playlists", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: musicDir, withIntermediateDirectories: true)

        // Write config
        let conf = generateMPDConf(musicDir: musicDir, host: host, port: port)
        try conf.write(toFile: "\(mpdDir)/mpd.conf", atomically: true, encoding: .utf8)

        // Ignore .cue files — they create duplicate virtual tracks alongside real files
        let mpdignore = "\(musicDir)/.mpdignore"
        if !fm.fileExists(atPath: mpdignore) {
            try "*.cue\n".write(toFile: mpdignore, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - mpd.conf parsing

    struct MPDOutput {
        let name: String
        let type: String
        let device: String?
        let mixerType: String?
    }

    struct MPDConf {
        var musicDir: String?
        var host: String?
        var port: Int?
        var confPath: String?
        var stickerFile: String?
        var followOutsideSymlinks: Bool = false
        var followInsideSymlinks: Bool = false
        var replaygain: String?
        var autoUpdate: Bool = false
        var dbFile: String?
        var outputs: [MPDOutput] = []
    }

    /// Auto-detect settings from mpd.conf
    static func detectFromMPDConf() -> MPDConf {
        for path in mpdConfPaths {
            if let conf = parseMPDConf(at: path) {
                return conf
            }
        }
        return MPDConf()
    }

    static func parseMPDConf(at path: String) -> MPDConf? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }

        var conf = MPDConf(confPath: path)
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }

            if let val = extractValue(line: trimmed, key: "music_directory") {
                conf.musicDir = expandPath(val)
            } else if let val = extractValue(line: trimmed, key: "bind_to_address") {
                conf.host = val
            } else if let val = extractValue(line: trimmed, key: "port") {
                conf.port = Int(val)
            } else if let val = extractValue(line: trimmed, key: "sticker_file") {
                conf.stickerFile = expandPath(val)
            } else if let val = extractValue(line: trimmed, key: "follow_outside_symlinks") {
                conf.followOutsideSymlinks = val.lowercased() == "yes"
            } else if let val = extractValue(line: trimmed, key: "follow_inside_symlinks") {
                conf.followInsideSymlinks = val.lowercased() == "yes"
            } else if let val = extractValue(line: trimmed, key: "replaygain") {
                conf.replaygain = val
            } else if let val = extractValue(line: trimmed, key: "auto_update") {
                conf.autoUpdate = val.lowercased() == "yes"
            } else if let val = extractValue(line: trimmed, key: "db_file") {
                conf.dbFile = expandPath(val)
            }
        }
        // Parse audio_output blocks
        conf.outputs = parseAudioOutputs(content)

        return conf.musicDir != nil ? conf : nil
    }

    /// Parse audio_output { ... } blocks from mpd.conf content
    private static func parseAudioOutputs(_ content: String) -> [MPDOutput] {
        var outputs: [MPDOutput] = []
        let pattern = #"audio_output\s*\{([^}]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return [] }
        let range = NSRange(content.startIndex..., in: content)
        for match in regex.matches(in: content, range: range) {
            guard let blockRange = Range(match.range(at: 1), in: content) else { continue }
            let block = String(content[blockRange])

            var name = "", type = "", device: String?, mixerType: String?
            for line in block.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let val = extractValue(line: trimmed, key: "name") { name = val }
                else if let val = extractValue(line: trimmed, key: "type") { type = val }
                else if let val = extractValue(line: trimmed, key: "device") { device = val }
                else if let val = extractValue(line: trimmed, key: "mixer_type") { mixerType = val }
            }
            if !name.isEmpty {
                outputs.append(MPDOutput(name: name, type: type, device: device, mixerType: mixerType))
            }
        }
        return outputs
    }

    /// Add an audio_output block to mpd.conf for a detected DAC.
    /// If the device name is ambiguous (mic + DAC share the same name),
    /// creates a CoreAudio aggregate device with a unique name.
    /// Returns the actual device name used in mpd.conf.
    @discardableResult
    static func addAudioOutput(name: String, device: String) throws -> String {
        guard let confPath = detectFromMPDConf().confPath else {
            throw NSError(domain: "DrPlayer", code: 1, userInfo: [NSLocalizedDescriptionKey: "mpd.conf not found"])
        }

        // If multiple CoreAudio devices share this name (e.g. mic + DAC),
        // create an aggregate device so MPD picks the right one
        var deviceName = device
        if CoreAudioDevices.hasNameConflict(device) {
            if let agg = CoreAudioDevices.createOutputAggregate(forDeviceNamed: device) {
                deviceName = agg.name
            }
        }

        var content = try String(contentsOfFile: confPath, encoding: .utf8)
        let block = """

        audio_output {
            type            "osx"
            name            "\(deviceName)"
            device          "\(deviceName)"
            mixer_type      "none"
            dop             "yes"
        }
        """
        content += "\n" + block
        try content.write(toFile: confPath, atomically: true, encoding: .utf8)
        return deviceName
    }

    private static func extractValue(line: String, key: String) -> String? {
        guard line.hasPrefix(key) else { return nil }
        let rest = line.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        // Remove surrounding quotes
        if rest.hasPrefix("\"") && rest.hasSuffix("\"") && rest.count >= 2 {
            return String(rest.dropFirst().dropLast())
        }
        return rest
    }

    private static func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return NSString(string: path).expandingTildeInPath as String
        }
        return path
    }

    // MARK: - Music sources (symlinks in music_directory)

    struct MusicSource: Identifiable {
        let id: String  // symlink name
        let name: String
        let target: String  // resolved target path
    }

    /// List current symlink-based sources inside the music directory
    func listMusicSources() -> [MusicSource] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: musicLibraryPath) else { return [] }

        var sources: [MusicSource] = []
        for entry in entries.sorted() {
            let fullPath = "\(musicLibraryPath)/\(entry)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            // Check if it's a symlink
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                let target = (try? fm.destinationOfSymbolicLink(atPath: fullPath)) ?? fullPath
                sources.append(MusicSource(id: entry, name: entry, target: target))
            } else if isDir.boolValue {
                // Regular directory is also a source
                sources.append(MusicSource(id: entry, name: entry, target: fullPath))
            }
        }
        return sources
    }

    /// Add a music source by creating a symlink in the music directory
    func addMusicSource(name: String, targetPath: String) throws {
        let linkPath = "\(musicLibraryPath)/\(name)"
        let fm = FileManager.default

        // Create music directory if needed
        try fm.createDirectory(atPath: musicLibraryPath, withIntermediateDirectories: true)

        // Create symlink
        try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: targetPath)
    }

    /// Remove a music source (symlink only, not the actual data)
    func removeMusicSource(name: String) throws {
        let linkPath = "\(musicLibraryPath)/\(name)"
        let fm = FileManager.default

        // Safety: only remove if it's a symlink
        if let attrs = try? fm.attributesOfItem(atPath: linkPath),
           attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            try fm.removeItem(atPath: linkPath)
        }
    }
}
