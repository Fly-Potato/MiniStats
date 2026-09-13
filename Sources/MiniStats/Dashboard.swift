import SwiftUI
import Charts
import AppKit

private struct TrendSeries: Identifiable {
    let id: String
    let color: Color
    let dashed: Bool
    let keyPath: KeyPath<HistorySample, Double?>
    let points: [TrendPoint]
}

private struct DashboardSnapshot {
    var end = Date()
    var samples: [HistorySample] = []
    var cpu: [TrendSeries] = []
    var memory: [TrendSeries] = []
    var network: [TrendSeries] = []
}

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @AppStorage("historyMinutes") private var storedMinutes = 10
    @State private var visible = false
    @State private var snapshot = DashboardSnapshot()
    @State private var networkScale = NetworkScale()
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private var minutes: Int { [10, 30, 60].contains(storedMinutes) ? storedMinutes : 10 }
    private var start: Date { snapshot.end.addingTimeInterval(-Double(minutes) * 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("MiniStats", systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                Text("实时更新").font(.caption).foregroundStyle(.secondary)
            }
            Picker("时间范围", selection: $storedMinutes) {
                ForEach([10, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
            }
            .pickerStyle(.segmented)
            if visible {
                ScrollView {
                    VStack(spacing: 12) {
                        TrendCard(title: "CPU", current: MetricFormat.percent(monitor.cpu),
                                  series: snapshot.cpu, samples: snapshot.samples, start: start, end: snapshot.end, upper: 1)
                        TrendCard(title: "内存", current: memoryLabel,
                                  series: snapshot.memory, samples: snapshot.samples, start: start, end: snapshot.end, upper: 1)
                        TrendCard(title: "网络", current: "↓ \(MetricFormat.speed(monitor.network?.download))  ↑ \(MetricFormat.speed(monitor.network?.upload))",
                                  series: snapshot.network, samples: snapshot.samples, start: start, end: snapshot.end,
                                  upper: networkScale.upper, isNetwork: true)
                    }
                }
                .frame(height: 450)
            }
            HStack {
                Text(recordingLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
            Text("内存为估算值 · 网卡：\(monitor.interfaces.joined(separator: ", "))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(16)
        .frame(width: 400)
        .onAppear {
            visible = true
            if storedMinutes != minutes { storedMinutes = minutes }
            updateCharts()
        }
        .onDisappear { visible = false }
        .onReceive(refresh) { _ in if visible { updateCharts() } }
        .onChange(of: storedMinutes) { _ in
            networkScale = NetworkScale()
            if visible { updateCharts() }
        }
    }

    private var memoryLabel: String {
        guard let memory = monitor.memory else { return "—" }
        return String(format: "%.0f%% · %.1f / %.1f GB", memory.fraction * 100, Double(memory.used) / 1e9, Double(memory.total) / 1e9)
    }

    private var recordingLabel: String {
        guard let first = monitor.history.samples.first else { return "正在收集数据…" }
        let elapsed = max(0, snapshot.end.timeIntervalSince(first.date))
        return elapsed < 60 ? "已记录不足 1 分钟" : "已记录 \(min(60, Int(elapsed / 60))) 分钟"
    }

    private func updateCharts() {
        let end = Date()
        let start = end.addingTimeInterval(-Double(minutes) * 60)
        let samples = monitor.history.window(minutes: minutes, endingAt: end)
        func series(_ name: String, _ color: Color, _ key: KeyPath<HistorySample, Double?>, dashed: Bool = false) -> TrendSeries {
            .init(id: name, color: color, dashed: dashed, keyPath: key,
                  points: TrendData.points(samples, value: key, start: start, end: end))
        }
        let peak = samples.reduce(0.0) { max($0, max($1.download ?? 0, $1.upload ?? 0)) }
        networkScale.update(peak: peak, now: end)
        snapshot = .init(end: end, samples: samples,
                         cpu: [series("CPU", .blue, \.cpu)],
                         memory: [series("内存", .purple, \.memory)],
                         network: [series("下载", .blue, \.download), series("上传", .orange, \.upload, dashed: true)])
    }
}

private struct TrendCard: View {
    let title: String
    let current: String
    let series: [TrendSeries]
    let samples: [HistorySample]
    let start: Date
    let end: Date
    let upper: Double
    var isNetwork = false
    @State private var hovered: Date?

    private var selected: HistorySample? { hovered.flatMap { TrendData.nearest(samples, to: $0) } }
    private var networkUnit: (divisor: Double, label: String) {
        if upper >= 1e9 { return (1e9, "GB/s") }
        if upper >= 1e6 { return (1e6, "MB/s") }
        return (1e3, "KB/s")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(current).font(.caption).monospacedDigit()
            }
            HStack(spacing: 8) {
                if isNetwork {
                    ForEach(series) { item in
                        HStack(spacing: 3) {
                            Text(item.dashed ? "┄" : "━").foregroundStyle(item.color)
                            Text(item.id)
                        }
                    }
                    Spacer()
                    Text(networkUnit.label)
                } else { Text("使用率 %") }
            }
            .font(.caption2).foregroundStyle(.secondary)
            Chart {
                ForEach(series) { item in
                    ForEach(item.points) { point in
                        LineMark(x: .value("时间", point.date), y: .value("数值", point.value),
                                 series: .value("连续区间", "\(item.id)-\(point.segment)"))
                            .foregroundStyle(item.color)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: item.dashed ? [4, 3] : []))
                            .interpolationMethod(.linear)
                    }
                    // A single point is still visible before enough samples form a line.
                    if item.points.count == 1, let point = item.points.first {
                        PointMark(x: .value("时间", point.date), y: .value("数值", point.value))
                            .foregroundStyle(item.color).symbolSize(12)
                    }
                }
                if let hovered, hovered >= start && hovered <= end {
                    RuleMark(x: .value("选中时间", hovered)).foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .chartXScale(domain: start...end)
            .chartYScale(domain: 0...upper)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: [start, start.addingTimeInterval(end.timeIntervalSince(start) / 2), end]) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            let remaining = Int(end.timeIntervalSince(date) / 60)
                            Text(remaining == 0 ? "现在" : "−\(remaining) 分钟").font(.system(size: 8))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, upper / 2, upper]) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(isNetwork ? String(format: "%g", number / networkUnit.divisor) : String(format: "%.0f", number * 100))
                                .font(.system(size: 8))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let frame = geometry[proxy.plotAreaFrame]
                                hovered = frame.contains(location) ? proxy.value(atX: location.x - frame.minX, as: Date.self) : nil
                            case .ended: hovered = nil
                            }
                        }
                }
            }
            .frame(height: 82)
            .accessibilityLabel("\(title)，所选时间范围内的历史趋势")
            Text(hoverLabel).font(.system(size: 9)).foregroundStyle(.secondary)
                .monospacedDigit().lineLimit(1).frame(height: 12, alignment: .leading)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: start) { _ in
            if let hovered, hovered < start { self.hovered = nil }
        }
    }

    private var hoverLabel: String {
        guard let hovered else {
            return series.allSatisfy { $0.points.isEmpty } ? "正在收集数据…" : "悬停查看时间与数值"
        }
        let time = hovered.formatted(date: .omitted, time: .standard)
        guard let selected else { return "\(time) · 无采样数据" }
        let values = series.map { item in
            let value = selected[keyPath: item.keyPath]
            return "\(item.id) \(isNetwork ? MetricFormat.speed(value) : MetricFormat.percent(value))"
        }.joined(separator: "  ")
        return "\(time) · \(values)"
    }
}
