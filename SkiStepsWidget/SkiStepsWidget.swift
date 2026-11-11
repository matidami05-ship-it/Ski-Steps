import WidgetKit
import SwiftUI

struct StepEntry: TimelineEntry {
    let date: Date
    let snapshot: StepSnapshot
}

struct StepProvider: TimelineProvider {
    private var current: StepSnapshot {
        StepSnapshot.load() ?? StepSnapshot(day: .now, steps: 0, distanceMeters: 0, goal: 10_000, useMetric: false)
    }

    func placeholder(in context: Context) -> StepEntry {
        StepEntry(date: .now, snapshot: StepSnapshot(day: .now, steps: 7_420, distanceMeters: 5_600, goal: 10_000, useMetric: false))
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
    private var distance: Double { isSameDay ? snap.distanceMeters : 0 }
    private var progress: Double { snap.goal > 0 ? steps / snap.goal : 0 }

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
                Text("\(Int((progress * 100).rounded()))% of \(Fmt.compact(snap.goal))")
                    .font(.caption)
            }

        case .accessoryInline:
            Label("\(Fmt.steps(steps)) steps", systemImage: "figure.walk")

        case .systemMedium:
            HStack(spacing: 18) {
                ring.frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Steps today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Fmt.steps(steps))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Label("\(Fmt.distance(distance, metric: snap.useMetric)) \(Fmt.distanceUnit(snap.useMetric))",
                          systemImage: "location.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent2)
                    Text(progress >= 1 ? "Goal reached 🎉" : "\(Fmt.steps(max(snap.goal - steps, 0))) to go")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(progress >= 1 ? Theme.gold : .primary)
                }
                Spacer(minLength: 0)
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
        .description("Today's steps and progress toward your goal.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct SkiStepsWidgetBundle: WidgetBundle {
    var body: some Widget {
        SkiStepsWidget()
    }
}
