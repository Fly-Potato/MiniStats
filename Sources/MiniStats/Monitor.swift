import Foundation
import Combine

final class Monitor: ObservableObject {
    @Published private(set) var cpu: Double?
    @Published private(set) var memory: MemoryUsage?
    @Published private(set) var network: NetworkRate?
    @Published private(set) var interfaces: [String] = []
    private(set) var history = MetricHistory()
    private var previousCPU: CPUTicks?
    private var previousNetwork: [String: NetworkCounters]?
    private var previousTime: TimeInterval?
    private var timer: Timer?

    init(automatic: Bool = true) {
        sample()
        if automatic {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
            timer.tolerance = 0.15
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    deinit { timer?.invalidate() }

    func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        let ticks = SystemMetrics.cpu()
        let counters = SystemMetrics.network()
        let elapsed = previousTime.map { now - $0 }
        // Discard the first sample and long gaps (such as sleep/wake).
        if let elapsed, elapsed > 0, elapsed < 5 {
            cpu = ticks.flatMap { tick in previousCPU.flatMap { tick.usage(since: $0) } }
            if let counters, let previousNetwork {
                network = .calculate(previous: previousNetwork, current: counters, elapsed: elapsed)
            } else { network = nil }
        } else {
            cpu = nil
            network = nil
        }
        memory = SystemMetrics.memory()
        interfaces = counters.map { $0.keys.sorted() } ?? []
        previousCPU = ticks
        previousNetwork = counters
        previousTime = now
        history.append(.init(date: Date(), cpu: cpu, memory: memory?.fraction,
                             download: network?.download, upload: network?.upload))
    }
}
