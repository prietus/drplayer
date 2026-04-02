import Foundation

/// Unified audio sample provider: uses FIFO when available, falls back to file decoding.
final class AudioSampleProvider: @unchecked Sendable {
    static let shared = AudioSampleProvider()

    private var currentFile = ""

    // Interpolation state for file-based mode
    private let lock = NSLock()
    private var lastElapsed: Double = 0
    private var lastUpdateTime: CFAbsoluteTime = 0
    private var isPlaying = false

    private init() {}

    /// Check if FIFO is available (local MPD with fifo output configured)
    var fifoAvailable: Bool {
        let fifoExists = FileManager.default.fileExists(atPath: AppSettings.fifoPath)
        let isLocal = AppSettings.shared.mpdHost == "localhost" || AppSettings.shared.mpdHost == "127.0.0.1"
        return fifoExists && isLocal
    }

    /// Start providing samples. For FIFO mode, starts the reader thread.
    func start(file: String) {
        if fifoAvailable {
            FIFOReader.shared.start()
        } else if !file.isEmpty && file != currentFile {
            currentFile = file
            Task.detached {
                FileAudioReader.shared.prepare(file: file)
            }
        }
    }

    /// Update with current playback state from MPD polling
    func update(file: String, elapsed: Double, playing: Bool = true) {
        if fifoAvailable { return }

        lock.lock()
        lastElapsed = elapsed
        lastUpdateTime = CFAbsoluteTimeGetCurrent()
        isPlaying = playing
        lock.unlock()

        if file != currentFile && !file.isEmpty {
            currentFile = file
            Task.detached {
                FileAudioReader.shared.prepare(file: file)
            }
        }
    }

    /// Get interpolated elapsed time (smooth between polls)
    private var interpolatedElapsed: Double {
        lock.lock()
        defer { lock.unlock() }
        guard isPlaying else { return lastElapsed }
        let timeSinceUpdate = CFAbsoluteTimeGetCurrent() - lastUpdateTime
        return lastElapsed + timeSinceUpdate
    }

    func getSamples() -> [Float] {
        if fifoAvailable {
            return FIFOReader.shared.getSamples()
        }
        // Update file reader with interpolated position on each frame
        FileAudioReader.shared.update(elapsed: interpolatedElapsed)
        return FileAudioReader.shared.getSamples()
    }

    func getAccumulatedSamples() -> [Float] {
        if fifoAvailable {
            return FIFOReader.shared.getAccumulatedSamples()
        }
        FileAudioReader.shared.update(elapsed: interpolatedElapsed)
        return FileAudioReader.shared.getAccumulatedSamples()
    }

    /// Reset state (e.g., when MPD host changes)
    func reset() {
        currentFile = ""
        lock.lock()
        lastElapsed = 0
        lastUpdateTime = 0
        isPlaying = false
        lock.unlock()
        FIFOReader.shared.stop()
        FileAudioReader.shared.clear()
    }
}
