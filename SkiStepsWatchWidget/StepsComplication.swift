import WidgetKit
import SwiftUI
import HealthKit
import Charts

// MARK: - Data

struct StepsEntry: TimelineEntry {
    let date: Date
    let steps: Double
    let distance: Double      // meters
    let goal: Double
    let useMetric: Bool
    let hourly: [Double]      // 24 values, steps per hour today

    var progress: Double { goal > 0 ? steps / goal : 0 }

    static let sample = StepsEntry(
        date: .now, steps: 8_412, distance: 6_100, goal: 10_000, useMetric: false,
        hourly: [0, 0, 0, 0, 0, 120, 640, 980, 420, 300, 210, 820, 1_150, 540, 380, 290, 610, 720, 236, 0, 0, 0, 0, 0]
    )
}

struct StepsProvider: TimelineProvider {
    private let store = HKHealthStore()

    func placeholder(in context: Context) -> StepsEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (StepsEntry) -> Void) {
        if context.isPreview { completion(.sample); return }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        Task {
            let entry = await load()
            // Ask for a refresh in 15 minutes (watchOS decides the exact time),
            // and reset at midnight.
            let cal = Calendar.current
            var next = Date().addingTimeInterval(15 * 60)
            if let midnight = cal.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime),
               midnight < next {
                next = midnight
            }
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func load() async -> StepsEntry {
        let share = WatchShare.load()
        let goal = share?.stepGoal ?? 10_000
        let metric = share?.useMetric ?? false
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        async let s = sum(.stepCount, .count(), start, now)
        async let d = sum(.distanceWalkingRunning, .meter(), start, now)
        async let h = hourly(start: start, end: now)
        return StepsEntry(date: now, steps: await s, distance: await d, goal: goal, useMetric: metric, hourly: await h)
    }

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ start: Date, _ end: Date) async -> Double {
        await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(id),
                                      quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    private func hourly(start: Date, end: Date) async -> [Double] {
        await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: HKQuantityType(.stepCount),
                                                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                                options: .cumulativeSum, anchorDate: start,
                                                intervalComponents: DateComponents(hour: 1))
            q.initialResultsHandler = { _, results, _ in
                var hours = Array(repeating: 0.0, count: 24)
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let h = Calendar.current.component(.hour, from: stats.startDate)
                    if (0..<24).contains(h) { hours[h] = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0 }
                }
                cont.resume(returning: hours)
            }
            store.execute(q)
        }
    }
}

// MARK: - Formatting

private func compact(_ v: Double) -> String {
    if v >= 10_000 { return String(format: "%.0fk", v / 1000) }
    if v >= 1_000 { return String(format: "%.1fk", v / 1000) }
    return "\(Int(v))"
}

private func full(_ v: Double) -> String {
    Int(v.rounded()).formatted(.number.grouping(.automatic))
}

private let mint = Color(red: 0.24, green: 0.95, blue: 0.62)
private let sky = Color(red: 0.10, green: 0.74, blue: 0.98)
private let gold = Color(red: 1.0, green: 0.80, blue: 0.30)

// MARK: - Views

struct StepsComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: StepsEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: rectangular
        }
    }

    /// Ring around the step count, like an Activity ring.
    private var circular: some View {
        Gauge(value: min(entry.progress, 1)) {
            Image(systemName: "figure.walk")
        } currentValueLabel: {
            Text(compact(entry.steps))
                .font(.system(.body, design: .rounded).weight(.bold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(entry.progress >= 1 ? gold : mint)
        .widgetAccentable()
    }

    /// Curved gauge along the corner of the face.
    private var corner: some View {
        Image(systemName: entry.progress >= 1 ? "star.fill" : "figure.walk")
            .font(.title3.weight(.semibold))
            .widgetAccentable()
            .widgetLabel {
                Gauge(value: min(entry.progress, 1)) {
                    Text("Steps")
                } currentValueLabel: {
                    Text(compact(entry.steps))
                } minimumValueLabel: {
                    Text("")
                } maximumValueLabel: {
                    Text(compact(entry.goal))
                }
                .tint(Gradient(colors: [sky, mint]))
            }
    }

    private var inline: some View {
        Label("\(full(entry.steps)) steps · \(Int((entry.progress * 100).rounded()))%", systemImage: "figure.walk")
    }

    /// The big middle slot: today's steps by hour, with the total and goal.
    private var rectangular: some View {
        let nowHour = Calendar.current.component(.hour, from: entry.date)
        let peak = max(entry.hourly.max() ?? 0, 1)
        return HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: "figure.walk")
                    Text("STEPS")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(mint)
                .widgetAccentable()
                Chart {
                    ForEach(0..<24, id: \.self) { h in
                        BarMark(x: .value("Hour", h), y: .value("Steps", entry.hourly[h]), width: .fixed(3))
                            .foregroundStyle(h == nowHour ? mint : sky.opacity(0.75))
                            .cornerRadius(1)
                    }
                }
                .chartXScale(domain: 0...23)
                .chartYScale(domain: 0...peak)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: [6, 12, 18]) { v in
                        AxisGridLine().foregroundStyle(.white.opacity(0.25))
                        AxisValueLabel {
                            if let h = v.as(Int.self) {
                                Text(h == 12 ? "12P" : (h < 12 ? "\(h)A" : "\(h - 12)P")).font(.system(size: 8))
                            }
                        }
                    }
                }
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text(full(entry.steps))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .widgetAccentable()
                Text("\(Int((entry.progress * 100).rounded()))% of \(compact(entry.goal))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(entry.progress >= 1 ? gold : .secondary)
                Gauge(value: min(entry.progress, 1)) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(entry.progress >= 1 ? gold : mint)
                    .frame(width: 58)
                Text(distanceText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 62, alignment: .trailing)
        }
    }

    private var distanceText: String {
        let v = entry.useMetric ? entry.distance / 1000 : entry.distance / 1609.344
        return String(format: "%.1f %@", v, entry.useMetric ? "km" : "mi")
    }
}

struct StepsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SkiStepsComplication", provider: StepsProvider()) { entry in
            StepsComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Ski Steps")
        .description("Today's steps and progress toward your goal.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct SkiStepsWatchWidgets: WidgetBundle {
    var body: some Widget {
        StepsComplication()
    }
}
