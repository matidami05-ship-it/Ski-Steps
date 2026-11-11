import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var health: HealthStore
    @Environment(\.openURL) private var openURL
    @AppStorage("dailyGoal") private var goal: Double = 10_000
    @AppStorage("useMetric") private var metric = false
    @AppStorage("goalAlerts") private var goalAlerts = true
    @AppStorage("distanceGoal") private var distanceGoal: Double = Metric.distance.defaultGoal
    @AppStorage("calorieGoal") private var calorieGoal: Double = Metric.calories.defaultGoal
    @AppStorage("activeGoal") private var activeGoal: Double = Metric.active.defaultGoal
    @AppStorage("autoDetectRuns") private var autoDetect = true
    @AppStorage("runVoice") private var runVoice = true

    private let presets: [Double] = [5_000, 7_500, 10_000, 12_500, 15_000]

    /// Distance goal shown in miles/km, stored in meters.
    private var distanceDisplay: Binding<Double> {
        let unit = metric ? 1000.0 : 1609.344
        return Binding(
            get: { (distanceGoal / unit * 2).rounded() / 2 },
            set: { distanceGoal = $0 * unit }
        )
    }

    private func goalLabel(_ m: Metric, _ value: String) -> some View {
        HStack {
            Label(m.title, systemImage: m.icon)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(m.color)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goal, in: 1_000...50_000, step: 500) {
                        goalLabel(.steps, Fmt.steps(goal))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.self) { value in
                                Button(Fmt.compact(value)) { goal = value }
                                    .buttonStyle(.bordered)
                                    .tint(goal == value ? Theme.accent : .gray)
                            }
                        }
                    }
                    Stepper(value: distanceDisplay, in: 0.5...50, step: 0.5) {
                        goalLabel(.distance, "\(Metric.distance.text(distanceDisplay.wrappedValue)) \(Fmt.distanceUnit(metric))")
                    }
                    Stepper(value: $calorieGoal, in: 50...3_000, step: 50) {
                        goalLabel(.calories, "\(Fmt.steps(calorieGoal)) cal")
                    }
                    Stepper(value: $activeGoal, in: 5...300, step: 5) {
                        goalLabel(.active, "\(Fmt.minutes(activeGoal)) min")
                    }
                } header: {
                    Text("Daily goals")
                } footer: {
                    Text("Calories are active calories. Active time is exercise minutes from your iPhone and Apple Watch.")
                }

                Section {
                    Toggle("Detect runs automatically", isOn: $autoDetect)
                    Toggle("Spoken splits during runs", isOn: $runVoice)
                } header: {
                    Text("Workouts")
                } footer: {
                    Text("Ski Steps checks your iPhone's motion data for runs you didn't record and offers to save them. Swims and other workouts come from Apple Watch automatically.")
                }

                Section("Notifications") {
                    Toggle("Alert me when I hit a goal", isOn: $goalAlerts)
                }

                Section("Units") {
                    Picker("Distance", selection: $metric) {
                        Text("Miles").tag(false)
                        Text("Kilometers").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        if let url = URL(string: "x-apple-health://") { openURL(url) }
                    } label: {
                        Label("Open the Health app", systemImage: "heart.fill")
                    }
                    Button {
                        Task { await health.refresh() }
                    } label: {
                        Label("Refresh now", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("To change what Ski Steps can read, open Health › your profile picture › Apps › Ski Steps.")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    if let updated = health.lastUpdated {
                        HStack {
                            Text("Last updated")
                            Spacer()
                            Text(updated.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .onChange(of: goal) { _, _ in health.settingsChanged() }
            .onChange(of: distanceGoal) { _, _ in health.settingsChanged() }
            .onChange(of: calorieGoal) { _, _ in health.settingsChanged() }
            .onChange(of: activeGoal) { _, _ in health.settingsChanged() }
            .onChange(of: autoDetect) { _, _ in Task { await health.refresh() } }
            .onChange(of: metric) { _, _ in health.settingsChanged() }
        }
    }
}
