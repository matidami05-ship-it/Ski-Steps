import SwiftUI
import Charts

// MARK: - Model

/// Fitness (CTL), Fatigue (ATL) and Form (TSB) from workout training load.
/// Each workout's load is a heart-rate TRIMP score; workouts without heart
/// rate fall back to an estimate from duration.
struct TrainingLoad {
    struct Day: Identifiable {
        var date: Date
        var load: Double
        var fitness: Double
        var fatigue: Double
        var form: Double
        var projected: Bool
        var id: Date { date }
    }

    var days: [Day]            // last 90 days + 14 projected
    var fitness: Double
    var fatigue: Double
    var form: Double
    var focusAnaerobic: Double // last 28 days
    var focusHigh: Double
    var focusLow: Double

    var ratio: Double { fitness > 0.5 ? fatigue / fitness : 0 }

    static let empty = TrainingLoad(days: [], fitness: 0, fatigue: 0, form: 0,
                                    focusAnaerobic: 0, focusHigh: 0, focusLow: 0)

    static func compute(workouts: [WorkoutSummary], restingHR: Double, maxHR: Double) -> TrainingLoad {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -180, to: today)!
        let focusStart = cal.date(byAdding: .day, value: -27, to: today)!

        var loads: [Date: Double] = [:]
        var anaerobic = 0.0, high = 0.0, low = 0.0
        for w in workouts where w.start >= start {
            let minutes = w.duration / 60
            var load: Double
            var intensity: Double? = nil
            if w.averageHeartRate > 0, maxHR > restingHR {
                let hrr = min(max((w.averageHeartRate - restingHR) / (maxHR - restingHR), 0), 1)
                load = minutes * hrr * 0.64 * exp(1.92 * hrr)
                intensity = hrr
            } else if w.energy > 0 {
                load = w.energy / 8
            } else {
                load = minutes * 0.6
            }
            load = min(load, 600)
            let day = cal.startOfDay(for: w.start)
            loads[day, default: 0] += load
            if w.start >= focusStart {
                switch intensity ?? 0.5 {
                case 0.8...: anaerobic += load
                case 0.6..<0.8: high += load
                default: low += load
                }
            }
        }

        var days: [Day] = []
        var ctl = 0.0, atl = 0.0
        var d = start
        let showFrom = cal.date(byAdding: .day, value: -89, to: today)!
        let projectTo = cal.date(byAdding: .day, value: 14, to: today)!
        while d <= projectTo {
            let projected = d > today
            let load = projected ? 0 : (loads[d] ?? 0)
            ctl += (load - ctl) / 42
            atl += (load - atl) / 7
            if d >= showFrom {
                days.append(Day(date: d, load: load, fitness: ctl, fatigue: atl, form: ctl - atl, projected: projected))
            }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        let now = days.last { !$0.projected }
        return TrainingLoad(days: days, fitness: now?.fitness ?? 0, fatigue: now?.fatigue ?? 0, form: now?.form ?? 0,
                            focusAnaerobic: anaerobic, focusHigh: high, focusLow: low)
    }
}

// MARK: - View

struct InsightsView: View {
    @EnvironmentObject private var health: HealthStore
    @State private var showSettings = false
    @AppStorage("dailyGoal") private var stepGoal: Double = 10_000
    @AppStorage("useMetric") private var useMetric = false
    @State private var selected: Date?

    private var t: TrainingLoad { health.training }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AICoachCard(kind: "overall", title: "AI Coach", icon: "sparkles", color: Theme.accent,
                                autoRefresh: true, prompt: { health.overallPrompt() })
                    sectionTitle("Fitness")
                    fitnessCard
                    ratioCard
                    focusCard
                    sectionTitle("Goals")
                    goalsCard
                    Text("Training load uses your workouts' heart rate (TRIMP), with your resting heart rate of \(Int(health.restingHR)) bpm and max of \(Int(health.maxHR)) bpm. Workouts without heart rate are estimated from calories or time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .refreshable { await health.refresh() }
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.title2.weight(.bold)).padding(.top, 4)
    }

    // MARK: Fitness chart

    private var shownDay: TrainingLoad.Day? {
        guard let selected else { return nil }
        return t.days.first { Calendar.current.isDate($0.date, inSameDayAs: selected) }
    }

    private var fitnessCard: some View {
        let day = shownDay
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Fitness", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundStyle(Theme.active)
                Spacer()
                if let day {
                    Text(day.date.formatted(.dateTime.month(.abbreviated).day()) + (day.projected ? " (projected)" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 0) {
                loadStat(day?.fitness ?? t.fitness, "Fitness (CTL)", Theme.accent2)
                loadStat(day?.fatigue ?? t.fatigue, "Fatigue (ATL)", Theme.calorie)
                loadStat(day?.form ?? t.form, "Form (TSB)", Theme.accent)
            }
            Chart {
                ForEach(t.days) { d in
                    AreaMark(x: .value("Day", d.date, unit: .day), y: .value("Fitness", d.fitness))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent2.opacity(0.35), Theme.accent2.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                }
                series(\.fitness, "Fitness", Theme.accent2)
                series(\.fatigue, "Fatigue", Theme.calorie)
                series(\.form, "Form", Theme.accent)
                RuleMark(x: .value("Today", Calendar.current.startOfDay(for: .now), unit: .day))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                if let day {
                    RuleMark(x: .value("Selected", day.date, unit: .day))
                        .foregroundStyle(Theme.gold.opacity(0.8))
                }
            }
            .chartXSelection(value: $selected)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel()
                }
            }
            .frame(height: 220)
        }
        .padding(16)
        .card()
    }

    @ChartContentBuilder
    private func series(_ key: KeyPath<TrainingLoad.Day, Double>, _ name: String, _ color: Color) -> some ChartContent {
        let today = Calendar.current.startOfDay(for: .now)
        ForEach(t.days.filter { !$0.projected }) { d in
            LineMark(x: .value("Day", d.date, unit: .day), y: .value(name, d[keyPath: key]), series: .value("S", name))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)
        }
        ForEach(t.days.filter { $0.projected || Calendar.current.isDate($0.date, inSameDayAs: today) }) { d in
            LineMark(x: .value("Day", d.date, unit: .day), y: .value(name, d[keyPath: key]), series: .value("S", name + " projected"))
                .foregroundStyle(color.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .interpolationMethod(.monotone)
        }
    }

    private func loadStat(_ v: Double, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text("\(Int(v.rounded()))").font(.title2.weight(.bold).monospacedDigit())
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Ratio

    private var ratioZone: (String, Color, String) {
        let r = t.ratio
        if t.fitness < 0.5 { return ("No data", .gray, "Record workouts with heart rate (Apple Watch) to build your training load.") }
        switch r {
        case ..<0.8: return ("Low", Theme.accent2, "Your short-term training load (ATL) is lower than your long-term load (CTL). You're recovering or detraining.")
        case 0.8..<1.3: return ("Optimal", Theme.accent, "You're building fitness at a healthy pace.")
        case 1.3..<1.5: return ("High", Theme.active, "You're training harder than usual. Watch for fatigue.")
        default: return ("Very high", Theme.calorie, "Big jump in training load — higher injury risk. Consider extra rest.")
        }
    }

    private var ratioCard: some View {
        let zone = ratioZone
        let maxR = 2.0
        return VStack(alignment: .leading, spacing: 12) {
            Text("Training Load Ratio").font(.headline).foregroundStyle(Theme.active)
            Text(zone.0).font(.title3.weight(.bold)).foregroundStyle(zone.1).frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                Text(String(format: "%.1f", t.ratio)).font(.headline.monospacedDigit()).foregroundStyle(zone.1)
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            Theme.accent2.frame(width: w * 0.8 / maxR)
                            Theme.accent.frame(width: w * 0.5 / maxR)
                            Theme.active.frame(width: w * 0.2 / maxR)
                            Theme.calorie
                        }
                        .clipShape(Capsule())
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(zone.1, lineWidth: 4))
                            .offset(x: min(max(w * t.ratio / maxR - 9, -2), w - 16))
                    }
                }
                .frame(height: 18)
            }
            Text(zone.2).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(16)
        .card()
    }

    // MARK: Focus

    private var focusCard: some View {
        let total = t.focusAnaerobic + t.focusHigh + t.focusLow
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -27, to: .now)!
        return VStack(alignment: .leading, spacing: 12) {
            Text("Training Load Focus").font(.headline).foregroundStyle(Theme.active)
            Text("\(from.formatted(.dateTime.month(.abbreviated).day())) – \(Date.now.formatted(.dateTime.month(.abbreviated).day().year()))")
                .font(.subheadline).foregroundStyle(.secondary)
            focusRow("Anaerobic", t.focusAnaerobic, total, Theme.calorie)
            focusRow("High Aerobic", t.focusHigh, total, Theme.active)
            focusRow("Low Aerobic", t.focusLow, total, Theme.accent2)
        }
        .padding(16)
        .card()
    }

    private func focusRow(_ name: String, _ v: Double, _ total: Double, _ color: Color) -> some View {
        let pct = total > 0 ? v / total : 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text("\(Int(v.rounded())) · \(Int((pct * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            GoalBar(progress: pct, color: color, height: 10)
        }
    }

    // MARK: Goals

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Last 7 days").font(.headline)
                Spacer()
                Text("days goal met").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Metric.allCases) { m in
                let days = Array((health.history[m] ?? []).suffix(7))
                let goal = m.goal()
                let met = days.filter { $0.value >= goal }.count
                let avg = days.isEmpty ? 0 : days.map(\.value).reduce(0, +) / Double(days.count)
                HStack(spacing: 12) {
                    Image(systemName: m.icon)
                        .foregroundStyle(m.color)
                        .frame(width: 34, height: 34)
                        .background(m.color.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(m.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(met)/7").font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(met >= 5 ? Theme.gold : m.color)
                        }
                        HStack(spacing: 4) {
                            ForEach(days) { d in
                                Capsule()
                                    .fill(d.value >= goal ? m.color : Color.white.opacity(0.12))
                                    .frame(height: 6)
                            }
                        }
                        Text("Avg \(m.text(m.display(avg, useMetric: useMetric))) \(m.unit(useMetric: useMetric)) / day · streak \(health.streak(m, goal: goal))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .card()
    }
}
