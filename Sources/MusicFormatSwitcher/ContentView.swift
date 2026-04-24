import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: MusicMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            deviceSection
            Divider()
            statusSection
            Divider()
            toggleSection
            Divider()
            footer
        }
        .frame(width: 270)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            Text("Music Format Switcher")
                .fontWeight(.medium)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Audio Device")
                .font(.caption)
                .foregroundStyle(.secondary)
            DeviceComboBox(text: $monitor.deviceName, items: monitor.availableDevices)
                .frame(height: 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            if monitor.lastTrack.isEmpty {
                Text("Waiting for track…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(monitor.lastTrack)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(monitor.lastSampleRate.formatted()) Hz · \(monitor.lastBits)-bit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var toggleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Active", isOn: $monitor.isEnabled)
            Toggle("Launch at Login", isOn: $monitor.launchAtLogin)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
