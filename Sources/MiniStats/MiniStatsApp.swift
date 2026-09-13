import SwiftUI
import AppKit

struct MiniStatsApp: App {
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            Dashboard(monitor: monitor)
        } label: {
            Text("↓ \(MetricFormat.speed(monitor.network?.download))  ↑ \(MetricFormat.speed(monitor.network?.upload))  CPU \(MetricFormat.percent(monitor.cpu))")
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}

private struct Dashboard: View {
    @ObservedObject var monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("MiniStats", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Text("每秒更新").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            resource("CPU", symbol: "cpu", value: MetricFormat.percent(monitor.cpu), fraction: monitor.cpu, color: .blue)
            resource("内存", symbol: "memorychip", value: MetricFormat.percent(monitor.memory?.fraction), fraction: monitor.memory?.fraction, color: .purple)
            if let memory = monitor.memory {
                Text(String(format: "已用 %.1f GB / 共 %.1f GB", Double(memory.used) / 1e9, Double(memory.total) / 1e9))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                networkValue("下载", symbol: "arrow.down", value: monitor.network?.download)
                Spacer()
                networkValue("上传", symbol: "arrow.up", value: monitor.network?.upload)
            }
            Text("物理网卡：\(monitor.interfaces.isEmpty ? "无活动接口" : monitor.interfaces.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("内存为估算值").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func resource(_ title: String, symbol: String, value: String, fraction: Double?, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(value).monospacedDigit()
            }
            ProgressView(value: fraction ?? 0).tint(color)
                .accessibilityLabel(title)
                .accessibilityValue(value)
        }
    }

    private func networkValue(_ title: String, symbol: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(MetricFormat.speed(value)).font(.system(.title3, design: .monospaced))
        }
    }
}
