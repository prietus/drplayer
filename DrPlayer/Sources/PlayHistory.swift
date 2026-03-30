import Foundation

/// Append-only local log of every play event with timestamps.
/// Each line: timestamp\tfile\tartist\talbum\ttitle\tduration
enum PlayHistory {
    private static let logPath: String = {
        let dir = NSHomeDirectory() + "/.drplayer"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/play_history.tsv"
    }()

    struct Entry {
        let timestamp: Date
        let file: String
        let artist: String
        let album: String
        let title: String
        let duration: Double
    }

    static func append(file: String, title: String, artist: String, album: String, duration: Double) {
        let ts = Int(Date().timeIntervalSince1970)
        let line = "\(ts)\t\(file)\t\(artist)\t\(album)\t\(title)\t\(Int(duration))\n"
        if let data = line.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }

    static func loadAll() -> [Entry] {
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 6,
                  let ts = Int(parts[0]) else { return nil }
            return Entry(
                timestamp: Date(timeIntervalSince1970: Double(ts)),
                file: String(parts[1]),
                artist: String(parts[2]),
                album: String(parts[3]),
                title: String(parts[4]),
                duration: Double(parts[5]) ?? 0
            )
        }
    }

    static func entries(since date: Date) -> [Entry] {
        loadAll().filter { $0.timestamp >= date }
    }
}
