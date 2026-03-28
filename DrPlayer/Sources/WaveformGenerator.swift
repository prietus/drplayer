import Foundation

/// Extracts audio peaks from a file using ffmpeg via posix_spawn.
/// Caches results to disk so each file is only processed once.
enum WaveformGenerator {
    static let barCount = 200

    private static let cacheDir: String = {
        let dir = NSHomeDirectory() + "/.drplayer/waveforms"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func generatePeaks(for filePath: String) async -> [Float] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                let peaks = extractPeaks(filePath: filePath)
                continuation.resume(returning: peaks)
            }
        }
    }

    private static func cacheKey(for path: String) -> String {
        // Use a hash of the resolved path as cache key
        let resolved = (path as NSString).resolvingSymlinksInPath
        var hash: UInt64 = 5381
        for byte in resolved.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private static func loadCache(for path: String) -> [Float]? {
        let key = cacheKey(for: path)
        let cachePath = "\(cacheDir)/\(key).wf"
        guard let data = FileManager.default.contents(atPath: cachePath) else { return nil }
        // Each peak stored as UInt8
        guard data.count == barCount else { return nil }
        return data.map { Float($0) / 255.0 }
    }

    private static func saveCache(for path: String, peaks: [Float]) {
        let key = cacheKey(for: path)
        let cachePath = "\(cacheDir)/\(key).wf"
        let data = Data(peaks.map { UInt8(min(255, max(0, $0 * 255))) })
        try? data.write(to: URL(fileURLWithPath: cachePath))
    }

    private static func extractPeaks(filePath: String) -> [Float] {
        let empty = Array(repeating: Float(0), count: barCount)
        let resolved = (filePath as NSString).resolvingSymlinksInPath
        guard FileManager.default.fileExists(atPath: resolved) else { return empty }

        // Check cache first
        if let cached = loadCache(for: filePath) {
            return cached
        }

        let tmpFile = NSTemporaryDirectory() + "drplayer_wf_\(ProcessInfo.processInfo.globallyUniqueString).raw"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        guard let ffmpeg = AppSettings.ffmpegPath else { return empty }
        let args = [
            ffmpeg,
            "-i", resolved,
            "-ac", "1",
            "-f", "u8",
            "-acodec", "pcm_u8",
            "-ar", "200",
            "-v", "quiet",
            "-y", tmpFile
        ]

        guard runProcess(args: args) else { return empty }

        guard let data = FileManager.default.contents(atPath: tmpFile),
              !data.isEmpty else {
            return empty
        }

        // Downsample to barCount peaks
        let chunkSize = max(1, data.count / barCount)
        var peaks = [Float]()

        for i in 0..<barCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, data.count)
            guard start < data.count else {
                peaks.append(0)
                continue
            }
            var maxVal: Float = 0
            for j in start..<end {
                let sample = abs(Float(data[j]) - 128.0) / 128.0
                if sample > maxVal { maxVal = sample }
            }
            peaks.append(maxVal)
        }

        // Normalize
        let maxPeak = peaks.max() ?? 1.0
        if maxPeak > 0 {
            peaks = peaks.map { $0 / maxPeak }
        }

        // Save to cache
        saveCache(for: filePath, peaks: peaks)

        return peaks
    }

    private static func runProcess(args: [String]) -> Bool {
        var cArgs = args.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { free($0) } }

        var pid: pid_t = 0

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        let ret = posix_spawn(&pid, args[0], &fileActions, nil, &cArgs, environ)
        guard ret == 0 else { return false }

        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return status == 0
    }
}
