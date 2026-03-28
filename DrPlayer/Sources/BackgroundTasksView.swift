import SwiftUI

/// Small indicator in transport bar showing background task status
struct BackgroundTasksIndicator: View {
    let vm: PlayerViewModel
    @State private var showPopover = false

    private var hasActivity: Bool {
        vm.genreEnrichRunning
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            ZStack {
                Image(systemName: "gearshape.2")
                    .foregroundColor(hasActivity ? .orange : .primary)
                if hasActivity {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                        .offset(x: 8, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Background tasks")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            BackgroundTasksPopover(vm: vm)
        }
    }
}

/// Popover with details of all background processes
private struct BackgroundTasksPopover: View {
    let vm: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background tasks")
                .font(.headline)

            // Genre enrichment
            taskRow(
                icon: "tag",
                title: "Genre enrichment",
                status: genreStatus,
                isActive: vm.genreEnrichRunning,
                progress: genreProgress
            )

            Divider()

            // DR14 cache
            taskRow(
                icon: "waveform",
                title: "DR14 analysis",
                status: "On demand · \(vm.dr14CacheCount) tracks cached",
                isActive: false,
                progress: nil
            )

            Divider()

            // Waveform cache
            taskRow(
                icon: "waveform.path",
                title: "Waveforms",
                status: "On demand · \(vm.waveformCacheCount) tracks cached",
                isActive: false,
                progress: nil
            )

            Divider()

            // Output polling
            taskRow(
                icon: "hifispeaker",
                title: "Audio outputs",
                status: "\(vm.audioOutputs.count) outputs · polling every 10s",
                isActive: vm.connected,
                progress: nil
            )

            if vm.radioEnabled {
                Divider()
                taskRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Radio",
                    status: "Active · auto-continue when queue ends",
                    isActive: true,
                    progress: nil
                )
            }

            Divider()

            // Cache stats
            VStack(alignment: .leading, spacing: 2) {
                Text("Cache")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("~/.drplayer/genres/ · ~/.drplayer/dr14/ · ~/.drplayer/waveforms/")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var genreStatus: String {
        if vm.genreEnrichRunning {
            let (done, total) = vm.genreEnrichProgress
            return "Processing \(done)/\(total) albums..."
        }
        return "Completed · \(GenreEnricher.cachedCount) albums cached"
    }

    private var genreProgress: Double? {
        guard vm.genreEnrichRunning else { return nil }
        let (done, total) = vm.genreEnrichProgress
        guard total > 0 else { return nil }
        return Double(done) / Double(total)
    }

    private func taskRow(icon: String, title: String, status: String, isActive: Bool, progress: Double?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isActive ? .orange : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.callout.weight(.medium))
                    if isActive {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let progress {
                    ProgressView(value: progress)
                        .tint(.orange)
                }
            }
        }
    }
}
