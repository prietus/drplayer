import SwiftUI

/// Maps a remote MPD's top-level library folders (e.g. "dsf", "rips") to
/// folders on this Mac. Internally each mapping is a symlink inside
/// `~/.drplayer/library`, which becomes the music base path, so every
/// MPD-relative path resolves as `<root>/<mpd path>`.
enum LibraryFolders {
    static let root = NSString(string: "~/.drplayer/library").expandingTildeInPath

    struct Folder: Identifiable {
        let name: String     // top-level folder in MPD
        let sample: String   // MPD-relative path of one file inside it
        var id: String { name }
    }

    // MARK: MPD

    /// Top-level folders of the MPD library, each with one sample file.
    static func fetchFolders(host: String, port: UInt16) async -> [Folder]? {
        let client = MPDClient(host: host, port: port)
        guard let lines = try? await client.send("lsinfo"), !lines.isEmpty else { return nil }
        var folders: [Folder] = []
        for dir in lines.compactMap({ value(of: "directory", in: $0) }) {
            if let file = await firstFile(in: dir, client: client, depth: 0) {
                folders.append(Folder(name: dir, sample: file))
            }
        }
        return folders
    }

    private static func firstFile(in dir: String, client: MPDClient, depth: Int) async -> String? {
        guard depth < 6 else { return nil }
        let escaped = dir.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        guard let lines = try? await client.send("lsinfo \"\(escaped)\"") else { return nil }
        if let file = lines.lazy.compactMap({ value(of: "file", in: $0) }).first {
            return file
        }
        for sub in lines.compactMap({ value(of: "directory", in: $0) }).prefix(3) {
            if let file = await firstFile(in: sub, client: client, depth: depth + 1) {
                return file
            }
        }
        return nil
    }

    private static func value(of key: String, in line: String) -> String? {
        let prefix = "\(key): "
        return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
    }

    // MARK: Mappings

    /// Local folder currently mapped to an MPD folder
    static func target(of folder: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: "\(root)/\(folder)")
    }

    static func map(_ folder: String, to localPath: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        let link = "\(root)/\(folder)"
        if (try? fm.destinationOfSymbolicLink(atPath: link)) != nil {
            try fm.removeItem(atPath: link)
        }
        try fm.createSymbolicLink(atPath: link, withDestinationPath: localPath)
    }

    /// Whether `localPath` really is `folder` (its sample file exists there)
    static func matches(_ folder: Folder, localPath: String) -> Bool {
        let rest = folder.sample.dropFirst(folder.name.count + 1)
        let path = ("\(localPath)/\(rest)" as NSString).resolvingSymlinksInPath
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: Detection

    /// Network mounts (NFS, SMB, AFP, WebDAV, autofs) plus /Volumes entries.
    static func candidateRoots() -> [String] {
        var roots: [String] = []
        var stats: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&stats, MNT_NOWAIT)
        let networkTypes: Set<String> = ["nfs", "smbfs", "afpfs", "webdav", "autofs"]
        if let stats {
            for i in 0..<Int(count) {
                var entry = stats[i]
                let type = withUnsafePointer(to: &entry.f_fstypename) {
                    String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
                }
                let mountPoint = withUnsafePointer(to: &entry.f_mntonname) {
                    String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
                }
                if networkTypes.contains(type), mountPoint != "/" {
                    roots.append(mountPoint)
                }
            }
        }
        if let volumes = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") {
            // Skip hidden/system entries and the boot volume (a symlink to /)
            roots += volumes
                .filter { !$0.hasPrefix(".") && !$0.hasPrefix("com.apple.") }
                .map { "/Volumes/\($0)" }
                .filter { (try? FileManager.default.destinationOfSymbolicLink(atPath: $0)) == nil }
        }
        var seen = Set<String>()
        return roots.filter { seen.insert($0).inserted }
    }

    /// Directories to search: candidate roots and up to two levels below
    private static func searchDirs() -> [String] {
        let fm = FileManager.default
        var all: [String] = []
        var level = candidateRoots()
        for _ in 0...2 {
            all += level
            level = level.flatMap { dir -> [String] in
                let children = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
                return children.filter { !$0.hasPrefix(".") }.prefix(40).compactMap { child in
                    let path = "\(dir)/\(child)"
                    var isDir: ObjCBool = false
                    return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue ? path : nil
                }
            }
        }
        return all
    }

    /// Find each folder among network mounts. Prefers a subfolder with the
    /// same name; also accepts a mount that is the folder itself.
    static func detect(_ folders: [Folder]) -> [String: String] {
        guard !folders.isEmpty else { return [:] }
        let dirs = searchDirs()
        var found: [String: String] = [:]
        for folder in folders {
            if let dir = dirs.first(where: { matches(folder, localPath: "\($0)/\(folder.name)") }) {
                found[folder.name] = "\(dir)/\(folder.name)"
            } else if let dir = dirs.first(where: { matches(folder, localPath: $0) }) {
                found[folder.name] = dir
            }
        }
        return found
    }
}

/// Lists the remote MPD's library folders and lets the user pick where
/// each one lives on this Mac. Sets `musicPath` to the internal root.
struct LibraryFoldersView: View {
    @Binding var musicPath: String
    let host: String
    let port: UInt16

    @State private var folders: [LibraryFolders.Folder] = []
    @State private var targets: [String: String] = [:]
    @State private var valid: [String: Bool] = [:]
    @State private var phase: Phase = .loading
    @State private var detectMessage: String?

    private enum Phase: Equatable {
        case loading, ready, detecting
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch phase {
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reading library folders from MPD…").font(.caption).foregroundStyle(.secondary)
                }
            case .failed(let msg):
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    Text(msg).font(.caption).foregroundColor(.red)
                    Spacer()
                    Button("Retry") { Task { await load() } }
                }
            case .ready, .detecting:
                ForEach(folders) { folder in
                    row(folder)
                }
                HStack(spacing: 8) {
                    Button("Detect all") { detectAll() }
                        .disabled(phase == .detecting)
                    if phase == .detecting {
                        ProgressView().controlSize(.small)
                        Text("Searching network mounts…").font(.caption).foregroundStyle(.secondary)
                    } else if let detectMessage {
                        Text(detectMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: "\(host):\(port)") {
            // Debounce while the host is being typed
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private func row(_ folder: LibraryFolders.Folder) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            Text(folder.name)
                .fontWeight(.medium)
                .frame(minWidth: 60, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(targets[folder.name] ?? "Not set")
                .font(.caption)
                .foregroundStyle(targets[folder.name] == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            switch valid[folder.name] {
            case true?:
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    .help("Files found")
            case false?:
                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    .help("This folder doesn't contain the files MPD has in \(folder.name)")
            case nil:
                Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
            }
            Button("Choose…") { choose(folder) }
        }
    }

    private func load() async {
        phase = .loading
        guard AppSettings.isRemoteHost(host) else {
            phase = .failed("Enter the server address first")
            return
        }
        guard let fetched = await LibraryFolders.fetchFolders(host: host, port: port) else {
            phase = .failed("Could not read folders from MPD at \(host)")
            return
        }
        // Carry over folders already reachable through a previous base path
        let previous = musicPath
        if previous != LibraryFolders.root && !previous.isEmpty {
            for folder in fetched where LibraryFolders.target(of: folder.name) == nil {
                let local = ("\(previous)/\(folder.name)" as NSString).resolvingSymlinksInPath
                if LibraryFolders.matches(folder, localPath: local) {
                    try? LibraryFolders.map(folder.name, to: local)
                }
            }
        }
        folders = fetched
        refreshStatus()
        phase = .ready
    }

    private func refreshStatus() {
        var t: [String: String] = [:]
        var v: [String: Bool] = [:]
        for folder in folders {
            if let target = LibraryFolders.target(of: folder.name) {
                t[folder.name] = target
                v[folder.name] = LibraryFolders.matches(folder, localPath: target)
            }
        }
        targets = t
        valid = v
        if !t.isEmpty {
            musicPath = LibraryFolders.root
        }
    }

    private func choose(_ folder: LibraryFolders.Folder) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Where is the “\(folder.name)” library on this Mac?"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? LibraryFolders.map(folder.name, to: url.path)
        detectMessage = nil
        refreshStatus()
    }

    private func detectAll() {
        let pending = folders.filter { valid[$0.name] != true }
        guard !pending.isEmpty else {
            detectMessage = "All folders are already set"
            return
        }
        phase = .detecting
        Task {
            let found = await Task.detached { LibraryFolders.detect(pending) }.value
            for (name, path) in found {
                try? LibraryFolders.map(name, to: path)
            }
            refreshStatus()
            let missing = pending.count - found.count
            detectMessage = missing == 0
                ? "Found \(found.count) of \(pending.count)"
                : "\(missing) not found — mount the share or use Choose…"
            phase = .ready
        }
    }
}
