import SwiftUI

/// Popover showing DR comparison data from dr.loudness-war.info
struct DRComparisonPopover: View {
    let artist: String
    let album: String
    let myDR: Int

    @State private var entries: [LoudnessWarEntry] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Rango Dinamico")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Text("Tu version:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("DR\(myDR)")
                        .font(.caption.bold().monospaced())
                        .foregroundColor(drColor(myDR))
                }
            }
            .padding(.bottom, 8)

            if loading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Consultando Loudness War DB...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            } else if entries.isEmpty {
                Text("No se encontraron datos en Loudness War DB para este album")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                // Column headers
                HStack(spacing: 0) {
                    Text("Edicion")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Año")
                        .frame(width: 40, alignment: .center)
                    Text("DR")
                        .frame(width: 35, alignment: .center)
                    Text("Min")
                        .frame(width: 30, alignment: .center)
                    Text("Max")
                        .frame(width: 30, alignment: .center)
                    Text("Codec")
                        .frame(width: 55, alignment: .center)
                    Text("Fuente")
                        .frame(width: 65, alignment: .trailing)
                }
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            entryRow(entry)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            // Footer
            HStack {
                Text("Fuente: dr.loudness-war.info")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .italic()
                Spacer()
                Button {
                    let q = "\(artist) \(album)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "https://dr.loudness-war.info/album/list?artist=\(artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&album=\(album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Abrir en web")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(14)
        .frame(width: 480)
        .task { await loadData() }
    }

    private func entryRow(_ entry: LoudnessWarEntry) -> some View {
        let isMyDR = entry.drAvg == myDR
        let isBetter = entry.drAvg > myDR
        let isWorse = entry.drAvg < myDR

        return Button {
            if let url = URL(string: "https://dr.loudness-war.info/album/view/\(entry.id)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
        HStack(spacing: 0) {
            Text(entry.album)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.year)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .center)

            Text("DR\(entry.drAvg)")
                .font(.caption.bold().monospaced())
                .foregroundColor(drColor(entry.drAvg))
                .frame(width: 35, alignment: .center)

            Text("\(entry.drMin)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .center)

            Text("\(entry.drMax)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .center)

            Text(entry.codec)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .center)

            Text(entry.source)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .background(
            isMyDR ? Color.accentColor.opacity(0.08) :
            isBetter ? Color.green.opacity(0.04) :
            isWorse ? Color.red.opacity(0.04) :
            Color.clear
        )
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }

    private func drColor(_ dr: Int) -> Color {
        switch dr {
        case 14...: return .green
        case 10...13: return .yellow
        case 7...9: return .orange
        default: return .red
        }
    }

    private func loadData() async {
        entries = await LoudnessWarService.search(artist: artist, album: album)
        loading = false
    }
}
