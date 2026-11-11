import WidgetKit
import SwiftUI

struct StepEntry: TimelineEntry {
    let date: Date
    let snapshot: StepSnapshot
}

struct StepProvider: TimelineProvider {
    private var current: StepSnapshot {
        StepSnapshot.load() ?? .empty
    }

    func placeholder(in context: Context) -> StepEntry {
        StepEntry(date: .now, snapshot: StepSnapshot(day: .now, steps: 7_420, distanceMeters: 5_600, energy: 340,
                                                     activeMinutes: 22, goals: [:], useMetric: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (StepEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : StepEntry(date: .now, snapshot: current))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepEntry>) -> Void) {
        let snap = current
        var entries = [StepEntry(date: .now, snapshot: snap)]
        // Add an entry at midnight so the widget resets to 0 for the new day.
        if let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 0),
                                                    matchingPolicy: .nextTime) {
            entries.append(StepEntry(date: midnight, snapshot: snap))
        }
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

struct StepWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StepEntry

    private var snap: StepSnapshot { entry.snapshot }
    // The midnight entry is evaluated on its own date, so check against that.
    private var isSameDay: Bool { Calendar.current.isDate(snap.day, inSameDayAs: entry.date) }
    private var steps: Double { isSameDay ? snap.steps : 0 }
    private var stepGoal: Double { snap.goal(.steps) }
    private var progress: Double { stepGoal > 0 ? steps / stepGoal : 0 }
    private func value(_ m: Metric) -> Double { isSameDay ? snap.value(m) : 0 }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(progress, 1)) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(Fmt.compact(steps))
            }
            .gaugeStyle(.accessoryCircular)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(Fmt.steps(steps)) steps", systemImage: "figure.walk")
                    .font(.headline)
                Gauge(value: min(progress, 1)) { EmptyView() }
                    .gaugeStyle(.accessoryLinear)
                Text("\(Int((progress * 100).rounded()))% of \(Fmt.compact(stepGoal))")
                    .font(.caption)
            }

        case .accessoryInline:
            Label("\(Fmt.steps(steps)) steps", systemImage: "figure.walk")

        case .systemMedium:
            HStack(spacing: 16) {
                ZStack {
                    ring
                    VStack(spacing: 0) {
                        Text(Fmt.compact(steps))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("steps").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach([Metric.distance, .calories, .active]) { m in
                        let goal = snap.goal(m)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Image(systemName: m.icon).font(.caption2).foregroundStyle(m.color)
                                Text(m.text(m.display(value(m), useMetric: snap.useMetric)))
                                    .font(.caption.weight(.bold).monospacedDigit())
                                Text("/ \(m.text(m.display(goal, useMetric: snap.useMetric))) \(m.unit(useMetric: snap.useMetric))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            GoalBar(progress: goal > 0 ? value(m) / goal : 0, color: m.color, height: 5)
                        }
                    }
                }
            }

        default:
            ZStack {
                ring
                VStack(spacing: 0) {
                    Text(Fmt.steps(steps))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("steps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22)
            }
        }
    }

    private var ring: some View {
        ProgressRing(progress: progress, lineWidth: family == .systemMedium ? 14 : 13)
    }
}

struct SkiStepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SkiStepsWidget", provider: StepProvider()) { entry in
            StepWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Theme.background
                }
        }
        .configurationDisplayName("Steps")
        .description("Today's steps, distance, calories and active time.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct SkiStepsWidgetBundle: WidgetBundle {
    var body: some Widget {
        SkiStepsWidget()
    }
}
