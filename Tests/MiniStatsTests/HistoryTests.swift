import XCTest
@testable import MiniStats

final class HistoryTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 10_000)
    private func sample(_ second: Double, _ value: Double? = 0.5) -> HistorySample {
        .init(date: origin.addingTimeInterval(second), cpu: value, memory: value, download: value, upload: value)
    }

    func testHistoryRetainsOneHourAndClipsSelectedWindow() {
        var history = MetricHistory()
        for second in 0...4_000 { history.append(sample(Double(second))) }
        XCTAssertEqual(history.samples.count, 3_601)
        XCTAssertEqual(history.samples.first?.date, origin.addingTimeInterval(400))
        for minutes in [10, 30, 60] {
            let window = history.window(minutes: minutes, endingAt: origin.addingTimeInterval(4_000))
            XCTAssertEqual(window.count, minutes * 60 + 1)
            XCTAssertEqual(window.last?.date, origin.addingTimeInterval(4_000))
        }
    }

    func testHistoryHandlesSleepAndBackwardsClock() {
        var history = MetricHistory()
        history.append(sample(0))
        history.append(sample(7_200))
        XCTAssertEqual(history.samples.count, 1)
        history.append(sample(10))
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.first?.date, origin.addingTimeInterval(10))
    }

    func testMissingSamplesAndLongGapsBreakLines() {
        let points = TrendData.points([sample(0), sample(1), sample(2, nil), sample(3), sample(10)],
                                      value: \.cpu, start: origin, end: origin.addingTimeInterval(10))
        XCTAssertEqual(points.map(\.segment), [0, 0, 1, 2])
        XCTAssertNil(TrendData.nearest([sample(0), sample(10)], to: origin.addingTimeInterval(5)))
    }

    func testDownsamplingRetainsExtremaAndEndpointsInOrder() {
        let values = [0.4, 0.1, 0.5, 0.9, 0.3, 0.4]
        let samples = values.enumerated().map { sample(Double($0.offset), $0.element) }
        let points = TrendData.points(samples, value: \.cpu, start: origin, end: origin.addingTimeInterval(10), buckets: 1)
        XCTAssertEqual(points.map(\.value), [0.4, 0.1, 0.9, 0.4])
        XCTAssertEqual(points.first?.date, samples.first?.date)
        XCTAssertEqual(points.last?.date, samples.last?.date)
    }

    func testScaleExpandsImmediatelyAndShrinksAfterDelay() {
        var scale = NetworkScale()
        scale.update(peak: 1_000_000, now: origin)
        XCTAssertEqual(scale.upper, 2_000_000)
        scale.update(peak: 1_000, now: origin.addingTimeInterval(1))
        XCTAssertEqual(scale.upper, 2_000_000)
        scale.update(peak: 1_000, now: origin.addingTimeInterval(30))
        XCTAssertEqual(scale.upper, 2_000_000)
        scale.update(peak: 1_000, now: origin.addingTimeInterval(31))
        XCTAssertEqual(scale.upper, 2_000)
    }
}
