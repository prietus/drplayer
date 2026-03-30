import SwiftUI

struct SmartPlaylistView: View {
    let vm: PlayerViewModel
    let onPlayFile: (String) -> Void

    @State private var playlists: [SmartPlaylist] = []
    @State private var selectedId: UUID?
    @State private var results: [Track] = []
    @State private var playCounts: [String: Int] = [:]
    @State private var favoriteFiles: Set<String> = []
    @State private var dataLoaded = false

    private var selectedIndex: Int? {
        guard let id = selectedId else { return nil }
        return playlists.firstIndex(where: { $0.id == id })
    }

    var body: some View {
        HSplitView {
            // Left: playlist list
            playlistList
                .frame(minWidth: 180, maxWidth: 220)

            // Right: editor + results
            if let idx = selectedIndex {
                VStack(spacing: 0) {
                    ruleEditor(for: idx)
                    Divider()
                    resultsList
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Select or create a smart playlist")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            playlists = SmartPlaylist.loadAll()
            await loadStickers()
        }
    }

    // MARK: - Playlist List

    private var playlistList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedId) {
                ForEach(playlists) { pl in
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.purple)
                            .font(.caption)
                        Text(pl.name)
                            .lineLimit(1)
                    }
                    .tag(pl.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            playlists.removeAll { $0.id == pl.id }
                            if selectedId == pl.id { selectedId = nil }
                            save()
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedId) { evaluate() }

            Divider()

            Button {
                let pl = SmartPlaylist()
                playlists.append(pl)
                selectedId = pl.id
                save()
            } label: {
                Label("New Playlist", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }

    // MARK: - Rule Editor

    private func ruleEditor(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name
            HStack {
                TextField("Playlist name", text: $playlists[index].name)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                    .onSubmit { save() }

                Spacer()

                // Play all
                if !results.isEmpty {
                    Button {
                        playAll()
                    } label: {
                        Label("Play All (\(results.count))", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // Match mode
            HStack(spacing: 4) {
                Text("Match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $playlists[index].match) {
                    Text("all").tag(SmartMatch.all)
                    Text("any").tag(SmartMatch.any)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .onChange(of: playlists[index].match) { save(); evaluate() }
                Text("of the following rules:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Rules
            ForEach(Array(playlists[index].rules.enumerated()), id: \.element.id) { ruleIdx, rule in
                ruleRow(playlistIndex: index, ruleIndex: ruleIdx)
            }

            // Add rule
            Button {
                playlists[index].rules.append(SmartRule())
                save()
            } label: {
                Label("Add Rule", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.cyan)

            // Limit
            HStack(spacing: 4) {
                Toggle("Limit to", isOn: Binding(
                    get: { playlists[index].limit != nil },
                    set: { playlists[index].limit = $0 ? 50 : nil; save(); evaluate() }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)

                if playlists[index].limit != nil {
                    TextField("", value: $playlists[index].limit, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onSubmit { save(); evaluate() }
                    Text("tracks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    private func ruleRow(playlistIndex: Int, ruleIndex: Int) -> some View {
        HStack(spacing: 6) {
            // Field picker
            Picker("", selection: $playlists[playlistIndex].rules[ruleIndex].field) {
                ForEach(SmartField.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .frame(width: 110)
            .onChange(of: playlists[playlistIndex].rules[ruleIndex].field) { _, newField in
                // Reset operator to first valid one
                let ops = SmartOperator.available(for: newField)
                if !ops.contains(playlists[playlistIndex].rules[ruleIndex].op) {
                    playlists[playlistIndex].rules[ruleIndex].op = ops.first ?? .contains
                }
                save(); evaluate()
            }

            // Operator picker
            let field = playlists[playlistIndex].rules[ruleIndex].field
            let availableOps = SmartOperator.available(for: field)
            Picker("", selection: $playlists[playlistIndex].rules[ruleIndex].op) {
                ForEach(availableOps, id: \.self) { op in
                    Text(op.rawValue).tag(op)
                }
            }
            .frame(width: 120)
            .onChange(of: playlists[playlistIndex].rules[ruleIndex].op) { save(); evaluate() }

            // Value field(s)
            if !field.isBoolean {
                TextField("value", text: $playlists[playlistIndex].rules[ruleIndex].value)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 80)
                    .onSubmit { save(); evaluate() }

                if playlists[playlistIndex].rules[ruleIndex].op == .between {
                    Text("–").foregroundStyle(.secondary)
                    TextField("to", text: $playlists[playlistIndex].rules[ruleIndex].value2)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onSubmit { save(); evaluate() }
                }
            }

            Spacer()

            // Delete rule
            if playlists[playlistIndex].rules.count > 1 {
                Button {
                    playlists[playlistIndex].rules.remove(at: ruleIndex)
                    save(); evaluate()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.caption)
    }

    // MARK: - Results

    private var resultsList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(results.count) tracks matched")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5))

            if results.isEmpty {
                VStack {
                    Spacer()
                    Text("No tracks match these rules")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                // Column headers
                HStack(spacing: 0) {
                    Text("").frame(width: 28)
                    Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Artist").frame(width: 150, alignment: .leading)
                    Text("Album").frame(width: 150, alignment: .leading)
                    Text("Label").frame(width: 100, alignment: .leading)
                    Text("DR").frame(width: 40)
                    Text("Dur.").frame(width: 50, alignment: .trailing)
                }
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
                .padding(.horizontal)
                .padding(.vertical, 4)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { track in
                            HStack(spacing: 0) {
                                Button { onPlayFile(track.file) } label: {
                                    Image(systemName: "play.circle")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 28)

                                Text(track.title)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)

                                Text(track.album)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)

                                Text(track.label)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .frame(width: 100, alignment: .leading)

                                if let dr = track.dr, dr > 0 {
                                    Text("DR\(dr)")
                                        .font(.caption2.bold().monospaced())
                                        .foregroundColor(drColor(dr))
                                        .frame(width: 40)
                                } else {
                                    Text("").frame(width: 40)
                                }

                                if track.duration > 0 {
                                    Text(String(format: "%d:%02d", Int(track.duration) / 60, Int(track.duration) % 60))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 50, alignment: .trailing)
                                } else {
                                    Text("").frame(width: 50)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())

                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func save() {
        SmartPlaylist.saveAll(playlists)
    }

    private func evaluate() {
        guard let idx = selectedIndex else {
            results = []
            return
        }
        results = playlists[idx].evaluate(
            albums: vm.albums,
            playCounts: playCounts,
            favoriteFiles: favoriteFiles
        )
    }

    private func playAll() {
        guard !results.isEmpty else { return }
        Task {
            await vm.enqueueAndPlayAll(files: results.map(\.file))
        }
    }

    private func loadStickers() async {
        playCounts = await vm.loadAllPlayCounts()
        favoriteFiles = await vm.loadAllFavoriteFiles()
        dataLoaded = true
    }

    private func drColor(_ dr: Int) -> Color {
        switch dr {
        case 14...: return .green
        case 10...13: return .yellow
        case 7...9: return .orange
        default: return .red
        }
    }
}
