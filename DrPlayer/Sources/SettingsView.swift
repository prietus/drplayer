import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            MusicSourcesTab()
                .tabItem {
                    Label("Sources", systemImage: "folder.badge.plus")
                }
            AudioOutputsTab()
                .tabItem {
                    Label("Audio", systemImage: "hifispeaker")
                }
        }
        .frame(width: 560, height: 400)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @State private var musicPath = AppSettings.shared.musicLibraryPath
    @State private var mpdHost = AppSettings.shared.mpdHost
    @State private var mpdPort = String(AppSettings.shared.mpdPort)
    @State private var lastfmKey = AppSettings.shared.lastfmApiKey
    @State private var discogsKey = AppSettings.shared.discogsKey
    @State private var discogsSecret = AppSettings.shared.discogsSecret
    @State private var testResult: TestResult?
    @State private var detectedConf: String?
    @State private var mpdConf: AppSettings.MPDConf?

    private enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section("Music library") {
                HStack {
                    TextField("music_directory", text: $musicPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose...") {
                        chooseFolder()
                    }
                }
                .onChange(of: musicPath) {
                    AppSettings.shared.musicLibraryPath = musicPath
                }
                if let conf = detectedConf {
                    Text("Auto-detected from \(conf)")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("music_directory from mpd.conf")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("MPD Connection") {
                TextField("Host", text: $mpdHost)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: mpdHost) {
                        AppSettings.shared.mpdHost = mpdHost
                    }
                TextField("Port", text: $mpdPort)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: mpdPort) {
                        if let port = Int(mpdPort), port > 0, port <= 65535 {
                            AppSettings.shared.mpdPort = port
                        }
                    }

                HStack {
                    Button("Test connection") {
                        testConnection()
                    }
                    if let result = testResult {
                        switch result {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        case .failure(let msg):
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }

            Section("External APIs") {
                HStack {
                    Text("Last.fm API Key")
                        .frame(width: 120, alignment: .trailing)
                    SecureField("API Key", text: $lastfmKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: lastfmKey) {
                            AppSettings.shared.lastfmApiKey = lastfmKey
                        }
                }
                Text("Get at last.fm/api/account/create — enriches artist data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Divider()

                HStack {
                    Text("Discogs Key")
                        .frame(width: 120, alignment: .trailing)
                    SecureField("Consumer Key", text: $discogsKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: discogsKey) {
                            AppSettings.shared.discogsKey = discogsKey
                        }
                }
                HStack {
                    Text("Discogs Secret")
                        .frame(width: 120, alignment: .trailing)
                    SecureField("Consumer Secret", text: $discogsSecret)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: discogsSecret) {
                            AppSettings.shared.discogsSecret = discogsSecret
                        }
                }
                Text("Get at discogs.com/settings/developers — physical edition data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // MPD Configuration Health Check
            if let conf = mpdConf {
                Section("mpd.conf") {
                    if let path = conf.confPath {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        healthRow("sticker_file",
                                  ok: conf.stickerFile != nil,
                                  detail: conf.stickerFile ?? "missing — preferred versions won't persist")

                        healthRow("follow_outside_symlinks",
                                  ok: conf.followOutsideSymlinks,
                                  detail: conf.followOutsideSymlinks ? "yes" : "no — music sources via symlinks won't work")

                        healthRow("follow_inside_symlinks",
                                  ok: conf.followInsideSymlinks,
                                  detail: conf.followInsideSymlinks ? "yes" : "no — nested symlinks won't resolve")

                        healthRow("replaygain",
                                  ok: conf.replaygain == "off" || conf.replaygain == nil,
                                  detail: conf.replaygain ?? "not set (bitperfect)")

                        healthRow("auto_update",
                                  ok: true,
                                  detail: conf.autoUpdate ? "yes" : "no — run `mpc update` manually after adding music")

                        healthRow("db_file",
                                  ok: conf.dbFile != nil,
                                  detail: conf.dbFile ?? "not set")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            let detected = AppSettings.detectFromMPDConf()
            detectedConf = detected.confPath
            mpdConf = detected
        }
    }

    @ViewBuilder
    private func healthRow(_ key: String, ok: Bool, detail: String) -> some View {
        GridRow {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(ok ? .green : .orange)
            Text(key)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 170, alignment: .leading)
            Text(detail)
                .font(.caption)
                .foregroundColor(ok ? .secondary : .orange)
                .lineLimit(1)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            musicPath = url.path
        }
    }

    private func testConnection() {
        testResult = nil
        let host = mpdHost
        let port = UInt16(mpdPort) ?? 6600
        Task {
            let client = MPDClient(host: host, port: port)
            do {
                let status = try await client.status()
                await MainActor.run {
                    testResult = status["state"] != nil ? .success : .failure("Unexpected response")
                }
            } catch {
                await MainActor.run {
                    testResult = .failure("Could not connect")
                }
            }
        }
    }
}

// MARK: - Music Sources Tab

private struct MusicSourcesTab: View {
    @State private var sources: [AppSettings.MusicSource] = []
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Music sources") {
                if sources.isEmpty {
                    Text("No sources configured in \(AppSettings.shared.musicLibraryPath)")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(sources) { source in
                        sourceRow(source)
                    }
                }
            }

            Section {
                HStack {
                    Button("Add source...") {
                        addSource()
                    }

                    Spacer()

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Text("Sources are linked as symlinks inside MPD's music_directory. Adding or removing sources triggers 'mpd update'.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refreshSources() }
    }

    private func sourceRow(_ source: AppSettings.MusicSource) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .fontWeight(.medium)
                Text(source.target)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(role: .destructive) {
                removeSource(source)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Remove source (only deletes the symlink, not the files)")
        }
    }

    private func addSource() {
        errorMessage = nil
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add source"
        panel.message = "Select a folder with music to link in MPD"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let name = url.lastPathComponent
        do {
            try AppSettings.shared.addMusicSource(name: name, targetPath: url.path)
            triggerMPDUpdate()
            refreshSources()
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func removeSource(_ source: AppSettings.MusicSource) {
        errorMessage = nil
        do {
            try AppSettings.shared.removeMusicSource(name: source.name)
            triggerMPDUpdate()
            refreshSources()
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func refreshSources() {
        sources = AppSettings.shared.listMusicSources()
    }

    private func triggerMPDUpdate() {
        let settings = AppSettings.shared
        let client = MPDClient(host: settings.mpdHost, port: UInt16(settings.mpdPort))
        Task {
            try? await client.command("update")
        }
    }
}

// MARK: - Audio Outputs Tab

private struct AudioOutputsTab: View {
    @State private var outputs: [MPDClient.AudioOutput] = []
    @State private var devices: [AudioDeviceInfo] = []
    @State private var loading = true
    @State private var mpdConf: AppSettings.MPDConf?
    @State private var addError: String?
    @State private var needsRestart = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // System audio devices (CoreAudio)
                Text(String(localized: "Audio devices", defaultValue: "Audio devices"))
                    .font(.headline)

                if devices.isEmpty {
                    Text("No output devices detected")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(devices) { device in
                        deviceCard(device)
                    }
                }

                Divider()

                // MPD outputs
                Text(String(localized: "MPD outputs", defaultValue: "MPD outputs"))
                    .font(.headline)

                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else if let err = loadError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                } else if outputs.isEmpty {
                    Text("No audio outputs found in MPD")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(outputs, id: \.id) { output in
                        outputRow(output)
                    }
                }

                if needsRestart {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Restart MPD to apply changes: `brew services restart mpd`")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.orange.opacity(0.1)))
                }

                if let err = addError {
                    Text(err).font(.caption).foregroundColor(.red)
                }

                Text("Outputs are defined in mpd.conf. From here you can only enable or disable them.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .task {
            devices = CoreAudioDevices.listOutputDevices()
            mpdConf = AppSettings.detectFromMPDConf()
            await loadOutputs()
        }
    }

    // MARK: - CoreAudio Device Card

    private func deviceCard(_ device: AudioDeviceInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Name + transport badge
            HStack(spacing: 8) {
                Image(systemName: deviceIcon(device))
                    .font(.title2)
                    .foregroundColor(transportColor(device.transport))

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.callout.bold())
                    if !device.manufacturer.isEmpty && device.manufacturer != device.name {
                        Text(device.manufacturer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Transport badge
                Text(device.transport)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(transportColor(device.transport).opacity(0.15)))
                    .foregroundColor(transportColor(device.transport))

                // Quality tier
                Text(CoreAudioDevices.qualityTier(device))
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.green.opacity(0.15)))
                    .foregroundColor(.green)
            }

            // Technical details
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                if !device.currentFormat.isEmpty {
                    GridRow {
                        detailLabel("Active")
                        Text(device.currentFormat)
                            .font(.caption.monospaced().bold())
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    detailLabel(String(localized: "Channels", defaultValue: "Channels"))
                    Text("\(device.outputChannels)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !device.supportedBitDepths.isEmpty {
                    GridRow {
                        detailLabel("Bit depth")
                        Text(device.supportedBitDepths.map { "\($0)bit" }.joined(separator: " · "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    detailLabel("Max rate")
                    Text(CoreAudioDevices.formatRate(device.maxSampleRate > 0 ? device.maxSampleRate : device.currentSampleRate))
                        .font(.caption.monospaced().bold())
                        .foregroundColor(.green)
                }
                GridRow {
                    detailLabel(String(localized: "Supported rates", defaultValue: "Supported rates"))
                    Text(device.supportedSampleRates.joined(separator: " · "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.leading, 36)

            // "Add to MPD" button if USB device not yet in mpd.conf
            if device.transport == "USB",
               let conf = mpdConf,
               !conf.outputs.contains(where: { $0.device == device.name || $0.name == device.name }) {
                Button {
                    addDeviceToMPD(device)
                } label: {
                    Label("Add to mpd.conf", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.leading, 36)
            } else if device.transport == "USB",
                      let conf = mpdConf,
                      conf.outputs.contains(where: { $0.device == device.name || $0.name == device.name }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Configured in mpd.conf")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 36)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }

    private func addDeviceToMPD(_ device: AudioDeviceInfo) {
        addError = nil
        do {
            try AppSettings.addAudioOutput(name: device.name, device: device.name)
            mpdConf = AppSettings.detectFromMPDConf()
            needsRestart = true
        } catch {
            addError = error.localizedDescription
        }
    }

    private func detailLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(width: 100, alignment: .trailing)
    }

    private func deviceIcon(_ device: AudioDeviceInfo) -> String {
        switch device.transport {
        case "USB": return "cable.connector"
        case "Built-in": return "laptopcomputer"
        case "Bluetooth", "Bluetooth LE": return "wave.3.right"
        case "HDMI": return "tv"
        case "Thunderbolt": return "bolt.fill"
        default: return "hifispeaker"
        }
    }

    private func transportColor(_ transport: String) -> Color {
        switch transport {
        case "USB": return .blue
        case "Built-in": return .secondary
        case "Bluetooth", "Bluetooth LE": return .cyan
        case "HDMI": return .purple
        case "Thunderbolt": return .orange
        default: return .secondary
        }
    }

    // MARK: - MPD Output Row

    private func outputRow(_ output: MPDClient.AudioOutput) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(output.name)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(output.plugin)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(.quaternary))
                    ForEach(Array(output.attributes.sorted(by: { $0.key < $1.key })), id: \.key) { key, val in
                        Text("\(key): \(val)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if output.attributes["mixer_type"] == "none" || output.attributes.isEmpty {
                        Text("bitperfect")
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                    }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { output.enabled },
                set: { _ in toggleOutput(output.id) }
            ))
            .toggleStyle(.switch)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }

    @State private var loadError: String?

    private func loadOutputs() async {
        let settings = AppSettings.shared
        let client = MPDClient(host: settings.mpdHost, port: UInt16(settings.mpdPort))
        do {
            outputs = try await client.outputs()
        } catch {
            loadError = "Cannot connect to MPD: \(error.localizedDescription)"
        }
        loading = false
    }

    private func toggleOutput(_ id: Int) {
        let settings = AppSettings.shared
        let client = MPDClient(host: settings.mpdHost, port: UInt16(settings.mpdPort))
        Task {
            try? await client.toggleOutput(id)
            await loadOutputs()
        }
    }
}
