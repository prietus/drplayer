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
                    Label("Fuentes", systemImage: "folder.badge.plus")
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

    private enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section("Biblioteca de musica") {
                HStack {
                    TextField("music_directory", text: $musicPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Elegir...") {
                        chooseFolder()
                    }
                }
                .onChange(of: musicPath) {
                    AppSettings.shared.musicLibraryPath = musicPath
                }
                if let conf = detectedConf {
                    Text("Auto-detectado desde \(conf)")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Directorio music_directory de mpd.conf")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Conexion MPD") {
                TextField("Host", text: $mpdHost)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: mpdHost) {
                        AppSettings.shared.mpdHost = mpdHost
                    }
                TextField("Puerto", text: $mpdPort)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: mpdPort) {
                        if let port = Int(mpdPort), port > 0, port <= 65535 {
                            AppSettings.shared.mpdPort = port
                        }
                    }

                HStack {
                    Button("Probar conexion") {
                        testConnection()
                    }
                    if let result = testResult {
                        switch result {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Conectado")
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

            Section("APIs externas") {
                HStack {
                    Text("Last.fm API Key")
                        .frame(width: 120, alignment: .trailing)
                    SecureField("API Key", text: $lastfmKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: lastfmKey) {
                            AppSettings.shared.lastfmApiKey = lastfmKey
                        }
                }
                Text("Obtener en last.fm/api/account/create — enriquece datos de artistas")
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
                Text("Obtener en discogs.com/settings/developers — datos de ediciones fisicas")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            let detected = AppSettings.detectFromMPDConf()
            detectedConf = detected.confPath
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Seleccionar"
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
                    testResult = status["state"] != nil ? .success : .failure("Respuesta inesperada")
                }
            } catch {
                await MainActor.run {
                    testResult = .failure("No se pudo conectar")
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
            Section("Fuentes de musica") {
                if sources.isEmpty {
                    Text("No hay fuentes configuradas en \(AppSettings.shared.musicLibraryPath)")
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
                    Button("Añadir fuente...") {
                        addSource()
                    }

                    Spacer()

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Text("Las fuentes se enlazan como symlinks dentro del music_directory de MPD. Al añadir o quitar fuentes se ejecuta 'mpd update'.")
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
            .help("Quitar fuente (solo elimina el symlink, no los archivos)")
        }
    }

    private func addSource() {
        errorMessage = nil
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Añadir fuente"
        panel.message = "Selecciona una carpeta con musica para enlazar en MPD"

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
    @State private var loading = true

    var body: some View {
        Form {
            Section("Salidas de audio") {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else if outputs.isEmpty {
                    Text("No se encontraron salidas de audio en MPD")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(outputs, id: \.id) { output in
                        outputRow(output)
                    }
                }
            }

            Section {
                Text("Las salidas se definen en mpd.conf. Desde aqui solo se pueden activar o desactivar.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await loadOutputs()
        }
    }

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
    }

    private func loadOutputs() async {
        let settings = AppSettings.shared
        let client = MPDClient(host: settings.mpdHost, port: UInt16(settings.mpdPort))
        if let outs = try? await client.outputs() {
            outputs = outs
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
