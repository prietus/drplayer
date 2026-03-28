import SwiftUI

struct Album: Identifiable {
    let id: String
    let title: String
    let artist: String
    let folder: String
    let date: String
    let originalDate: String
    let label: String
    let musicbrainzAlbumId: String
    var genres: [String]
    var composers: [String] = []
    var tracks: [Track] = []
    var avgDR: Int? = nil

    var totalDuration: Double {
        tracks.reduce(0) { $0 + $1.duration }
    }

    var formattedDuration: String {
        let total = Int(totalDuration)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(mins)min"
        }
        return "\(mins) min"
    }

    /// Detect format from file extensions in the album
    var format: String {
        let extensions = Set(tracks.map { (($0.file as NSString).pathExtension).uppercased() })
        return extensions.sorted().joined(separator: " / ")
    }

    /// Resolve cover art from the album folder on disk (cached).
    var coverImage: NSImage? {
        if let cached = CoverCache.shared.get(folder) {
            return cached
        }
        let musicBase = AppSettings.shared.musicLibraryPath
        let albumPath = "\(musicBase)/\(folder)"
        let img = Self.findCover(in: albumPath)
        CoverCache.shared.set(folder, image: img)
        return img
    }

    /// All images in the folder + Art/Artwork/Covers/Scans subfolders (for gallery)
    var allArtwork: [String] {
        let musicBase = AppSettings.shared.musicLibraryPath
        let albumPath = ("\(musicBase)/\(folder)" as NSString).resolvingSymlinksInPath
        let fm = FileManager.default
        let imageExtensions = Set(["jpg", "jpeg", "png", "bmp", "tiff", "tif", "webp"])
        var images: [String] = []

        func scanDir(_ dir: String) {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for file in files.sorted() {
                let ext = (file as NSString).pathExtension.lowercased()
                if imageExtensions.contains(ext) {
                    images.append("\(dir)/\(file)")
                }
            }
        }

        // Album root
        scanDir(albumPath)

        // Common artwork subdirectories
        let artDirs = ["Art", "Artwork", "Covers", "Scans", "art", "artwork", "covers", "scans"]
        for dir in artDirs {
            let subPath = "\(albumPath)/\(dir)"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: subPath, isDirectory: &isDir), isDir.boolValue {
                scanDir(subPath)
            }
        }

        // Also check parent if we're in a subfolder (Disc 1/, Stereo/)
        let subfolderPatterns = ["disc", "cd", "stereo", "mono", "surround"]
        let folderName = (albumPath as NSString).lastPathComponent.lowercased()
        if subfolderPatterns.contains(where: { folderName.hasPrefix($0) }) {
            let parentPath = (albumPath as NSString).deletingLastPathComponent
            scanDir(parentPath)
            for dir in artDirs {
                let subPath = "\(parentPath)/\(dir)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: subPath, isDirectory: &isDir), isDir.boolValue {
                    scanDir(subPath)
                }
            }
        }

        return images
    }

    nonisolated static func findCover(in albumPath: String) -> NSImage? {
        let imageExtensions = ["jpg", "jpeg", "png", "bmp", "tiff", "tif", "webp"]
        let preferredNames = ["cover", "folder", "front", "artwork", "cover_for_foobar"]
        let fm = FileManager.default
        // Resolve symlinks for NFS-mounted paths
        let resolved = (albumPath as NSString).resolvingSymlinksInPath

        // Pass 0: try direct file access for common names (faster & more reliable on NFS)
        for name in preferredNames {
            for ext in imageExtensions {
                let path = "\(resolved)/\(name).\(ext)"
                if fm.fileExists(atPath: path) {
                    if let img = NSImage(contentsOfFile: path) { return img }
                }
                // Also try capitalized
                let pathCap = "\(resolved)/\(name.prefix(1).uppercased() + name.dropFirst()).\(ext)"
                if fm.fileExists(atPath: pathCap) {
                    if let img = NSImage(contentsOfFile: pathCap) { return img }
                }
            }
        }

        // Pass 1: list directory and find any image
        let files = (try? fm.contentsOfDirectory(atPath: resolved)) ?? []
        let imageFiles = files.filter { f in
            let ext = (f as NSString).pathExtension.lowercased()
            return Set(imageExtensions).contains(ext)
        }
        if let first = imageFiles.first {
            return NSImage(contentsOfFile: "\(resolved)/\(first)")
        }

        // Pass 3: look in common subdirectories (Art/, Artwork/, Scans/)
        let artDirs = ["Art", "Artwork", "Scans", "Covers", "art", "artwork", "scans", "covers"]
        for dir in artDirs {
            let subPath = "\(resolved)/\(dir)"
            if let subFiles = try? fm.contentsOfDirectory(atPath: subPath) {
                let subImages = subFiles.filter { f in
                    imageExtensions.contains((f as NSString).pathExtension.lowercased())
                }
                // Prefer "front" or "cover" in subfolder
                for name in preferredNames {
                    if let match = subImages.first(where: {
                        ($0 as NSString).deletingPathExtension.lowercased() == name
                    }) {
                        return NSImage(contentsOfFile: "\(subPath)/\(match)")
                    }
                }
                if let first = subImages.first {
                    return NSImage(contentsOfFile: "\(subPath)/\(first)")
                }
            }
        }

        // Pass 4: walk up parent directories (for Disc 01/, Stereo/, Disc 1/Stereo/, etc.)
        let subfolderPatterns = ["disc", "cd", "stereo", "mono", "surround", "side", "disk"]
        var current = resolved
        for _ in 0..<3 { // up to 3 levels
            let folderName = (current as NSString).lastPathComponent.lowercased()
            guard subfolderPatterns.contains(where: { folderName.hasPrefix($0) }) else { break }
            let parentPath = (current as NSString).deletingLastPathComponent
            if let parentFiles = try? fm.contentsOfDirectory(atPath: parentPath) {
                let parentImages = parentFiles.filter { f in
                    imageExtensions.contains((f as NSString).pathExtension.lowercased())
                }
                for name in preferredNames {
                    if let match = parentImages.first(where: {
                        ($0 as NSString).deletingPathExtension.lowercased() == name
                    }) {
                        return NSImage(contentsOfFile: "\(parentPath)/\(match)")
                    }
                }
                if let first = parentImages.first {
                    return NSImage(contentsOfFile: "\(parentPath)/\(first)")
                }
            }
            // Also check Art/Artwork subdirs in parent
            for dir in artDirs {
                let subPath = "\(parentPath)/\(dir)"
                if let subFiles = try? fm.contentsOfDirectory(atPath: subPath) {
                    let subImages = subFiles.filter { f in
                        imageExtensions.contains((f as NSString).pathExtension.lowercased())
                    }
                    if let first = subImages.first {
                        return NSImage(contentsOfFile: "\(subPath)/\(first)")
                    }
                }
            }
            current = parentPath
        }

        return nil
    }
}
