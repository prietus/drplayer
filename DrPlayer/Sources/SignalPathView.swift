import SwiftUI

/// Small dot indicator that shows signal path quality. Click to expand.
struct SignalPathIndicator: View {
    let vm: PlayerViewModel
    @State private var showPopover = false

    private var isBitperfect: Bool {
        guard let output = vm.audioOutputs.first(where: { $0.enabled }) else { return false }
        let mixerNone = output.attributes["mixer_type"] == "none" || output.attributes.isEmpty
        return mixerNone
    }

    private var signalColor: Color {
        guard vm.connected, vm.isPlaying else { return .gray }
        if vm.sampleRateMatched && isBitperfect { return .green }
        return isBitperfect ? .cyan : .purple
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(signalColor.opacity(0.3))
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(signalColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: signalColor.opacity(0.8), radius: 4)
            }
        }
        .buttonStyle(.plain)
        .help(vm.sampleRateMatched && isBitperfect ? "Bitperfect · Rate matched" : isBitperfect ? "Bitperfect" : "Signal path")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            SignalPathPopover(vm: vm, isBitperfect: isBitperfect)
        }
    }
}

/// Popover showing the signal chain from source to output
private struct SignalPathPopover: View {
    let vm: PlayerViewModel
    let isBitperfect: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Signal path")
                    .font(.headline)
                Spacer()
                if vm.sampleRateMatched {
                    Text("Rate Matched")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.green.opacity(0.15)))
                }
                if isBitperfect {
                    Text("Bitperfect")
                        .font(.caption.bold())
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.cyan.opacity(0.15)))
                }
            }
            .padding(.bottom, 12)

            // Signal chain
            VStack(alignment: .leading, spacing: 0) {
                // Source
                signalNode(
                    icon: "doc.richtext",
                    title: "Origin",
                    detail: sourceDescription,
                    color: .cyan
                )

                connector

                // MPD
                signalNode(
                    icon: "server.rack",
                    title: "MPD",
                    detail: mpdDescription,
                    color: .cyan
                )

                // Sample rate matching node
                if vm.sampleRateMatched {
                    connector

                    signalNode(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Rate Match → \(matchedRateLabel)",
                        detail: vm.matchedDeviceName,
                        color: .green
                    )
                }

                connector

                // Output
                if let output = vm.audioOutputs.first(where: { $0.enabled }) {
                    signalNode(
                        icon: "hifispeaker",
                        title: output.name,
                        detail: outputDescription(output),
                        color: .cyan
                    )
                } else {
                    signalNode(
                        icon: "hifispeaker",
                        title: "Output",
                        detail: "No active output",
                        color: .gray
                    )
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Signal chain components

    private func signalNode(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connector: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 13)
            Rectangle()
                .fill(.cyan.opacity(0.3))
                .frame(width: 2, height: 16)
        }
    }

    // MARK: - Descriptions

    private var sourceDescription: String {
        let format = vm.audioFormat
        guard !format.isEmpty else { return "---" }

        let parts = format.split(separator: ":")
        guard parts.count >= 2 else { return format }

        let rate = String(parts[0])

        if rate.hasPrefix("dsd") {
            let channels = parts.count >= 3 ? String(parts[2]) : String(parts[1])
            let ch = channelLabel(channels)
            return "DSD \(rate.dropFirst(3)) \(ch)"
        }

        if let sr = Int(rate) {
            let bits = parts.count >= 3 ? String(parts[1]) : "?"
            let channels = parts.count >= 3 ? String(parts[2]) : String(parts[1])
            let kHz = Double(sr) / 1000.0
            let kHzStr = kHz.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f kHz", kHz)
                : String(format: "%.1f kHz", kHz)
            return "\(kHzStr) / \(bits) bit / \(channelLabel(channels))"
        }

        return format
    }

    private var mpdDescription: String {
        var parts: [String] = []
        if !vm.bitrate.isEmpty && vm.bitrate != "0" {
            parts.append("\(vm.bitrate) kbps")
        }
        parts.append(isBitperfect ? "No processing" : "Active processing")
        return parts.joined(separator: " · ")
    }

    private func outputDescription(_ output: MPDClient.AudioOutput) -> String {
        var parts: [String] = [output.plugin.uppercased()]
        if output.attributes["mixer_type"] == "none" || output.attributes.isEmpty {
            parts.append("no mixer")
        } else if let mixer = output.attributes["mixer_type"] {
            parts.append("mixer: \(mixer)")
        }
        if output.attributes["dop"] == "1" || output.attributes["dop"] == "yes" {
            parts.append("DoP")
        }
        return parts.joined(separator: " · ")
    }

    private var matchedRateLabel: String {
        let fmt = vm.audioFormat.lowercased()
        if fmt.hasPrefix("dsd"),
           let token = fmt.split(separator: ":").first,
           let mult = Int(token.dropFirst(3)) {
            return "DSD\(mult) (DoP)"
        }
        return CoreAudioDevices.formatRate(vm.matchedSampleRate)
    }

    private func channelLabel(_ ch: String) -> String {
        switch ch {
        case "1": return "mono"
        case "2": return "stereo"
        default: return "\(ch) ch"
        }
    }
}
