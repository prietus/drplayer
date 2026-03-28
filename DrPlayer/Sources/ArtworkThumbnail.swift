import SwiftUI

struct ArtworkThumbnail: View {
    let path: String
    @State private var image: NSImage?
    @State private var showFull = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 2)
                    .onTapGesture { showFull = true }
                    .onHover { h in
                        if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 120, height: 160)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .task(id: path) {
            let p = path
            image = await Task.detached {
                NSImage(contentsOfFile: (p as NSString).resolvingSymlinksInPath)
            }.value
        }
        .popover(isPresented: $showFull) {
            if let image {
                VStack(spacing: 4) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 600, maxHeight: 600)

                    Text((path as NSString).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }
}
