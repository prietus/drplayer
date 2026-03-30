import SwiftUI

struct ProducerListView: View {
    let albums: [Album]
    let onSelectAlbum: (Album) -> Void
    let onPlayFile: (String) -> Void

    @State private var searchText = ""
    @State private var producerMap: [String: [ProducerAlbum]] = [:]  // producer name -> albums
    @State private var loading = true
    @State private var loadedCount = 0
    @State private var selectedProducer: String?

    struct ProducerAlbum: Identifiable {
        let id: String  // album id
        let album: Album
        let roles: [String]  // e.g. ["producer", "mastering"]
    }

    private var filteredProducers: [(name: String, albums: [ProducerAlbum])] {
        var result = producerMap.map { (name: $0.key, albums: $0.value) }
            .sorted { $0.albums.count > $1.albums.count }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(q) }
        }

        return result
    }

    var body: some View {
        if let producer = selectedProducer {
            producerDetail(name: producer)
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
                    Text("Producer credits come from MusicBrainz. Albums need a MusicBrainz ID.")
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
                                HStack(spacing: 12) {
                                    Image(systemName: "person.badge.key.fill")
                                        .font(.title3)
                                        .foregroundStyle(.orange)
                                        .frame(width: 32)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(producer.name)
                                            .font(.callout.weight(.medium))
                                            .foregroundStyle(.primary)
                                        let roles = Set(producer.albums.flatMap(\.roles)).sorted()
                                        Text("\(producer.albums.count) albums · \(roles.joined(separator: ", "))")
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

    // MARK: - Producer Detail

    private func producerDetail(name: String) -> some View {
        let producerAlbums = producerMap[name] ?? []

        return VStack(spacing: 0) {
            HStack {
                Button {
                    selectedProducer = nil
                } label: {
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
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.largeTitle.bold())
                            let roles = Set(producerAlbums.flatMap(\.roles)).sorted()
                            Text(roles.joined(separator: ", ").capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(producerAlbums.count) albums in library")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
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
    }

    // MARK: - Loading

    /// Reads cached MusicBrainz release data that was fetched when visiting album details.
    /// Only albums previously viewed will have cached data.
    private func loadProducers() async {
        loading = true
        var map: [String: [ProducerAlbum]] = [:]
        let productionRoles = ["producer", "executive producer", "mastering", "engineer", "recording", "mix", "balance", "remastered"]

        for album in albums {
            // Try to load from MetadataCache (populated when user views album detail)
            let release: MBRelease?
            if !album.musicbrainzAlbumId.isEmpty {
                release = await MusicBrainzService.fetchReleaseFromCache(id: album.musicbrainzAlbumId)
            } else {
                // Try cached search results
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
