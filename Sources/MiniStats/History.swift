import Foundation

struct HistorySample {
    let date: Date
    let cpu: Double?
    let memory: Double?
    let download: Double?
    let upload: Double?
}

struct MetricHistory {
    private(set) var samples: [HistorySample] = []
    static let retention: TimeInterval = 3_600

    mutating func append(_ sample: HistorySample) {
        // A backwards wall-clock adjustment starts a new timeline.
        if let last = samples.last, sample.date <= last.date { samples.removeAll(keepingCapacity: true) }
        samples.append(sample)
        let cutoff = sample.date.addingTimeInterval(-Self.retention)
        if let first = samples.firstIndex(where: { $0.date >= cutoff }), first > 0 {
            samples.removeFirst(first)
        }
        if samples.count > 3_601 { samples.removeFirst(samples.count - 3_601) }
    }

    func window(minutes: Int, endingAt end: Date) -> [HistorySample] {
        let start = end.addingTimeInterval(-Double(minutes) * 60)
        return samples.filter { $0.date >= start && $0.date <= end }
    }
}

struct TrendPoint: Identifiable {
    let date: Date
    let value: Double
    let segment: Int
    var id: Date { date }
}

enum TrendData {
    static func points(_ samples: [HistorySample], value: KeyPath<HistorySample, Double?>,
                       start: Date, end: Date, buckets: Int = 120) -> [TrendPoint] {
        let bucketDuration = max(end.timeIntervalSince(start) / Double(max(buckets, 1)), 1)
        var result: [TrendPoint] = []
        var bucket: [TrendPoint] = []
        var bucketIndex: Int?
        var segment = 0
        var previous: Date?

        func flush() {
            guard let first = bucket.first, let last = bucket.last,
                  let low = bucket.min(by: { $0.value < $1.value }),
                  let high = bucket.max(by: { $0.value < $1.value }) else { return }
            var dates = Set<Date>()
            result.append(contentsOf: [first, low, high, last].sorted { $0.date < $1.date }.filter { dates.insert($0.date).inserted })
            bucket.removeAll(keepingCapacity: true)
        }

        for sample in samples where sample.date >= start && sample.date <= end {
            guard let number = sample[keyPath: value], number.isFinite else {
                flush()
                segment += 1
                previous = nil
                continue
            }
            if let previous, sample.date.timeIntervalSince(previous) >= 5 {
                flush()
                segment += 1
            }
            let index = Int(sample.date.timeIntervalSince(start) / bucketDuration)
            if index != bucketIndex { flush(); bucketIndex = index }
            bucket.append(.init(date: sample.date, value: number, segment: segment))
            previous = sample.date
        }
        flush()
        return result
    }

    static func nearest(_ samples: [HistorySample], to date: Date) -> HistorySample? {
        guard let sample = samples.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
              abs(sample.date.timeIntervalSince(date)) < 2.5 else { return nil }
        return sample
    }
}

struct NetworkScale {
    private(set) var upper: Double = 1_000
    private var lowSince: Date?

    mutating func update(peak: Double, now: Date) {
        let target = Self.ceiling(max(peak * 1.1, 1_000))
        if target > upper {
            upper = target
            lowSince = nil
        } else if target <= upper / 2 {
            if let lowSince, now.timeIntervalSince(lowSince) >= 30 {
                upper = target
                self.lowSince = nil
            } else if lowSince == nil { lowSince = now }
        } else { lowSince = nil }
    }

    private static func ceiling(_ value: Double) -> Double {
        let magnitude = pow(10, floor(log10(value)))
        let normalized = value / magnitude
        let step = [1.0, 2, 5, 10].first { $0 >= normalized } ?? 10
        return step * magnitude
    }
}
