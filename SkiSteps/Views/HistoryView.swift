import SwiftUI
import Charts

struct HistoryView: View {
    enum Span: String, CaseIterable, Identifiable {
        case week = "W", month = "M", sixMonths = "6M", year = "Y"
        var id: Self { self }

        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .sixMonths: 182
            case .year: 365
            }
        }

        /// How each bar is grouped.
        var unit: Calendar.Component {
            switch self {
            case .week, .month: .day
            case .sixMonths: .weekOfYear
            case .year: .month
            }
        }
    }

    @EnvironmentObject private var health: HealthStore
    @AppStorage("dailyGoal") private var goal: Double = 10_000
    @State private var span: Span = .week
    @State private var selection: Date?

    private let cal = Calendar.current

    private var rawDays: [StepPoint] { Array(health.daily.suffix(span.days)) }

    private var bars: [StepPoint] {
        guard span.unit != .day else { return rawDays }
        let groups = Dictionary(grouping: rawDays) { point in
            cal.dateInterval(of: span.unit, for: point.date)?.start ?? point.date
        }
        return groups.map { start, points in
            StepPoint(date: start, value: points.map(\.value).reduce(0, +) / Double(max(points.count, 1)))
        }
        .sorted { $0.date < $1.date }
    }

    private var selectedBar: StepPoint? {
        guard let selection else { return nil }
        return bars.first { cal.isDate($0.date, equalTo: selection, toGranularity: span.unit) }
    }

    private var average: Double {
        // Leave out today so an unfinished day doesn't drag the average down.
        let past = rawDays.filter { !cal.isDateInToday($0.date) }
        guard !past.isEmpty else { return 0 }
        return past.map(\.value).reduce(0, +) / Double(past.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Range", selection: $span) {
                        ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: span) { _, _ in selection = nil }

                    chartCard
                    summaryGrid
                    if span == .week || span == .month { dayList }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("History")
            .refreshable { await health.refresh() }
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let bar = selectedBar {
                    Text(span.unit == .day ? "STEPS" : "DAILY AVERAGE")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(Fmt.steps(bar.value))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(label(for: bar.date))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("DAILY AVERAGE")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(Fmt.steps(average))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(rangeLabel)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(height: 78, alignment: .topLeading)

            Chart {
                ForEach(bars) { bar in
                    BarMark(x: .value("Date", bar.date, unit: span.unit),
                            y: .value("Steps", bar.value))
                        .foregroundStyle(bar.value >= goal ? Theme.accent : Theme.accent2.opacity(0.6))
                        .cornerRadius(span == .week ? 6 : 2)
                        .opacity(selectedBar == nil || selectedBar == bar ? 1 : 0.35)
                }
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.gold.opacity(0.8))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal").font(.caption2.weight(.semibold)).foregroundStyle(Theme.gold)
                    }
            }
            .chartXSelection(value: $selection)
            .chartXAxis {
                switch span {
                case .week:
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    }
                case .month:
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                case .sixMonths, .year:
                    AxisMarks(values: .stride(by: .month, count: span == .year ? 2 : 1)) { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Fmt.compact(v)) }
                    }
                }
            }
            .frame(height: 240)
            .animation(.easeInOut, value: span)
        }
        .padding(16)
        .card()
    }

    private func label(for date: Date) -> String {
        switch span.unit {
        case .weekOfYear: "Week of " + date.formatted(.dateTime.month(.abbreviated).day())
        case .month: date.formatted(.dateTime.month(.wide).year())
        default: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }

    private var rangeLabel: String {
        guard let first = rawDays.first?.date, let last = rawDays.last?.date else { return "" }
        return first.formatted(.dateTime.month(.abbreviated).day()) + " – " +
            last.formatted(.dateTime.month(.abbreviated).day().year())
    }

    // MARK: Summary

    private var summaryGrid: some View {
        let total = rawDays.map(\.value).reduce(0, +)
        let best = rawDays.max { $0.value < $1.value }
        let met = rawDays.filter { $0.value >= goal }.count
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            BadgeTile(icon: "sum", color: Theme.accent2, title: "Total", value: Fmt.steps(total))
            BadgeTile(icon: "target", color: Theme.accent, title: "Goals met", value: "\(met) of \(rawDays.count)")
            BadgeTile(icon: "trophy.fill", color: Theme.gold, title: "Best day",
                      value: best.map { Fmt.steps($0.value) } ?? "—",
                      caption: best.map { $0.date.formatted(.dateTime.month(.abbreviated).day()) })
            BadgeTile(icon: "flame.fill", color: .orange, title: "Streak",
                      value: "\(health.streak(goal: goal)) days")
        }
    }

    // MARK: Day list

    private var dayList: some View {
        VStack(spacing: 0) {
            ForEach(Array(rawDays.reversed())) { day in
                HStack(spacing: 12) {
                    ProgressRing(progress: goal > 0 ? day.value / goal : 0, lineWidth: 4)
                        .frame(width: 30, height: 30)
                    Text(cal.isDateInToday(day.date) ? "Today"
                         : day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    Spacer()
                    Text(Fmt.steps(day.value))
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(day.value >= goal ? Theme.accent : .primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                if day.id != rawDays.first?.id {
                    Divider().overlay(Theme.stroke).padding(.leading, 58)
                }
            }
        }
        .padding(.vertical, 6)
        .card()
    }
}
