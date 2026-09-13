import Foundation
import Darwin

struct NetworkCounters {
    let received: UInt64
    let sent: UInt64
}

struct NetworkRate {
    let download: Double
    let upload: Double

    static func calculate(previous: [String: NetworkCounters], current: [String: NetworkCounters], elapsed: Double) -> Self {
        guard elapsed > 0 else { return .init(download: 0, upload: 0) }
        var received: Double = 0
        var sent: Double = 0
        for (name, now) in current {
            guard let old = previous[name] else { continue }
            // A newly connected interface or reset counter must not create a spike.
            if now.received >= old.received { received += Double(now.received - old.received) }
            if now.sent >= old.sent { sent += Double(now.sent - old.sent) }
        }
        return .init(download: received / elapsed, upload: sent / elapsed)
    }
}

struct CPUTicks {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func usage(since old: Self) -> Double? {
        let busy = Double(user &- old.user) + Double(system &- old.system) + Double(nice &- old.nice)
        let total = busy + Double(idle &- old.idle)
        return total > 0 ? busy / total : nil
    }
}

struct MemoryUsage {
    let used: UInt64
    let total: UInt64
    var fraction: Double { Double(used) / Double(total) }
}

enum SystemMetrics {
    static func cpu() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return .init(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    static func memory() -> MemoryUsage? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // Approximate physical memory in use: anonymous + wired + compressed pages.
        let pages = UInt64(info.internal_page_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let purgeable = UInt64(info.purgeable_count)
        let used = (pages > purgeable ? pages - purgeable : 0) * UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory
        return .init(used: min(used, total), total: total)
    }

    static func network() -> [String: NetworkCounters]? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var result: [String: NetworkCounters] = [:]
        var cursor = addresses
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let interface = entry.pointee
            guard let address = interface.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_LINK,
                  interface.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let data = interface.ifa_data else { continue }
            let name = String(cString: interface.ifa_name)
            // Physical Ethernet/Wi-Fi interfaces; exclude VPN/bridge duplicates.
            guard name.hasPrefix("en") else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            result[name] = .init(received: UInt64(stats.ifi_ibytes), sent: UInt64(stats.ifi_obytes))
        }
        return result
    }
}

enum MetricFormat {
    static func speed(_ bytes: Double?) -> String {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return "—" }
        let units = ["KB/s", "MB/s", "GB/s"]
        var value = bytes / 1_000
        var unit = 0
        // Promote before rounding would display four digits, such as 1000 KB/s.
        while value >= 999.5 && unit < units.count - 1 {
            value /= 1_000
            unit += 1
        }
        if value >= 999.5 { return "999+ GB/s" }
        let precision = value > 0 && value < 9.95 ? "%.1f" : "%.0f"
        return String(format: precision, value) + " " + units[unit]
    }
    static func percent(_ fraction: Double?) -> String {
        fraction.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
    }
}
