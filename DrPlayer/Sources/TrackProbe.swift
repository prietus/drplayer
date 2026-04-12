import Foundation

/// Uses ffprobe to extract detailed metadata from audio files.
enum TrackProbe {
    static func probe(path: String) async -> TrackMetadata {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let meta = runProbe(path: path)
                continuation.resume(returning: meta)
            }
        }
    }

    /// Read only format-level tags from a file via ffprobe (lightweight).
    /// Returns a case-insensitive dictionary of tag key → value.
    static func readFileTags(path: String) async -> [String: String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let tags = runReadTags(path: path)
                continuation.resume(returning: tags)
            }
        }
    }

    private static func runReadTags(path: String) -> [String: String] {
        let resolved = (path as NSString).resolvingSymlinksInPath
        let tmpFile = NSTemporaryDirectory() + "drplayer_tags_\(ProcessInfo.processInfo.globallyUniqueString).json"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        guard let ffprobe = AppSettings.ffprobePath else { return [:] }
        let args = [
            ffprobe,
            "-v", "quiet",
            "-print_format", "json",
            "-show_entries", "format_tags",
            resolved
        ]

        guard runProcess(args: args, outputFile: tmpFile) else { return [:] }

        guard let data = FileManager.default.contents(atPath: tmpFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = json["format"] as? [String: Any],
              let tags = format["tags"] as? [String: String] else {
            return [:]
        }
        // Normalize keys to uppercase for case-insensitive lookup
        var normalized: [String: String] = [:]
        for (key, val) in tags {
            normalized[key.uppercased()] = val
        }
        return normalized
    }

    private static func runProbe(path: String) -> TrackMetadata {
        let resolved = (path as NSString).resolvingSymlinksInPath
        let tmpFile = NSTemporaryDirectory() + "drplayer_probe_\(ProcessInfo.processInfo.globallyUniqueString).json"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        guard let ffprobe = AppSettings.ffprobePath else { return TrackMetadata() }
        let args = [
            ffprobe,
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            resolved
        ]

        guard runProcess(args: args, outputFile: tmpFile) else { return TrackMetadata() }

        guard let data = FileManager.default.contents(atPath: tmpFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TrackMetadata()
        }

        var meta = TrackMetadata()

        // Parse streams
        if let streams = json["streams"] as? [[String: Any]],
           let audio = streams.first(where: { ($0["codec_type"] as? String) == "audio" }) {
            meta.codec = audio["codec_name"] as? String ?? ""
            meta.codecLong = audio["codec_long_name"] as? String ?? ""
            meta.sampleRate = audio["sample_rate"] as? String ?? ""
            meta.channels = audio["channels"] as? Int ?? 0
            meta.channelLayout = audio["channel_layout"] as? String ?? ""
            meta.sampleFormat = audio["sample_fmt"] as? String ?? ""

            if let bps = audio["bits_per_raw_sample"] as? String, bps != "0" {
                meta.bitDepth = bps
            } else if let bps = audio["bits_per_sample"] as? Int, bps > 0 {
                meta.bitDepth = String(bps)
            }

            meta.duration = audio["duration"] as? String ?? ""
        }

        // Parse format
        if let format = json["format"] as? [String: Any] {
            meta.formatName = format["format_long_name"] as? String ?? format["format_name"] as? String ?? ""
            meta.fileSize = format["size"] as? String ?? ""

            if meta.duration.isEmpty {
                meta.duration = format["duration"] as? String ?? ""
            }

            meta.bitrate = format["bit_rate"] as? String ?? ""

            // Tags
            if let tags = format["tags"] as? [String: String] {
                meta.tags = tags
            }
        }

        return meta
    }

    private static func runProcess(args: [String], outputFile: String) -> Bool {
        var cArgs = args.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { free($0) } }

        var pid: pid_t = 0

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)

        // Redirect stdout to output file
        let fd = open(outputFile, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { return false }
        posix_spawn_file_actions_adddup2(&fileActions, fd, STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        defer {
            close(fd)
            posix_spawn_file_actions_destroy(&fileActions)
        }

        let ret = posix_spawn(&pid, args[0], &fileActions, nil, &cArgs, environ)
        guard ret == 0 else { return false }

        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return true
    }
}
