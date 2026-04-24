import CoreAudio

func allOutputDevices() -> [(id: AudioDeviceID, name: String)] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)

    return ids.compactMap { deviceID in
        var outAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var outSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &outAddr, 0, nil, &outSize) == noErr,
              outSize > 0 else { return nil }

        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameRef: Unmanaged<CFString>? = nil
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, &nameRef)

        let name = nameRef?.takeRetainedValue() as String? ?? ""
        guard !name.isEmpty else { return nil }
        return (id: deviceID, name: name)
    }
}

func outputStreams(of deviceID: AudioDeviceID) -> [AudioStreamID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioStreamID>.size
    var streams = [AudioStreamID](repeating: 0, count: count)
    AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &streams)
    return streams
}

func availablePhysicalFormats(of streamID: AudioStreamID) -> [AudioStreamRangedDescription] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioStreamPropertyAvailablePhysicalFormats,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(streamID, &address, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioStreamRangedDescription>.size
    var formats = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: count)
    AudioObjectGetPropertyData(streamID, &address, 0, nil, &size, &formats)
    return formats
}

func currentPhysicalFormat(of streamID: AudioStreamID) -> AudioStreamBasicDescription? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioStreamPropertyPhysicalFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var desc = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    guard AudioObjectGetPropertyData(streamID, &address, 0, nil, &size, &desc) == noErr else { return nil }
    return desc
}

func setPhysicalFormat(_ desc: AudioStreamBasicDescription, on streamID: AudioStreamID) -> OSStatus {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioStreamPropertyPhysicalFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var mutableDesc = desc
    return AudioObjectSetPropertyData(streamID, &address, 0, nil,
                                      UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &mutableDesc)
}

func bestFormat(
    from ranged: [AudioStreamRangedDescription],
    sampleRate: Float64,
    bitsPerChannel: UInt32
) -> AudioStreamBasicDescription? {
    let candidates = ranged.filter {
        $0.mSampleRateRange.mMinimum <= sampleRate && sampleRate <= $0.mSampleRateRange.mMaximum
    }.map { $0.mFormat }

    if let exact = candidates.first(where: { $0.mBitsPerChannel == bitsPerChannel }) {
        return exact
    }
    return candidates.min(by: {
        abs(Int($0.mBitsPerChannel) - Int(bitsPerChannel)) <
        abs(Int($1.mBitsPerChannel) - Int(bitsPerChannel))
    })
}
