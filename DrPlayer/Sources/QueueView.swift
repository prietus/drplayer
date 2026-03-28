import SwiftUI

struct QueueView: View {
    let vm: PlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Cola")
                    .font(.headline)
                Spacer()
                Text("\(vm.playlist.count) pistas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await vm.clearQueue() }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Vaciar cola")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            // Track list
            List {
                ForEach(vm.playlist, id: \.id) { track in
                    HStack(spacing: 8) {
                        if track.pos == vm.currentPos {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                                .frame(width: 16)
                        } else {
                            Text(String(track.pos + 1))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .frame(width: 16)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(.caption)
                                .fontWeight(track.pos == vm.currentPos ? .bold : .regular)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            Task { await vm.removeFromQueue(pos: track.pos) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await vm.playTrack(track.pos) }
                    }
                }
            }
            .listStyle(.plain)
        }
        .background(.ultraThinMaterial.opacity(0.5))
    }
}
