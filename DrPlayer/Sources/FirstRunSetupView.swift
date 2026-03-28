import SwiftUI

struct FirstRunSetupView: View {
    let onComplete: () -> Void

    @State private var musicPath: String
    @State private var mpdHost: String
    @State private var mpdPort: String
    @State private var detectedConf: String?
    @State private var deps: AppSettings.DependencyStatus
    @State private var sources: [AppSettings.MusicSource] = []
    @State private var testResult: TestResult?
    @State private var testing = false
    @State private var confGenerated = false
    @State private var confError: String?

    private enum TestResult {
        case success
        case failure(String)
    }

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let detected = AppSettings.detectFromMPDConf()
        let deps = AppSettings.checkDependencies()
        _musicPath = State(initialValue: detected.musicDir ?? AppSettings.shared.musicLibraryPath)
        _mpdHost = State(initialValue: detected.host ?? AppSettings.shared.mpdHost)
        _mpdPort = State(initialValue: String(detected.port ?? AppSettings.shared.mpdPort))
        _detectedConf = State(initialValue: detected.confPath)
        _deps = State(initialValue: deps)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Configure DrPlayer")
                    .font(.title.bold())
            }
            .padding(.top, 20)
            .padding(.bottom, 12)

            Form {
                // Step 1: Dependencies
                dependenciesSection

                // Step 2: mpd.conf
                if deps.allSatisfied {
                    mpdConfSection
                    connectionSection
                    sourcesSection
                }
            }
            .formStyle(.grouped)

            // Footer
            HStack(spacing: 12) {
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

                Spacer()

                if deps.allSatisfied {
                    Button("Test connection") {
                        testConnection()
                    }
                    .disabled(testing)

                    Button("Start") {
                        saveAndComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(musicPath.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 560, height: 560)
        .onAppear { refreshSources() }
        .onChange(of: musicPath) { refreshSources() }
    }

    // MARK: - Dependencies Section

    private var dependenciesSection: some View {
        Section("1. Prerequisites") {
            depRow("mpd", path: deps.mpd)
            depRow("ffmpeg", path: deps.ffmpeg)
            depRow("ffprobe", path: deps.ffprobe)

            if !deps.allSatisfied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Install missing dependencies with Homebrew:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("brew install \(deps.missing.joined(separator: " "))")
                        .font(.caption.monospaced())
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.8)))
                        .foregroundColor(.green)
                        .textSelection(.enabled)
                    Button("Verify again") {
                        deps = AppSettings.checkDependencies()
                    }
                }
            }
        }
    }

    private func depRow(_ name: String, path: String?) -> some View {
        HStack {
            Image(systemName: path != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(path != nil ? .green : .red)
            Text(name)
                .fontWeight(.medium)
            Spacer()
            if let path {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("not found")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - mpd.conf Section

    private var mpdConfSection: some View {
        Section("2. MPD Configuration") {
            if let conf = detectedConf {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("mpd.conf detected")
                        .fontWeight(.medium)
                    Spacer()
                    Text(conf)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("mpd.conf not found")
                        .fontWeight(.medium)
                }

                HStack {
                    TextField("music_directory", text: $musicPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose...") {
                        chooseFolder()
                    }
                }

                HStack {
                    Button("Generate mpd.conf") {
                        generateConf()
                    }

                    if confGenerated {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Created at ~/.mpd/mpd.conf")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    if let err = confError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Text("Generates a basic bitperfect configuration at ~/.mpd/mpd.conf")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section("3. Connection") {
            HStack {
                TextField("Host", text: $mpdHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                TextField("Port", text: $mpdPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
            }

            if detectedConf != nil {
                HStack {
                    TextField("music_directory", text: $musicPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose...") {
                        chooseFolder()
                    }
                }
            }
        }
    }

    // MARK: - Sources Section

    private var sourcesSection: some View {
        Section("4. Music sources") {
            if sources.isEmpty {
                Text("No sources. You can add them now or later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sources) { source in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(source.name)
                                .font(.callout.weight(.medium))
                            Text(source.target)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                }
            }
            Button("Add source...") {
                addSource()
            }
            Text("Creates symlinks in music_directory pointing to your music folders")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

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

    private func generateConf() {
        confError = nil
        confGenerated = false
        let port = Int(mpdPort) ?? 6600
        do {
            try AppSettings.installMPDConf(musicDir: musicPath, host: mpdHost, port: port)
            confGenerated = true
            // Re-detect
            let detected = AppSettings.detectFromMPDConf()
            detectedConf = detected.confPath
        } catch {
            confError = error.localizedDescription
        }
    }

    private func addSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add source"
        panel.message = "Select a folder with music"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        AppSettings.shared.musicLibraryPath = musicPath
        let name = url.lastPathComponent
        try? AppSettings.shared.addMusicSource(name: name, targetPath: url.path)
        refreshSources()
    }

    private func refreshSources() {
        let savedPath = AppSettings.shared.musicLibraryPath
        AppSettings.shared.musicLibraryPath = musicPath
        sources = AppSettings.shared.listMusicSources()
        AppSettings.shared.musicLibraryPath = savedPath
    }

    private func testConnection() {
        testing = true
        testResult = nil
        let host = mpdHost
        let port = UInt16(mpdPort) ?? 6600
        Task {
            let client = MPDClient(host: host, port: port)
            do {
                let status = try await client.status()
                await MainActor.run {
                    testing = false
                    testResult = status["state"] != nil ? .success : .failure("Unexpected response")
                }
            } catch {
                await MainActor.run {
                    testing = false
                    testResult = .failure("Could not connect")
                }
            }
        }
    }

    private func saveAndComplete() {
        let settings = AppSettings.shared
        settings.musicLibraryPath = musicPath
        settings.mpdHost = mpdHost
        if let port = Int(mpdPort), port > 0, port <= 65535 {
            settings.mpdPort = port
        }
        settings.hasCompletedSetup = true
        onComplete()
    }
}
