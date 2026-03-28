import Foundation
import Network

/// Minimal MPD client using Network.framework
class MPDClient {
    private let host: String
    private let port: UInt16

    init(host: String = "localhost", port: UInt16 = 6600) {
        self.host = host
        self.port = port
    }

    /// Send a command to MPD and return the response lines.
    func send(_ command: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            var buffer = Data()

            connection.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    continuation.resume(throwing: err)
                }
            }

            connection.start(queue: .global())

            // Read the MPD greeting, then send command, then read response
            readUntilOK(connection: connection, buffer: &buffer) { _ in
                let msg = "\(command)\n"
                connection.send(
                    content: msg.data(using: .utf8),
                    completion: .contentProcessed { _ in }
                )

                var responseBuffer = Data()
                self.readUntilOK(connection: connection, buffer: &responseBuffer) { lines in
                    connection.cancel()
                    continuation.resume(returning: lines)
                }
            }
        }
    }

    /// Send a command expecting no meaningful response.
    func command(_ cmd: String) async throws {
        _ = try await send(cmd)
    }

    /// Send multiple commands in a command list.
    func commandList(_ cmds: [String]) async throws {
        let full = "command_list_begin\n" + cmds.joined(separator: "\n") + "\ncommand_list_end"
        _ = try await send(full)
    }

    private func readUntilOK(
        connection: NWConnection,
        buffer: inout Data,
        completion: @escaping ([String]) -> Void
    ) {
        let buf = UnsafeMutablePointer<Data>.allocate(capacity: 1)
        buf.initialize(to: buffer)

        func recv() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                guard let data = data else {
                    completion([])
                    buf.deallocate()
                    return
                }
                buf.pointee.append(data)
                if let str = String(data: buf.pointee, encoding: .utf8) {
                    let lines = str.components(separatedBy: "\n")
                    if lines.contains(where: { $0.hasPrefix("OK") || $0.hasPrefix("ACK") }) {
                        let result = lines.filter { !$0.isEmpty && !$0.hasPrefix("OK") && !$0.hasPrefix("ACK") }
                        completion(result)
                        buf.deallocate()
                        return
                    }
                }
                recv()
            }
        }
        recv()
    }
}

// MARK: - Parsed helpers

extension MPDClient {
    func status() async throws -> [String: String] {
        let lines = try await send("status")
        return parseResponse(lines)
    }

    func currentSong() async throws -> [String: String] {
        let lines = try await send("currentsong")
        return parseResponse(lines)
    }

    func playlistInfo() async throws -> [[String: String]] {
        let lines = try await send("playlistinfo")
        return parsePlaylist(lines)
    }

    private func parseResponse(_ lines: [String]) -> [String: String] {
        var dict: [String: String] = [:]
        for line in lines {
            if let idx = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                dict[key] = val
            }
        }
        return dict
    }

    /// Search MPD database (case-insensitive, partial match)
    func search(query: String) async throws -> [[String: String]] {
        let lines = try await send("search any \"\(query)\"")
        return parsePlaylist(lines)
    }

    func listAllInfo() async throws -> [[String: String]] {
        let lines = try await send("listallinfo")
        return parsePlaylist(lines)
    }

    // MARK: - Stickers (favorites)

    func setStickerBool(uri: String, name: String, value: Bool) async throws {
        if value {
            try await command("sticker set song \"\(uri)\" \"\(name)\" \"1\"")
        } else {
            try await command("sticker delete song \"\(uri)\" \"\(name)\"")
        }
    }

    func getSticker(uri: String, name: String) async throws -> String? {
        let lines = try await send("sticker get song \"\(uri)\" \"\(name)\"")
        // Response: "sticker: name=value"
        for line in lines {
            if line.hasPrefix("sticker:") {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    return String(parts[1])
                }
            }
        }
        return nil
    }

    func findSticker(name: String) async throws -> [String: String] {
        // Returns all URIs that have this sticker
        let lines = try await send("sticker find song \"\" \"\(name)\"")
        var result: [String: String] = [:]
        var currentFile = ""
        for line in lines {
            if line.hasPrefix("file:") {
                currentFile = String(line.dropFirst(6))
            } else if line.hasPrefix("sticker:") {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    result[currentFile] = String(parts[1])
                }
            }
        }
        return result
    }

    // MARK: - Audio Outputs

    struct AudioOutput {
        let id: Int
        let name: String
        let plugin: String
        let enabled: Bool
        let attributes: [String: String]
    }

    func outputs() async throws -> [AudioOutput] {
        let lines = try await send("outputs")
        return parseOutputs(lines)
    }

    func enableOutput(_ id: Int) async throws {
        try await command("enableoutput \(id)")
    }

    func disableOutput(_ id: Int) async throws {
        try await command("disableoutput \(id)")
    }

    func toggleOutput(_ id: Int) async throws {
        try await command("toggleoutput \(id)")
    }

    private func parseOutputs(_ lines: [String]) -> [AudioOutput] {
        var results: [AudioOutput] = []
        var currentId: Int?
        var name = ""
        var plugin = ""
        var enabled = false
        var attrs: [String: String] = [:]

        for line in lines {
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "outputid":
                if let prevId = currentId {
                    results.append(AudioOutput(id: prevId, name: name, plugin: plugin, enabled: enabled, attributes: attrs))
                }
                currentId = Int(val)
                name = ""; plugin = ""; enabled = false; attrs = [:]
            case "outputname": name = val
            case "plugin": plugin = val
            case "outputenabled": enabled = val == "1"
            case "attribute":
                let parts = val.split(separator: "=", maxSplits: 1)
                if parts.count == 2 { attrs[String(parts[0])] = String(parts[1]) }
            default: break
            }
        }
        if let prevId = currentId {
            results.append(AudioOutput(id: prevId, name: name, plugin: plugin, enabled: enabled, attributes: attrs))
        }
        return results
    }

    private func parsePlaylist(_ lines: [String]) -> [[String: String]] {
        var tracks: [[String: String]] = []
        var current: [String: String] = [:]
        for line in lines {
            if let idx = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                if key == "file" && !current.isEmpty {
                    tracks.append(current)
                    current = [:]
                }
                current[key] = val
            }
        }
        if !current.isEmpty { tracks.append(current) }
        return tracks
    }
}
