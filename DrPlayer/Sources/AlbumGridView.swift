import SwiftUI

struct AlbumGridView: View {
    let albums: [Album]
    let currentAlbum: String
    let onSelect: (Album) -> Void
    var scrollToAlbumId: String? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(albums, id: \.id) { album in
                        AlbumCell(album: album, isPlaying: album.title == currentAlbum)
                            .onTapGesture { onSelect(album) }
                            .id(album.id)
                    }
                }
                .padding()
            }
            .onChange(of: scrollToAlbumId) { _, id in
                if let id {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onAppear {
                if let id = scrollToAlbumId {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

struct AlbumCell: View {
    let album: Album
    let isPlaying: Bool

    @State private var cover: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let cover {
                    Image(nsImage: cover)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                        }
                }
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .padding(4)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: isPlaying ? 4 : 0)

            Text(album.title)
                .font(.caption.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(album.artist)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .task(id: album.id) {
            let a = album
            let img = await a.coverImageAsync()
            cover = img
        }
        .onAppear {
            if cover == nil, let cached = CoverCache.shared.get(album.folder) {
                cover = cached
            }
        }
    }
}
