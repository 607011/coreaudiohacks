#!/usr/bin/env swift

// music-format-daemon.swift
// Listens for Apple Music track-change notifications and automatically sets
// the physical audio format (sample rate + bit depth) on a CoreAudio output device.
//
// Apple Music broadcasts "com.apple.Music.playerInfo" via DistributedNotificationCenter
// on every state change. The userInfo includes "Sample Rate" for lossless tracks.
//
// Usage:
//   swift music-format-daemon.swift            # watches for device named "D10s"
//   swift music-format-daemon.swift "D10s"     # explicit device name fragment
//
// For persistent background use, compile once and install the LaunchAgent:
//   swiftc -O -o music-format-daemon music-format-daemon.swift
//   launchctl load ~/Library/LaunchAgents/com.user.music-format-daemon.plist

import Foundation
import CoreAudio

// MARK: - CoreAudio helpers (duplicated from sync-format.swift for standalone use)

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

// MARK: - Format switcher

func applyFormat(sampleRate: Int, deviceID: AudioDeviceID, deviceName: String) {
    let desiredRate = Float64(sampleRate)
    let desiredBits: UInt32 = 24  // D10s has no 16-bit physical formats

    let streams = outputStreams(of: deviceID)
    for (i, streamID) in streams.enumerated() {
        let available = availablePhysicalFormats(of: streamID)
        guard let match = bestFormat(from: available, sampleRate: desiredRate, bitsPerChannel: desiredBits) else {
            log("stream \(i): no matching format for \(sampleRate) Hz / \(desiredBits)-bit")
            continue
        }
        if let current = currentPhysicalFormat(of: streamID),
           current.mSampleRate == match.mSampleRate,
           current.mBitsPerChannel == match.mBitsPerChannel {
            log("\(deviceName): already \(sampleRate) Hz / \(match.mBitsPerChannel)-bit")
            return
        }
        let status = setPhysicalFormat(match, on: streamID)
        if status == noErr {
            log("\(deviceName): ✓ \(sampleRate) Hz / \(match.mBitsPerChannel)-bit")
        } else {
            log("\(deviceName): ✗ failed (OSStatus \(status))")
        }
    }
}

// MARK: - Apple Music sample rate via AppleScript (fallback)

func currentTrackSampleRate() -> Int? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", """
        tell application "Music"
            if player state is playing or player state is paused then
                set sr to sample rate of current track
                if sr is missing value then return 0
                return sr
            else
                return 0
            end if
        end tell
        """]
    let out = Pipe(), err = Pipe()
    proc.standardOutput = out
    proc.standardError = err
    do { try proc.run() } catch {
        log("osascript launch failed: \(error)")
        return nil
    }
    proc.waitUntilExit()
    let errOutput = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !errOutput.isEmpty { log("osascript error: \(errOutput)") }
    let raw = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard let value = Int(raw), value > 0 else { return nil }
    return value
}

/// Retries until a non-zero sample rate is returned or all attempts are exhausted.
func currentTrackSampleRateWithRetry(
    attempt: Int = 1,
    maxAttempts: Int = 100,
    trackName: String,
    then completion: @escaping (Int?) -> Void
) {
    var completed = false
    
    func retry(attempt: Int) {
        if completed { return }
        
        if let sr = currentTrackSampleRate() {
            completed = true
            completion(sr)
            return
        }
        guard attempt < maxAttempts else {
            completed = true
            completion(nil)
            return
        }
        let interval = 0.150 * Double(attempt)
        log("Sample rate not yet available for \"\(trackName)\" — retrying in \(String(format: "%.1f", interval))s (attempt \(attempt)/\(maxAttempts))")
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            retry(attempt: attempt + 1)
        }
    }
    
    retry(attempt: attempt)
}

// MARK: - Config (~/.config/music-format-daemon.yaml)

struct Config {
    var device: String = "D10s"

    static func load() -> Config {
        var config = Config()
        let path = (("~/.config/music-format-daemon.yaml" as NSString)
            .expandingTildeInPath)
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return config
        }
        // Parse flat "key: value" YAML — no library needed for this structure
        for line in contents.split(separator: "\n") {
            let trimmed = line.drop(while: { $0 == " " })
            guard !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[trimmed.startIndex..<colon]
                .trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            switch key {
            case "device": config.device = value
            default: break
            }
        }
        return config
    }
}

// MARK: - Logging (stdout, unbuffered — visible in launchctl log and Console.app)

func log(_ message: String) {
    var ts = timeval()
    gettimeofday(&ts, nil)
    let date = Date(timeIntervalSince1970: Double(ts.tv_sec))
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime]
    print("[\(fmt.string(from: date))] \(message)")
    fflush(stdout)
}

// MARK: - Main

let config = Config.load()
// CLI argument overrides config file (useful for testing)
let searchTerm = CommandLine.arguments.dropFirst().first ?? config.device

// Resolve device on each notification in case the DAC was reconnected.
func findDevice() -> (id: AudioDeviceID, name: String)? {
    allOutputDevices().first { $0.name.localizedCaseInsensitiveContains(searchTerm) }
}

if findDevice() == nil {
    fputs("No output device matching \"\(searchTerm)\" found at startup — will retry on next track change.\n", stderr)
    fflush(stderr)
}

log("Watching Apple Music — device: \"\(searchTerm)\"")

DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("com.apple.Music.playerInfo"),
    object: nil,
    queue: .main
) { notification in
    guard let info = notification.userInfo else { return }

    // Only act when playback starts (ignore Paused / Stopped)
    guard let state = info["Player State"] as? String, state == "Playing" else { return }

    if ProcessInfo.processInfo.environment["MUSIC_DAEMON_DEBUG"] != nil {
        log("Notification keys: \(info.keys.map { "\($0)" }.sorted().joined(separator: ", "))")
    }

    let trackName = [info["Name"] as? String, info["Artist"] as? String]
        .compactMap { $0 }.joined(separator: " – ")

    if let sr = info["Sample Rate"] as? Int, sr > 0 {
        // Sample rate came directly from the notification — act immediately
        log("Track: \(trackName.isEmpty ? "(unknown)" : trackName)  |  \(sr) Hz")
        if let device = findDevice() {
            applyFormat(sampleRate: sr, deviceID: device.id, deviceName: device.name)
        }
    } else {
        // Query Apple Music via osascript with exponential back-off
        currentTrackSampleRateWithRetry(trackName: trackName) { sr in
            guard let sampleRate = sr else {
                log("Sample rate unavailable for: \(trackName.isEmpty ? "(unknown)" : trackName)")
                return
            }
            log("Track: \(trackName.isEmpty ? "(unknown)" : trackName)  |  \(sampleRate) Hz")
            guard let device = findDevice() else {
                log("Device \"\(searchTerm)\" not found — is it connected?")
                return
            }
            applyFormat(sampleRate: sampleRate, deviceID: device.id, deviceName: device.name)
        }
    }
}

RunLoop.main.run()
