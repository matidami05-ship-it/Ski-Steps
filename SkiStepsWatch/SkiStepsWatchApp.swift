import SwiftUI
import WatchKit

@main
struct SkiStepsWatchApp: App {
    @StateObject private var health: WatchHealth
    @StateObject private var workouts: WorkoutManager
    @Environment(\.scenePhase) private var phase

    init() {
        let h = WatchHealth()
        _health = StateObject(wrappedValue: h)
        _workouts = StateObject(wrappedValue: WorkoutManager(store: h.store))
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(health)
                .environmentObject(workouts)
                .tint(Theme.accent)
                .task { await health.start() }
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await health.refresh() } }
                }
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject private var workouts: WorkoutManager

    var body: some View {
        if let result = workouts.result {
            SummaryView(result: result)
        } else if workouts.isActive {
            LiveWorkoutView()
        } else {
            NavigationStack {
                TabView {
                    WatchTodayView()
                    StartWorkoutView()
                }
                .tabViewStyle(.verticalPage)
            }
        }
    }
}

// MARK: - Today

struct WatchTodayView: View {
    @EnvironmentObject private var health: WatchHealth

    var body: some View {
        let _ = health.goalsVersion
        let goal = Metric.steps.goal()
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    ProgressRing(progress: goal > 0 ? health.steps / goal : 0, lineWidth: 12)
                    VStack(spacing: 0) {
                        Image(systemName: "figure.walk")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                        Text(Fmt.steps(health.steps))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("of \(Fmt.compact(goal))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 22)
                }
                .frame(width: 130, height: 130)

                ForEach([Metric.distance, .calories, .active]) { m in
                    let g = m.goal()
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: m.icon).font(.caption2).foregroundStyle(m.color)
                            Text(m.text(m.display(health.value(m), useMetric: health.useMetric)))
                                .font(.footnote.weight(.semibold).monospacedDigit())
                            Spacer()
                            Text("\(m.text(m.display(g, useMetric: health.useMetric))) \(m.unit(useMetric: health.useMetric))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        GoalBar(progress: g > 0 ? health.value(m) / g : 0, color: m.color, height: 5)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Today")
    }
}

// MARK: - Start

struct StartWorkoutView: View {
    @EnvironmentObject private var workouts: WorkoutManager

    var body: some View {
        List(WatchWorkout.allCases) { w in
            Button {
                workouts.start(w)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: w.icon)
                        .font(.title3)
                        .foregroundStyle(color(w))
                        .frame(width: 36, height: 36)
                        .background(color(w).opacity(0.2), in: Circle())
                    Text(w.title).font(.headline)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Workouts")
    }

    private func color(_ w: WatchWorkout) -> Color {
        switch w.kind {
        case .run: Theme.run
        case .walk: Theme.accent
        case .swim: Theme.accent2
        case .cycle: Theme.gold
        case .other: Theme.calorie
        }
    }
}

// MARK: - Live

struct LiveWorkoutView: View {
    @EnvironmentObject private var workouts: WorkoutManager
    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            controls.tag(0)
            metrics.tag(1)
            NowPlayingView().tag(2)
        }
        .tabViewStyle(.page)
    }

    private var useMetric: Bool { UserDefaults.standard.bool(forKey: "useMetric") }

    private var metrics: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.clock(workouts.elapsed(at: context.date)))
                    .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(workouts.isPaused ? Theme.gold : Theme.accent)
                if let w = workouts.current, w.kind != .other {
                    Text(distanceText(w))
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                }
                Text("\(Fmt.steps(workouts.energy)) CAL")
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.calorie)
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(workouts.heartRate > 0 ? "\(Int(workouts.heartRate))" : "--")
                    Text("BPM").font(.caption2).foregroundStyle(.secondary)
                }
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                if let w = workouts.current {
                    if w.kind == .swim {
                        Text("\(workouts.laps) LAPS").font(.headline).foregroundStyle(Theme.accent2)
                    } else if w.kind == .run || w.kind == .walk {
                        Text("\(Fmt.pace(seconds: workouts.elapsed(at: context.date), meters: workouts.distance, metric: useMetric)) /\(Fmt.distanceUnit(useMetric))")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.run)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(workouts.current?.title ?? "")
    }

    private func distanceText(_ w: WatchWorkout) -> String {
        if w.kind == .swim {
            return useMetric ? "\(Fmt.steps(workouts.distance)) M" : "\(Fmt.steps(workouts.distance / 0.9144)) YD"
        }
        return "\(Fmt.distance(workouts.distance, metric: useMetric)) \(Fmt.distanceUnit(useMetric).uppercased())"
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                controlButton(workouts.isPaused ? "Resume" : "Pause",
                              icon: workouts.isPaused ? "play.fill" : "pause.fill",
                              color: Theme.gold) { workouts.togglePause() }
                controlButton("End", icon: "xmark", color: .red) { workouts.end() }
            }
            if workouts.current?.kind == .swim {
                controlButton("Lock", icon: "drop.fill", color: Theme.accent2) {
                    WKInterfaceDevice.current().enableWaterLock()
                }
            }
        }
    }

    private func controlButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: icon).font(.title2.weight(.bold))
            }
            .tint(color)
            .buttonStyle(.bordered)
            .frame(width: 70, height: 50)
            Text(title).font(.caption2)
        }
    }
}

// MARK: - Summary

struct SummaryView: View {
    @EnvironmentObject private var workouts: WorkoutManager
    let result: WorkoutResult

    private var useMetric: Bool { UserDefaults.standard.bool(forKey: "useMetric") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label("Saved to Health", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
                Text(result.title).font(.headline)
                row("Time", Fmt.clock(result.duration), Theme.active)
                if result.distance > 0 {
                    row("Distance", result.kind == .swim
                        ? (useMetric ? "\(Fmt.steps(result.distance)) m" : "\(Fmt.steps(result.distance / 0.9144)) yd")
                        : "\(Fmt.distance(result.distance, metric: useMetric)) \(Fmt.distanceUnit(useMetric))",
                        Theme.accent2)
                }
                row("Calories", "\(Fmt.steps(result.energy)) cal", Theme.calorie)
                if result.averageHeartRate > 0 {
                    row("Avg heart rate", "\(Int(result.averageHeartRate)) bpm", .red)
                }
                if result.laps > 0 { row("Laps", "\(result.laps)", Theme.accent2) }
                Button("Done") { workouts.dismissSummary() }
                    .tint(Theme.accent)
                    .padding(.top, 6)
            }
        }
    }

    private func row(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
    }
}
