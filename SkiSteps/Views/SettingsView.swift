import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var health: HealthStore
    @Environment(\.openURL) private var openURL
    @AppStorage("dailyGoal") private var goal: Double = 10_000
    @AppStorage("useMetric") private var metric = false
    @AppStorage("goalAlerts") private var goalAlerts = true

    private let presets: [Double] = [5_000, 7_500, 10_000, 12_500, 15_000]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goal, in: 1_000...50_000, step: 500) {
                        HStack {
                            Text("Steps")
                            Spacer()
                            Text(Fmt.steps(goal))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Theme.accent)
                        }
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
                } header: {
                    Text("Daily goal")
                }

                Section("Notifications") {
                    Toggle("Alert me when I hit my goal", isOn: $goalAlerts)
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
            .onChange(of: metric) { _, _ in health.settingsChanged() }
        }
    }
}
