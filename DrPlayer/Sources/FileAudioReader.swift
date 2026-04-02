import Foundation

/// Reads PCM samples directly from audio files using ffmpeg.
/// Used as fallback when MPD's FIFO is not available (remote MPD).
final class FileAudioReader: @unchecked Sendable {
    static let shared = FileAudioReader()

    private let lock = NSLock()
    private var samples: [Float] = []
    private var accumulatedSamples: [Float] = []
    private let fftSize = 2048

    private var sampleRate: Double = 44100

    // Pre-decoded buffer for fast seeking
    private var decodedBuffer: [Float] = []
    private var decodedFile: String = ""
    private var decoding = false

    private init() {}

    /// Decode the file into memory using ffmpeg for universal format support
    func prepare(file: String) {
        guard !file.isEmpty else { return }
        let fullPath = (AppSettings.shared.resolveFilePath(file) as NSString).resolvingSymlinksInPath

        lock.lock()
        let alreadyLoaded = decodedFile == fullPath && !decodedBuffer.isEmpty
        let isDecoding = decoding
        lock.unlock()
        if alreadyLoaded || isDecoding { return }

        guard FileManager.default.fileExists(atPath: fullPath) else { return }

        lock.lock()
        decoding = true
        lock.unlock()

        // Use ffmpeg to decode any format to raw PCM float mono 44100Hz
        let ffmpegPath = AppSettings.ffmpegPath ?? "/opt/homebrew/bin/ffmpeg"
        let tempFile = NSTemporaryDirectory() + "drplayer_viz.raw"

        // Remove old temp file
        try? FileManager.default.removeItem(atPath: tempFile)

        let args = [
            ffmpegPath, "-y", "-i", fullPath,
            "-ac", "1",           // mono
            "-ar", "44100",       // 44.1kHz
            "-f", "f32le",        // 32-bit float little-endian
            "-acodec", "pcm_f32le",
            tempFile
        ]

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

        guard ret == 0 else {
            lock.lock()
            decoding = false
            lock.unlock()
            return
        }

        var exitStatus: Int32 = 0
        waitpid(pid, &exitStatus, 0)

        guard exitStatus == 0,
              let data = try? Data(contentsOf: URL(fileURLWithPath: tempFile)) else {
            lock.lock()
            decoding = false
            lock.unlock()
            try? FileManager.default.removeItem(atPath: tempFile)
            return
        }

        let floatCount = data.count / MemoryLayout<Float>.size
        var buffer = [Float](repeating: 0, count: floatCount)
        data.withUnsafeBytes { rawBuf in
            let src = rawBuf.bindMemory(to: Float.self)
            for i in 0..<floatCount {
                buffer[i] = src[i]
            }
        }

        lock.lock()
        decodedBuffer = buffer
        decodedFile = fullPath
        sampleRate = 44100
        decoding = false
        lock.unlock()

        try? FileManager.default.removeItem(atPath: tempFile)
    }

    /// Extract samples at the given playback position
    func update(elapsed: Double) {
        lock.lock()
        guard !decodedBuffer.isEmpty else {
            lock.unlock()
            return
        }

        let startSample = Int(elapsed * sampleRate)
        let endSample = min(startSample + fftSize, decodedBuffer.count)

        guard startSample >= 0 && startSample < decodedBuffer.count else {
            samples = []
            accumulatedSamples = []
            lock.unlock()
            return
        }

        let slice = Array(decodedBuffer[startSample..<endSample])
        samples = slice
        accumulatedSamples = slice

        lock.unlock()
    }

    func getSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func getAccumulatedSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return accumulatedSamples
    }

    func clear() {
        lock.lock()
        samples = []
        accumulatedSamples = []
        decodedBuffer = []
        decodedFile = ""
        lock.unlock()
    }
}
