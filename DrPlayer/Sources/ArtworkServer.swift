import Foundation
import Network

/// Minimal HTTP server on localhost that serves a single file at a time.
/// Used to pass local artwork to OBIScanner via its WebDAV URL scheme.
final class ArtworkServer {
    static let shared = ArtworkServer()

    private var listener: NWListener?
    private var currentFilePath: String?
    private var currentFileName: String?
    private let port: UInt16 = 18923

    private init() {}

    /// Serve a local file and return the OBIScanner scan deep-link URL.
    func serve(filePath: String) -> URL? {
        let fileName = prepare(filePath: filePath)
        var components = URLComponents()
        components.scheme = "obiscanner"
        components.host = "scan"
        components.queryItems = [
            URLQueryItem(name: "server", value: "http://localhost:\(port)"),
            URLQueryItem(name: "path", value: fileName)
        ]
        return components.url
    }

    /// Serve a local file and return the OBIScanner identify deep-link URL.
    /// OBIScanner will call back to drplayer://identify with the discogsId.
    func serveForIdentify(filePath: String, albumFullPath: String) -> URL? {
        let fileName = prepare(filePath: filePath)
        var components = URLComponents()
        components.scheme = "obiscanner"
        components.host = "identify"
        components.queryItems = [
            URLQueryItem(name: "server", value: "http://localhost:\(port)"),
            URLQueryItem(name: "path", value: fileName),
            URLQueryItem(name: "album", value: albumFullPath),
            URLQueryItem(name: "callback", value: "drplayer")
        ]
        return components.url
    }

    private func prepare(filePath: String) -> String {
        let resolved = (filePath as NSString).resolvingSymlinksInPath
        let fileName = (resolved as NSString).lastPathComponent
        currentFilePath = resolved
        currentFileName = fileName
        startIfNeeded()
        return fileName
    }

    private func startIfNeeded() {
        guard listener == nil else { return }

        let params = NWParameters.tcp
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        guard let l = try? NWListener(using: params, on: nwPort) else { return }

        l.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        l.start(queue: .global(qos: .userInitiated))
        listener = l
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        // Read the HTTP request
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let _ = data else {
                connection.cancel()
                return
            }
            self.sendFile(over: connection)
        }
    }

    private func sendFile(over connection: NWConnection) {
        guard let filePath = currentFilePath,
              let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let ext = (filePath as NSString).pathExtension.lowercased()
        let mime: String
        switch ext {
        case "jpg", "jpeg": mime = "image/jpeg"
        case "png": mime = "image/png"
        case "bmp": mime = "image/bmp"
        case "tiff", "tif": mime = "image/tiff"
        case "webp": mime = "image/webp"
        default: mime = "application/octet-stream"
        }

        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nContent-Length: \(fileData.count)\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(fileData)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
