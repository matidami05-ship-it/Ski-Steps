import SwiftUI
import Charts

struct TodayView: View {
    @EnvironmentObject private var health: HealthStore
    @AppStorage("dailyGoal") private var goal: Double = 10_000
    @AppStorage("useMetric") private var metric = false
    @State private var celebrate = 0

    private var progress: Double { goal > 0 ? health.steps / goal : 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ringCard
                    statsRow
                    if !health.hasAnyData { noDataCard }
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
        HStack(spacing: 10) {
            StatTile(icon: "location.fill", color: Theme.accent2,
                     value: Fmt.distance(health.distance, metric: metric),
                     label: Fmt.distanceUnit(metric))
            StatTile(icon: "stairs", color: .orange,
                     value: Fmt.steps(health.flights), label: "floors")
            StatTile(icon: "flame.fill", color: .pink,
                     value: Fmt.steps(health.energy), label: "cal")
        }
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
