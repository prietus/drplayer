import SwiftUI

struct ProducerListView: View {
    let albums: [Album]
    let onSelectAlbum: (Album) -> Void
    let onPlayFile: (String) -> Void

    @State private var searchText = ""
    @State private var producerMap: [String: [ProducerAlbum]] = [:]
    @State private var loading = true
    @State private var loadedCount = 0
    @State private var selectedProducer: String?
    @State private var roleFilter: String?

    struct ProducerAlbum: Identifiable {
        let id: String
        let album: Album
        let roles: [String]
    }

    /// All unique roles across all producers
    private var allRoles: [String] {
        var roles = Set<String>()
        for (_, albums) in producerMap {
            for pa in albums {
                for role in pa.roles {
                    // Extract base role (before parentheses)
                    let base = role.split(separator: "(").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? role
                    roles.insert(base.lowercased())
                }
            }
        }
        return roles.sorted()
    }

    private var filteredProducers: [(name: String, albums: [ProducerAlbum])] {
        var result = producerMap.map { (name: $0.key, albums: $0.value) }
            .sorted { $0.albums.count > $1.albums.count }

        if let filter = roleFilter {
            result = result.filter { producer in
                producer.albums.contains { pa in
                    pa.roles.contains { $0.lowercased().contains(filter) }
                }
            }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(q) }
        }

        return result
    }

    var body: some View {
        if let producer = selectedProducer {
            ProducerDetailView(
                name: producer,
                producerAlbums: producerMap[producer] ?? [],
                onBack: { selectedProducer = nil },
                onSelectAlbum: onSelectAlbum
            )
        } else {
            producerListBody
        }
    }

    // MARK: - List

    private var producerListBody: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search producers...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                if loading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning \(loadedCount)/\(albums.count)...")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(filteredProducers.count) producers")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Role filter chips
            if !allRoles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        roleChip(nil, label: "All")
                        ForEach(allRoles, id: \.self) { role in
                            roleChip(role, label: role.capitalized)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
            }

            Divider()

            if producerMap.isEmpty && !loading {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No producer data found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Producer credits come from MusicBrainz.\nBrowse albums first to cache metadata.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredProducers, id: \.name) { producer in
                            Button {
                                selectedProducer = producer.name
                            } label: {
                                ProducerRow(name: producer.name, albums: producer.albums)
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .task { await loadProducers() }
    }

    private func roleChip(_ role: String?, label: String) -> some View {
        Button {
            roleFilter = role
        } label: {
            Text(label)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(roleFilter == role ? Color.orange : Color.clear)
                .foregroundStyle(roleFilter == role ? .white : .secondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(roleFilter == role ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private func loadProducers() async {
        loading = true
        var map: [String: [ProducerAlbum]] = [:]
        let productionRoles = ["producer", "executive producer", "mastering", "engineer", "recording", "mix", "balance", "remastered", "remixer"]

        for album in albums {
            let release: MBRelease?
            if !album.musicbrainzAlbumId.isEmpty {
                release = await MusicBrainzService.fetchReleaseFromCache(id: album.musicbrainzAlbumId)
            } else {
                release = await MusicBrainzService.fetchCachedRelease(artist: album.artist, album: album.title)
            }

            guard let release else {
                await MainActor.run { loadedCount += 1 }
                continue
            }

            for credit in release.credits {
                let role = credit.role.lowercased()
                let isProduction = productionRoles.contains { role.contains($0) }
                guard isProduction else { continue }

                let entry = ProducerAlbum(id: album.id, album: album, roles: [credit.role])
                if var existing = map[credit.name] {
                    if let idx = existing.firstIndex(where: { $0.id == album.id }) {
                        existing[idx] = ProducerAlbum(id: album.id, album: album, roles: existing[idx].roles + [credit.role])
                    } else {
                        existing.append(entry)
                    }
                    map[credit.name] = existing
                } else {
                    map[credit.name] = [entry]
                }
            }

            await MainActor.run {
                loadedCount += 1
                producerMap = map
            }
        }

        await MainActor.run { loading = false }
    }
}

// MARK: - Producer Row with Avatar

private struct ProducerRow: View {
    let name: String
    let albums: [ProducerListView.ProducerAlbum]
    @State private var avatar: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
                if let img = avatar {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "person.badge.key.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                let roles = Set(albums.flatMap(\.roles).map { baseRole($0) }).sorted()
                Text("\(albums.count) albums · \(roles.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .task {
            avatar = await ArtistAvatarService.avatar(for: name)
        }
    }

    private func baseRole(_ role: String) -> String {
        let base = role.split(separator: "(").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? role
        return base.lowercased()
    }
}

// MARK: - Producer Detail View

private struct ProducerDetailView: View {
    let name: String
    let producerAlbums: [ProducerListView.ProducerAlbum]
    let onBack: () -> Void
    let onSelectAlbum: (Album) -> Void

    @State private var avatar: NSImage?
    @State private var wikiSummary: WikiSummary?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Producers").font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Header with avatar
                    HStack(alignment: .top, spacing: 16) {
                        Group {
                            if let img = avatar {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.quaternary)
                                    .frame(width: 120, height: 120)
                                    .overlay {
                                        Image(systemName: "person.badge.key.fill")
                                            .font(.system(size: 32))
                                            .foregroundStyle(.orange)
                                    }
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.largeTitle.bold())
                            let roles = Set(producerAlbums.flatMap(\.roles).map { baseRole($0) }).sorted()
                            Text(roles.joined(separator: ", ").capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(producerAlbums.count) albums in library")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            // Bio from Wikipedia
                            if let wiki = wikiSummary, !wiki.extract.isEmpty {
                                Text(wiki.extract)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(6)
                                    .padding(.top, 4)

                                if !wiki.pageURL.isEmpty {
                                    Button {
                                        if let url = URL(string: wiki.pageURL) { NSWorkspace.shared.open(url) }
                                    } label: {
                                        Text("Wikipedia")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else if loading {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini)
                                    Text("Loading bio...").font(.caption2).foregroundStyle(.tertiary)
                                }
                                .padding(.top, 4)
                            }
                        }

                        Spacer()
                    }
                    .padding()

                    Divider().padding(.horizontal)

                    // Albums
                    AlbumGridView(
                        albums: producerAlbums.map(\.album),
                        currentAlbum: "",
                        onSelect: onSelectAlbum,
                        scrollToAlbumId: nil
                    )
                }
            }
        }
        .task { await loadInfo() }
    }

    private func loadInfo() async {
        async let avatarTask = ArtistAvatarService.avatar(for: name)
        async let wikiTask = WikipediaService.searchArtist(name: name)

        avatar = await avatarTask
        wikiSummary = await wikiTask
        loading = false
    }

    private func baseRole(_ role: String) -> String {
        let base = role.split(separator: "(").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? role
        return base.lowercased()
    }
}
