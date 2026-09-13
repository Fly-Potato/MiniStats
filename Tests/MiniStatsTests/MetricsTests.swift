import XCTest
@testable import MiniStats

final class MetricsTests: XCTestCase {
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
