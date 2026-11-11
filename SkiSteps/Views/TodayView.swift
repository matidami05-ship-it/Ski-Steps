import SwiftUI
import Charts

struct TodayView: View {
    @EnvironmentObject private var health: HealthStore
    @AppStorage("dailyGoal") private var goal: Double = 10_000
    @AppStorage("useMetric") private var metric = false
    @AppStorage("distanceGoal") private var distanceGoal: Double = Metric.distance.defaultGoal
    @AppStorage("calorieGoal") private var calorieGoal: Double = Metric.calories.defaultGoal
    @AppStorage("activeGoal") private var activeGoal: Double = Metric.active.defaultGoal
    @State private var celebrate = 0

    private var progress: Double { goal > 0 ? health.steps / goal : 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ringCard
                    statsRow
                    if !health.hasAnyData { noDataCard }
                    CurveCard(title: "Active Energy", icon: "flame.fill", color: Theme.calorie,
                              curve: health.energyCurve, unit: "kcal")
                    restingCard
                    CurveCard(title: "Exercise Minutes", icon: "timer", color: Theme.active,
                              curve: health.exerciseCurve, unit: "min")
                    if !health.stepsByDevice.isEmpty { devicesCard }
                    hourlyCard
                    weekCard
                    streakCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await health.refresh() }
            .sensoryFeedback(.success, trigger: celebrate)
            .onChange(of: health.steps >= goal) { _, reached in
                if reached { celebrate += 1 }
            }
        }
    }

    // MARK: Ring

    private var ringCard: some View {
        VStack(spacing: 14) {
            ZStack {
                ProgressRing(progress: progress, lineWidth: 24)
                    .frame(width: 250, height: 250)
                    .animation(.spring(duration: 1.1), value: progress)
                VStack(spacing: 4) {
                    Image(systemName: progress >= 1 ? "star.fill" : "figure.walk")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(progress >= 1 ? Theme.gold : Theme.accent)
                    Text(Fmt.steps(health.steps))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: health.steps))
                        .animation(.snappy, value: health.steps)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("of \(Fmt.steps(goal)) steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
            }
            Text(statusLine)
                .font(.headline)
                .foregroundStyle(progress >= 1 ? Theme.gold : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .card()
    }

    private var statusLine: String {
        let pct = Int((progress * 100).rounded())
        if progress >= 2 { return "Double your goal — incredible! \(pct)%" }
        if progress >= 1 { return "Goal crushed! \(pct)%" }
        let left = max(goal - health.steps, 0)
        return "\(Fmt.steps(left)) to go · \(pct)%"
    }

    // MARK: Stats

    private var statsRow: some View {
        VStack(spacing: 10) {
            ForEach([Metric.distance, .calories, .active]) { m in
                GoalRow(metric: m,
                        value: health.today(m),
                        goal: m.goal(),
                        useMetric: metric)
            }
            HStack(spacing: 10) {
                StatTile(icon: "stairs", color: .orange,
                         value: Fmt.steps(health.flights), label: "floors climbed")
                StatTile(icon: "figure.run", color: Theme.run,
                         value: Fmt.distance(todayRunMeters, metric: metric),
                         label: "\(Fmt.distanceUnit(metric)) run today")
            }
        }
    }

    private var todayRunMeters: Double {
        health.workouts
            .filter { $0.kind == .running && Calendar.current.isDateInToday($0.start) }
            .map(\.distance).reduce(0, +)
    }

    private var noDataCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.yellow)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("No step data yet").font(.headline)
                Text("If you've been walking, check that Ski Steps is allowed to read Steps in the Health app: Sharing › Apps › Ski Steps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private var restingCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "bed.double.fill")
                .foregroundStyle(Theme.calorie)
                .frame(width: 40, height: 40)
                .background(Theme.calorie.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Resting Energy").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.steps(health.restingEnergy)).font(.title2.weight(.bold).monospacedDigit())
                    Text("kcal").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Total burned").font(.caption).foregroundStyle(.secondary)
                Text("\(Fmt.steps(health.restingEnergy + health.energy)) kcal")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
        .padding(16)
        .card()
    }

    // MARK: Devices

    private var devicesCard: some View {
        let total = max(health.stepsByDevice.map(\.value).reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Steps by device").font(.headline)
                Spacer()
                Text("Health merges these").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(health.stepsByDevice) { d in
                HStack(spacing: 12) {
                    Image(systemName: d.isWatch ? "applewatch" : "iphone")
                        .font(.title3)
                        .foregroundStyle(d.isWatch ? Theme.accent : Theme.accent2)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(d.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text(Fmt.steps(d.value)).font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        GoalBar(progress: d.value / total, color: d.isWatch ? Theme.accent : Theme.accent2, height: 5)
                    }
                }
            }
        }
        .padding(16)
        .card()
    }

    // MARK: Hourly

    private var hourlyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today by hour").font(.headline)
                Spacer()
                if let peak = health.hourly.max(by: { $0.value < $1.value }), peak.value > 0 {
                    Text("Peak \(peak.date.formatted(.dateTime.hour()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Chart(health.hourly) { point in
                BarMark(x: .value("Hour", point.date, unit: .hour),
                        y: .value("Steps", point.value))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.accent2, Theme.accent], startPoint: .bottom, endPoint: .top)
                    )
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel(format: .dateTime.hour())
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
            .frame(height: 150)
        }
        .padding(16)
        .card()
    }

    // MARK: Week

    private var weekCard: some View {
        let week = Array(health.daily.suffix(7))
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                let met = week.filter { $0.value >= goal }.count
                Text("\(met)/\(week.count) goals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                ForEach(week) { day in
                    let isToday = Calendar.current.isDateInToday(day.date)
                    VStack(spacing: 6) {
                        ZStack {
                            ProgressRing(progress: goal > 0 ? day.value / goal : 0, lineWidth: 6)
                                .frame(width: 40, height: 40)
                            if day.value >= goal {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Theme.accent : .secondary)
                        Text(Fmt.compact(day.value))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .card()
    }

    // MARK: Streak

    private var streakCard: some View {
        HStack(spacing: 10) {
            BadgeTile(icon: "flame.fill", color: .orange,
                      title: "Streak",
                      value: "\(health.streak(goal: goal)) days")
            BadgeTile(icon: "trophy.fill", color: Theme.gold,
                      title: "Best day",
                      value: health.bestDay.map { Fmt.steps($0.value) } ?? "—",
                      caption: health.bestDay.map { $0.date.formatted(.dateTime.month(.abbreviated).day().year()) })
        }
    }
}

// MARK: - Reusable pieces

/// Today's running total vs. your average day, like HealthFit.
struct CurveCard: View {
    var title: String
    var icon: String
    var color: Color
    var curve: DayCurve
    var unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)
            HStack(spacing: 0) {
                total(curve.averageNow, "Average", .gray)
                total(curve.todayTotal, "Today", color)
            }
            Chart {
                ForEach(curve.average) { p in
                    LineMark(x: .value("Time", p.date), y: .value("Average", p.value), series: .value("S", "avg"))
                        .foregroundStyle(Color.gray)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                }
                ForEach(curve.today) { p in
                    LineMark(x: .value("Time", p.date), y: .value("Today", p.value), series: .value("S", "today"))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 3.5))
                        .interpolationMethod(.monotone)
                }
                if let last = curve.today.last {
                    RuleMark(x: .value("Now", last.date))
                        .foregroundStyle(.white.opacity(0.3))
                    PointMark(x: .value("Now", last.date), y: .value("Today", last.value))
                        .foregroundStyle(color)
                        .symbolSize(90)
                    PointMark(x: .value("Now", last.date), y: .value("Average", curve.averageNow))
                        .foregroundStyle(Color.gray)
                        .symbolSize(70)
                }
            }
            .chartXScale(domain: dayDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisTick().foregroundStyle(Theme.stroke)
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 170)
        }
        .padding(16)
        .card()
    }

    private var dayDomain: ClosedRange<Date> {
        let start = Calendar.current.startOfDay(for: .now)
        return start...Calendar.current.date(byAdding: .day, value: 1, to: start)!
    }

    private func total(_ v: Double, _ label: String, _ c: Color) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.steps(v)).font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                Text(unit).font(.headline)
            }
            .foregroundStyle(c)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct GoalRow: View {
    var metric: Metric
    var value: Double
    var goal: Double
    var useMetric: Bool

    private var progress: Double { goal > 0 ? value / goal : 0 }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                ProgressRing(progress: progress, lineWidth: 6, colors: [metric.color.opacity(0.6), metric.color])
                Image(systemName: progress >= 1 ? "checkmark" : metric.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(progress >= 1 ? Theme.gold : metric.color)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.title).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(metric.text(metric.display(value, useMetric: useMetric)))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(metric.color)
                    Text("/ \(metric.text(metric.display(goal, useMetric: useMetric))) \(metric.unit(useMetric: useMetric))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GoalBar(progress: progress, color: metric.color)
            }
        }
        .padding(14)
        .card()
    }
}

struct StatTile: View {
    var icon: String
    var color: Color
    var value: String
    var label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .card()
    }
}

struct BadgeTile: View {
    var icon: String
    var color: Color
    var title: String
    var value: String
    var caption: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                if let caption {
                    Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .card()
    }
}

extension View {
    func card() -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke))
    }
}
