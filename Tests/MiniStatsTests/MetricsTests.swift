import XCTest
@testable import MiniStats

final class MetricsTests: XCTestCase {
    func testSpeedAutomaticallyScalesUnits() {
        XCTAssertEqual(MetricFormat.speed(0), "0 KB/s")
        XCTAssertEqual(MetricFormat.speed(12_000), "12 KB/s")
        XCTAssertEqual(MetricFormat.speed(1_800_000), "1.8 MB/s")
        XCTAssertEqual(MetricFormat.speed(2_400_000_000), "2.4 GB/s")
        XCTAssertEqual(MetricFormat.speed(123_000_000), "123 MB/s")
    }

    func testSpeedPromotesBeforeRoundingToFourDigits() {
        XCTAssertEqual(MetricFormat.speed(999_499), "999 KB/s")
        XCTAssertEqual(MetricFormat.speed(999_500), "1.0 MB/s")
        XCTAssertEqual(MetricFormat.speed(999_500_000), "1.0 GB/s")
        XCTAssertEqual(MetricFormat.speed(9_950_000), "10 MB/s")
        XCTAssertEqual(MetricFormat.speed(1_000_000_000_000), "999+ GB/s")
    }

    func testSpeedHandlesUnavailableAndInvalidValues() {
        XCTAssertEqual(MetricFormat.speed(nil), "—")
        XCTAssertEqual(MetricFormat.speed(-1), "—")
        XCTAssertEqual(MetricFormat.speed(.infinity), "—")
        XCTAssertEqual(MetricFormat.speed(.nan), "—")
    }

    func testNetworkUsesElapsedTimeAndIgnoresNewInterfaces() {
        let rate = NetworkRate.calculate(
            previous: ["en0": .init(received: 100, sent: 200)],
            current: ["en0": .init(received: 1100, sent: 700), "en1": .init(received: 999999, sent: 999999)],
            elapsed: 2)
        XCTAssertEqual(rate.download, 500)
        XCTAssertEqual(rate.upload, 250)
    }

    func testCounterResetDoesNotProduceSpike() {
        let rate = NetworkRate.calculate(previous: ["en0": .init(received: 900, sent: 900)], current: ["en0": .init(received: 10, sent: 20)], elapsed: 1)
        XCTAssertEqual(rate.download, 0)
        XCTAssertEqual(rate.upload, 0)
    }

    func testCPUUsesTickDeltas() {
        let previous = CPUTicks(user: 100, system: 100, idle: 100, nice: 0)
        let current = CPUTicks(user: 120, system: 110, idle: 170, nice: 0)
        XCTAssertEqual(current.usage(since: previous)!, 0.3, accuracy: 0.00001)
        XCTAssertNil(previous.usage(since: previous))
    }
}
