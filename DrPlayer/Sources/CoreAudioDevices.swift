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
    // Extended info
    let maxSampleRate: Double
    let supportedBitDepths: [Int]
    let currentBitDepth: Int
    let currentFormat: String  // e.g. "lpcm 32bit/44100Hz"
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
        let streamInfo = outputStreamInfo(for: id)

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
            uid: uid,
            maxSampleRate: streamInfo.maxRate,
            supportedBitDepths: streamInfo.bitDepths,
            currentBitDepth: streamInfo.currentBitDepth,
            currentFormat: streamInfo.currentFormat
        )
    }

    // MARK: - Stream info

    private static func outputStreamInfo(for id: AudioObjectID) -> (maxRate: Double, bitDepths: [Int], currentBitDepth: Int, currentFormat: String) {
        var streamAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &streamSize) == noErr,
              streamSize > 0 else { return (0, [], 0, "") }

        let streamCount = Int(streamSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        guard AudioObjectGetPropertyData(id, &streamAddr, 0, nil, &streamSize, &streamIDs) == noErr,
              let streamID = streamIDs.first else { return (0, [], 0, "") }

        // Current physical format
        var physFmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyPhysicalFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var physFmt = AudioStreamBasicDescription()
        var physFmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let currentBitDepth: Int
        let currentFormat: String
        if AudioObjectGetPropertyData(streamID, &physFmtAddr, 0, nil, &physFmtSize, &physFmt) == noErr {
            currentBitDepth = Int(physFmt.mBitsPerChannel)
            currentFormat = "\(currentBitDepth)bit / \(formatRate(Double(physFmt.mSampleRate)))"
        } else {
            currentBitDepth = 0
            currentFormat = ""
        }

        // Available physical formats
        var availAddr = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyAvailablePhysicalFormats,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var availSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(streamID, &availAddr, 0, nil, &availSize) == noErr else {
            return (0, [currentBitDepth], currentBitDepth, currentFormat)
        }

        let fmtCount = Int(availSize) / MemoryLayout<AudioStreamRangedDescription>.size
        var fmts = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: fmtCount)
        guard AudioObjectGetPropertyData(streamID, &availAddr, 0, nil, &availSize, &fmts) == noErr else {
            return (0, [currentBitDepth], currentBitDepth, currentFormat)
        }

        let bitDepths = Array(Set(fmts.map { Int($0.mFormat.mBitsPerChannel) })).sorted()
        let maxRate = fmts.map { Double($0.mFormat.mSampleRate) }.max() ?? 0

        return (maxRate, bitDepths, currentBitDepth, currentFormat)
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
        let maxRate = device.maxSampleRate > 0 ? device.maxSampleRate : device.currentSampleRate
        if maxRate >= 705600 { return "DSD512" }
        if maxRate >= 384000 { return "DSD / DXD" }
        if maxRate >= 192000 { return "Hi-Res" }
        if maxRate >= 96000 { return "Hi-Res" }
        if maxRate >= 48000 { return "CD+" }
        return "CD"
    }
}
