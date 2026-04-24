import Foundation
import CoreAudio
import ServiceManagement
import AppKit
import UserNotifications

class MusicMonitor: ObservableObject {
    @Published var lastTrack: String = ""
    @Published var lastSampleRate: Int = 0
    @Published var lastBits: UInt32 = 0
    @Published var availableDevices: [String] = []

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
            if notificationsEnabled { requestNotificationPermission() }
        }
    }

    @Published var launchAtLogin: Bool = false {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    @Published var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: "deviceName") }
    }

    init() {
        isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
        notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? false
        deviceName = UserDefaults.standard.string(forKey: "deviceName") ?? "D10s"
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshDevices()
        startMonitoring()
        if notificationsEnabled { requestNotificationPermission() }
    }

    func refreshDevices() {
        availableDevices = allOutputDevices().map { $0.name }
    }

    // MARK: - Notification handling

    private func startMonitoring() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleNotification(notification)
        }
    }

    private func handleNotification(_ notification: Notification) {
        guard isEnabled else { return }
        guard let info = notification.userInfo,
              let state = info["Player State"] as? String,
              state == "Playing" else { return }

        let trackName = [info["Name"] as? String, info["Artist"] as? String]
            .compactMap { $0 }.joined(separator: " – ")

        if let sr = info["Sample Rate"] as? Int, sr > 0 {
            applyFormat(sampleRate: sr, trackName: trackName)
        } else {
            queryWithRetry(attempt: 1, trackName: trackName)
        }
    }

    // MARK: - Sample rate query with exponential back-off

    private func queryWithRetry(attempt: Int, trackName: String, maxAttempts: Int = 4) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if let sr = self.querySampleRate(), sr > 0 {
                DispatchQueue.main.async { self.applyFormat(sampleRate: sr, trackName: trackName) }
            } else if attempt < maxAttempts {
                let delay = 0.1 * pow(2.0, Double(attempt - 1))
                Thread.sleep(forTimeInterval: delay)
                DispatchQueue.main.async { self.queryWithRetry(attempt: attempt + 1, trackName: trackName) }
            }
        }
    }

    private func querySampleRate() -> Int? {
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
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let raw = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Int(raw).flatMap { $0 > 0 ? $0 : nil }
    }

    // MARK: - Format switching

    private func applyFormat(sampleRate: Int, trackName: String) {
        guard let device = allOutputDevices().first(where: {
            $0.name.localizedCaseInsensitiveContains(deviceName)
        }) else { return }

        let streams = outputStreams(of: device.id)
        for streamID in streams {
            let available = availablePhysicalFormats(of: streamID)
            guard let match = bestFormat(from: available, sampleRate: Float64(sampleRate),
                                         bitsPerChannel: 24) else { continue }

            if let current = currentPhysicalFormat(of: streamID),
               current.mSampleRate == match.mSampleRate,
               current.mBitsPerChannel == match.mBitsPerChannel {
                lastTrack = trackName
                lastSampleRate = sampleRate
                lastBits = match.mBitsPerChannel
                sendNotification(trackName: trackName, sampleRate: sampleRate, bits: match.mBitsPerChannel)
                return
            }

            if setPhysicalFormat(match, on: streamID) == noErr {
                lastTrack = trackName
                lastSampleRate = sampleRate
                lastBits = match.mBitsPerChannel
                sendNotification(trackName: trackName, sampleRate: sampleRate, bits: match.mBitsPerChannel)
            }
            return
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func sendNotification(trackName: String, sampleRate: Int, bits: UInt32) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = trackName.isEmpty ? "Now Playing" : trackName
        content.body = "\(sampleRate.formatted()) Hz · \(bits)-bit"
        let request = UNNotificationRequest(
            identifier: "track-change",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Launch at Login

    private func applyLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Status may already match — ignore
        }
    }
}
