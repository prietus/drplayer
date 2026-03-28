import Foundation
import Accelerate

/// Computes DR14 (Dynamic Range) values for audio files using AVFoundation + vDSP.
/// Algorithm follows the Pleasurize Music Foundation DR14 specification:
///   1. Segment audio into 3-second blocks
///   2. Compute RMS and peak for each block
///   3. Select top 20% loudest blocks by RMS
///   4. DR = -20 * log10(meanRMS / secondHighestPeak)
enum DR14Analyzer {

    struct Result {
        let dr: Int
        let peak: Float   // dBFS
        let rms: Float    // dBFS
    }

    private static let cacheDir: String = {
        let dir = NSHomeDirectory() + "/.drplayer/dr14"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let blockDuration: Double = 3.0 // seconds

    // MARK: - Public API

    /// Analyze a single track. Returns nil if the file can't be decoded.
    static func analyze(filePath: String) -> Result? {
        let resolved = (filePath as NSString).resolvingSymlinksInPath
        guard FileManager.default.fileExists(atPath: resolved) else { return nil }

        // Check cache
        if let cached = loadCache(for: resolved) { return cached }

        // Decode to mono f32 PCM via ffmpeg
        guard let (samples, sampleRate) = decodeToFloat(path: resolved) else { return nil }
        guard samples.count > 0, sampleRate > 0 else { return nil }

        let result = computeDR14(samples: samples, sampleRate: sampleRate)

        if let result {
            saveCache(for: resolved, result: result)
        }
        return result
    }

    /// Analyze a track asynchronously on a background queue.
    static func analyze(filePath: String) async -> Result? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = analyze(filePath: filePath)
                continuation.resume(returning: result)
            }
        }
    }

    /// Compute average DR for an album given its track DR values.
    static func albumDR(trackDRs: [Int]) -> Int? {
        let valid = trackDRs.filter { $0 > 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / valid.count
    }

    // MARK: - DR14 Algorithm

    private static func computeDR14(samples: [Float], sampleRate: Int) -> Result? {
        let blockSize = Int(Double(sampleRate) * blockDuration)
        guard blockSize > 0 else { return nil }

        let blockCount = samples.count / blockSize
        guard blockCount >= 1 else { return nil }

        var rmsValues = [Float](repeating: 0, count: blockCount)
        var peakValues = [Float](repeating: 0, count: blockCount)

        for i in 0..<blockCount {
            let offset = i * blockSize
            samples.withUnsafeBufferPointer { buf in
                let ptr = buf.baseAddress! + offset
                let n = vDSP_Length(blockSize)

                // RMS: sqrt(2.0 * sum(x^2) / N) — DR14 spec uses factor of 2
                var sumSq: Float = 0
                vDSP_svesq(ptr, 1, &sumSq, n)
                rmsValues[i] = sqrtf(2.0 * sumSq / Float(blockSize))

                // Peak: max absolute value
                var peak: Float = 0
                vDSP_maxmgv(ptr, 1, &peak, n)
                peakValues[i] = peak
            }
        }

        // Sort blocks by RMS ascending, take top 20%
        let sortedRMS = rmsValues.sorted()
        let top20Count = max(1, blockCount / 5)
        let top20RMS = Array(sortedRMS.suffix(top20Count))
        let meanRMS = top20RMS.reduce(0, +) / Float(top20Count)

        // Second highest peak (per DR14 spec)
        let sortedPeaks = peakValues.sorted()
        let secondPeak: Float
        if sortedPeaks.count >= 2 {
            secondPeak = sortedPeaks[sortedPeaks.count - 2]
        } else {
            secondPeak = sortedPeaks.last ?? 0
        }

        guard meanRMS > 0, secondPeak > 0 else { return nil }

        let drValue = -20.0 * log10f(meanRMS / secondPeak)
        let drInt = max(0, min(99, Int(drValue.rounded())))

        let peakDB = 20.0 * log10f(secondPeak)
        let rmsDB = 20.0 * log10f(meanRMS)

        return Result(dr: drInt, peak: peakDB, rms: rmsDB)
    }

    // MARK: - Audio Decoding via ffmpeg

    /// Decode audio file to mono Float32 PCM at native sample rate.
    /// Returns (samples, sampleRate) or nil on failure.
    private static func decodeToFloat(path: String) -> ([Float], Int)? {
        let tmpFile = NSTemporaryDirectory() + "drplayer_dr14_\(ProcessInfo.processInfo.globallyUniqueString).raw"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        // First, get the sample rate from ffprobe
        guard let sampleRate = probeSampleRate(path: path), sampleRate > 0 else { return nil }

        // Decode to mono f32le at native sample rate
        guard let ffmpeg = AppSettings.ffmpegPath else { return nil }
        let args = [
            ffmpeg,
            "-i", path,
            "-ac", "1",
            "-f", "f32le",
            "-acodec", "pcm_f32le",
            "-ar", String(sampleRate),
            "-v", "quiet",
            "-y", tmpFile
        ]

        guard runProcess(args: args) else { return nil }

        guard let data = FileManager.default.contents(atPath: tmpFile),
              data.count >= 4 else { return nil }

        let floatCount = data.count / MemoryLayout<Float>.size
        var samples = [Float](repeating: 0, count: floatCount)
        _ = samples.withUnsafeMutableBytes { dest in
            data.copyBytes(to: dest)
        }

        return (samples, sampleRate)
    }

    private static func probeSampleRate(path: String) -> Int? {
        let tmpFile = NSTemporaryDirectory() + "drplayer_sr_\(ProcessInfo.processInfo.globallyUniqueString).txt"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        guard let ffprobe = AppSettings.ffprobePath else { return nil }
        let args = [
            ffprobe,
            "-v", "quiet",
            "-select_streams", "a:0",
            "-show_entries", "stream=sample_rate",
            "-of", "default=noprint_wrappers=1:nokey=1",
            path
        ]

        guard runProcessWithOutput(args: args, outputPath: tmpFile) else { return nil }

        guard let data = FileManager.default.contents(atPath: tmpFile),
              let str = String(data: data, encoding: .utf8) else { return nil }

        return Int(str.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Cache

    private static func cacheKey(for path: String) -> String {
        var hash: UInt64 = 5381
        for byte in path.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private static func loadCache(for path: String) -> Result? {
        let key = cacheKey(for: path)
        let cachePath = "\(cacheDir)/\(key).dr14"
        guard let data = FileManager.default.contents(atPath: cachePath),
              let str = String(data: data, encoding: .utf8) else { return nil }
        let parts = str.split(separator: ",")
        guard parts.count == 3,
              let dr = Int(parts[0]),
              let peak = Float(parts[1]),
              let rms = Float(parts[2]) else { return nil }
        return Result(dr: dr, peak: peak, rms: rms)
    }

    private static func saveCache(for path: String, result: Result) {
        let key = cacheKey(for: path)
        let cachePath = "\(cacheDir)/\(key).dr14"
        let str = "\(result.dr),\(result.peak),\(result.rms)"
        try? str.write(toFile: cachePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Process helpers

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

    private static func runProcessWithOutput(args: [String], outputPath: String) -> Bool {
        var cArgs = args.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { free($0) } }

        var pid: pid_t = 0
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, outputPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        let ret = posix_spawn(&pid, args[0], &fileActions, nil, &cArgs, environ)
        guard ret == 0 else { return false }

        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return status == 0
    }
}
