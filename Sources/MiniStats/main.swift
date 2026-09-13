import Foundation
import AppKit

if CommandLine.arguments.contains("--sample") {
    print("App: \(BuildIdentity.displayName)")
    let monitor = Monitor(automatic: false)
    Thread.sleep(forTimeInterval: 1)
    monitor.sample()
    print("CPU: \(MetricFormat.percent(monitor.cpu))")
    print("Memory: \(MetricFormat.percent(monitor.memory?.fraction))")
    print("Download: \(MetricFormat.speed(monitor.network?.download))")
    print("Upload: \(MetricFormat.speed(monitor.network?.upload))")
    print("Interfaces: \(monitor.interfaces.joined(separator: ", "))")
    if monitor.cpu == nil || monitor.memory == nil || monitor.network == nil { exit(1) }
} else {
    NSApplication.shared.setActivationPolicy(.accessory)
    MiniStatsApp.main()
}
