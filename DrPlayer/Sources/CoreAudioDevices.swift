import CoreAudio
import Foundation

struct AudioDeviceInfo: Identifiable {
    let id: AudioObjectID
    let name: String
    let manufacturer: String
    let transport: String
    let outputChannels: Int
    let currentSampleRate: Double
    let supportedSampleRates: [String]
    let uid: String
}

enum CoreAudioDevices {

    /// List all output audio devices with detailed info
    static func listOutputDevices() -> [AudioDeviceInfo] {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize
        ) == noErr else { return [] }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceInfo(for: $0) }
    }

    private static func deviceInfo(for id: AudioObjectID) -> AudioDeviceInfo? {
        // Check output channels first — skip input-only devices
        let channels = outputChannels(for: id)
        guard channels > 0 else { return nil }

        let name = stringProperty(id, selector: kAudioObjectPropertyName)
        let manufacturer = stringProperty(id, selector: kAudioObjectPropertyManufacturer)
        let transport = transportType(for: id)
        let currentRate = nominalSampleRate(for: id)
        let rates = availableSampleRates(for: id)
        let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID)

        // Skip virtual/aggregate devices with only 1 channel (Teams, etc.)
        if transport == "Virtual" && channels <= 1 { return nil }

        return AudioDeviceInfo(
            id: id,
            name: name,
            manufacturer: manufacturer,
            transport: transport,
            outputChannels: channels,
            currentSampleRate: currentRate,
            supportedSampleRates: rates,
            uid: uid
        )
    }

    // MARK: - Property helpers

    private static func stringProperty(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        _ = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
        }
        return value as String
    }

    private static func transportType(for id: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)

        switch transport {
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeBluetooth: return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth LE"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        case kAudioDeviceTransportTypeAggregate: return "Aggregate"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeFireWire: return "FireWire"
        case kAudioDeviceTransportTypePCI: return "PCI"
        default: return "Unknown"
        }
    }

    private static func outputChannels(for id: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size > 0 else { return 0 }

        let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferListPtr.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferListPtr) == noErr else { return 0 }

        return UnsafeMutableAudioBufferListPointer(bufferListPtr).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func nominalSampleRate(for id: AudioObjectID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate)
        return rate
    }

    private static func availableSampleRates(for id: AudioObjectID) -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &ranges) == noErr else { return [] }

        return ranges.map { r in
            if r.mMinimum == r.mMaximum {
                return formatRate(r.mMinimum)
            }
            return "\(formatRate(r.mMinimum))–\(formatRate(r.mMaximum))"
        }
    }

    static func formatRate(_ rate: Double) -> String {
        if rate >= 1000 {
            let khz = rate / 1000.0
            return khz.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(khz)) kHz"
                : String(format: "%.1f kHz", khz)
        }
        return "\(Int(rate)) Hz"
    }

    /// Max supported sample rate for a device
    static func maxRate(for device: AudioDeviceInfo) -> Double {
        // Parse from supportedSampleRates
        return device.currentSampleRate // fallback
    }

    /// Classify device quality tier
    static func qualityTier(_ device: AudioDeviceInfo) -> String {
        let maxRate = device.supportedSampleRates.last.flatMap { str -> Double? in
            // Parse "384 kHz" -> 384000
            let cleaned = str.replacingOccurrences(of: " kHz", with: "")
            if let val = Double(cleaned) { return val * 1000 }
            return nil
        } ?? device.currentSampleRate

        if maxRate >= 384000 { return "Hi-Res (DSD/DXD)" }
        if maxRate >= 192000 { return "Hi-Res" }
        if maxRate >= 96000 { return "Hi-Res" }
        if maxRate >= 48000 { return "CD+" }
        return "CD"
    }
}
