import SwiftUI
import Charts

struct SleepView: View {
    @EnvironmentObject private var health: HealthStore
    @AppStorage("sleepGoal") private var goalHours: Double = 8
    @State private var selected: Date?
    @State private var span = 7

    private var nights: [SleepNight] { health.nights }

    private var shown: SleepNight? {
        if let selected, let n = nights.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
            return n
        }
        return nights.last
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let night = shown {
                        scoreCard(night)
                        stagesCard(night)
                    } else {
                        emptyCard
                    }
                    if !nights.isEmpty {
                        trendCard
                        habitsCard
                    }
                    AICoachCard(kind: "sleep", title: "AI Sleep Analysis", icon: "moon.stars.fill",
                                color: SleepStage.deep.color, prompt: { health.sleepPrompt() })
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(
                LinearGradient(colors: [Color(red: 0.05, green: 0.04, blue: 0.16), Theme.bgTop],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            )
            .navigationTitle("Sleep")
            .refreshable { await health.refresh() }
        }
    }

    // MARK: Score

    private func scoreCard(_ n: SleepNight) -> some View {
        let score = n.score(goalHours: goalHours, usualBedtime: nights.usualBedtime(before: n))
        let isLast = n.id == nights.last?.id
        return VStack(spacing: 14) {
            HStack {
                Text(isLast ? "Last night" : n.day.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.headline)
                Spacer()
                Text(n.source).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: Double(score) / 100, lineWidth: 12,
                                 colors: [SleepStage.deep.color, SleepStage.rem.color])
                    VStack(spacing: 0) {
                        Text("\(score)").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("score").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Asleep").font(.caption).foregroundStyle(.secondary)
                        Text(SleepFmt.hours(n.asleep)).font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    GoalBar(progress: n.asleep / (goalHours * 3600), color: SleepStage.rem.color)
                    Text("Goal \(SleepFmt.hours(goalHours * 3600)) · in bed \(SleepFmt.hours(n.inBed))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 0) {
                miniStat("bed.double.fill", n.bedtime.formatted(date: .omitted, time: .shortened), "Bedtime")
                miniStat("sun.max.fill", n.wake.formatted(date: .omitted, time: .shortened), "Woke up")
                miniStat("percent", "\(Int((n.efficiency * 100).rounded()))%", "Efficiency")
            }
        }
        .padding(16)
        .card()
    }

    private func miniStat(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundStyle(SleepStage.rem.color)
            Text(value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Stages

    private func stagesCard(_ n: SleepNight) -> some View {
        let stages: [SleepStage] = n.hasStages ? [.awake, .rem, .core, .deep] : [.awake, .asleep]
        return VStack(alignment: .leading, spacing: 12) {
            Text(n.hasStages ? "Sleep stages" : "Sleep timeline").font(.headline)
            Chart(n.segments) { s in
                RectangleMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end),
                              y: .value("Stage", s.stage.title))
                    .foregroundStyle(s.stage.color)
                    .cornerRadius(3)
            }
            .chartYScale(domain: stages.map(\.title))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: n.hasStages ? 170 : 100)

            VStack(spacing: 8) {
                ForEach(stages) { st in
                    let t = n.total(st)
                    let total = max(n.segments.reduce(0) { $0 + $1.duration }, 1)
                    HStack(spacing: 10) {
                        Circle().fill(st.color).frame(width: 10, height: 10)
                        Text(st.title).font(.subheadline).frame(width: 60, alignment: .leading)
                        GoalBar(progress: t / total, color: st.color, height: 7)
                        Text(SleepFmt.hours(t)).font(.subheadline.monospacedDigit()).frame(width: 64, alignment: .trailing)
                        Text("\(Int((t / total * 100).rounded()))%")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                    }
                }
            }
            if !n.hasStages {
                Text("Sleep stages (Deep, Core, REM) appear when they come from a newer Apple Watch or a ring like Oura.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .card()
    }

    // MARK: Trend

    private var trendCard: some View {
        let recent = Array(nights.suffix(span))
        let avg = recent.isEmpty ? 0 : recent.map(\.asleep).reduce(0, +) / Double(recent.count)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Average asleep").font(.caption).foregroundStyle(.secondary)
                    Text(SleepFmt.hours(avg)).font(.title2.weight(.bold))
                }
                Spacer()
                Picker("Span", selection: $span) {
                    Text("7 nights").tag(7)
                    Text("30 nights").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            Chart {
                ForEach(recent) { n in
                    BarMark(x: .value("Night", n.day, unit: .day), y: .value("Hours", n.asleep / 3600))
                        .foregroundStyle(n.asleep >= goalHours * 3600 ? SleepStage.rem.color : SleepStage.core.color.opacity(0.7))
                        .cornerRadius(span == 7 ? 6 : 2)
                        .opacity(selected == nil || Calendar.current.isDate(n.day, inSameDayAs: selected!) ? 1 : 0.4)
                }
                RuleMark(y: .value("Goal", goalHours))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.gold)
            }
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h))h") } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: span == 7 ? 1 : 7)) { _ in
                    AxisValueLabel(format: span == 7 ? .dateTime.weekday(.narrow) : .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 180)
            Text("Tap a bar to see that night above.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .card()
    }

    // MARK: Habits

    private var habitsCard: some View {
        let recent = Array(nights.suffix(14))
        let bed = recent.map(\.bedtimeMinutes)
        let avgBed = bed.reduce(0, +) / Double(max(bed.count, 1))
        let spread = bed.isEmpty ? 0 : sqrt(bed.map { pow($0 - avgBed, 2) }.reduce(0, +) / Double(bed.count))
        let wakeMins = recent.map { n -> Double in
            let cal = Calendar.current
            return n.wake.timeIntervalSince(cal.startOfDay(for: n.wake)) / 60
        }
        let avgWake = wakeMins.reduce(0, +) / Double(max(wakeMins.count, 1))
        let wakeText = Calendar.current.startOfDay(for: .now).addingTimeInterval(avgWake * 60)
            .formatted(date: .omitted, time: .shortened)
        let met = recent.filter { $0.asleep >= goalHours * 3600 }.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 2 weeks").font(.headline)
            HStack(spacing: 0) {
                miniStat("moon.fill", SleepFmt.clockTime(minutesAfter6pm: avgBed), "Avg bedtime")
                miniStat("alarm.fill", wakeText, "Avg wake")
                miniStat("checkmark.circle.fill", "\(met)/\(recent.count)", "Goal met")
            }
            HStack(spacing: 8) {
                Image(systemName: spread < 30 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(spread < 30 ? Theme.accent : Theme.gold)
                Text(spread < 30
                     ? "Consistent bedtime — within about \(Int(spread)) minutes most nights."
                     : "Your bedtime varies by about \(Int(spread)) minutes. A steadier schedule usually means better sleep.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .card()
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "bed.double.fill").font(.largeTitle).foregroundStyle(SleepStage.rem.color)
            Text("No sleep data yet").font(.headline)
            Text("Wear your Apple Watch to bed with Sleep Focus on, set a sleep schedule in the Health app, or use a ring like Oura. Sleep appears here once it's in Apple Health.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("If you already track sleep, check Settings › Check Health connection and make sure Sleep is turned on for Ski Steps.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .card()
    }
}

// MARK: - AI coach card

struct AICoachCard: View {
    let kind: String
    let title: String
    let icon: String
    let color: Color
    let prompt: () -> String
    @ObservedObject private var coach = AICoach.shared
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
                Spacer()
                if let r = coach.results[kind] {
                    Text(r.date.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if coach.loading.contains(kind) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Analyzing your data…").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let r = coach.results[kind] {
                MarkdownText(r.text)
                Text("By \(r.provider) · general wellness info, not medical advice")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Get a personal summary of your recent data, with patterns and tips for the week ahead.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            if let err = coach.errors[kind] {
                Text(err).font(.footnote).foregroundStyle(.yellow)
            }

            if coach.active == nil {
                Button {
                    showSettings = true
                } label: {
                    Label("Set up AI Coach", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(color, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await coach.analyze(kind, prompt: prompt()) }
                } label: {
                    Label(coach.results[kind] == nil ? "Analyze" : "Refresh analysis", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(color, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(coach.loading.contains(kind))
            }
        }
        .padding(16)
        .card()
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(color.opacity(0.35)))
        .sheet(isPresented: $showSettings) {
            NavigationStack { AISettingsView() }
                .presentationDetents([.medium, .large])
        }
    }
}

/// Renders the coach's markdown: bold/italics inline, "- " lines as bullets.
struct MarkdownText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    EmptyView()
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        inline(String(line.dropFirst(2)))
                    }
                } else if line.hasPrefix("#") {
                    inline(line.drop { $0 == "#" || $0 == " " }.description).font(.headline)
                } else {
                    inline(line)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s) { return Text(a) }
        return Text(s)
    }
}

// MARK: - AI settings

struct AISettingsView: View {
    @ObservedObject private var coach = AICoach.shared
    @AppStorage("aiProvider") private var provider: AICoach.Provider = .auto
    @AppStorage("claudeModel") private var model = "claude-sonnet-5-5"
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var savedKey = false

    var body: some View {
        Form {
            Section {
                Picker("Use", selection: $provider) {
                    ForEach(AICoach.Provider.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Apple Intelligence", value: coach.appleStatus)
                LabeledContent("Claude", value: coach.hasClaudeKey ? "API key saved" : "No API key")
                LabeledContent("Now using", value: coach.active?.title ?? "Not set up")
            } header: {
                Text("AI Coach")
            } footer: {
                Text("Automatic uses Apple Intelligence when your iPhone supports it (free, and your data stays on the phone). Otherwise it uses Claude with your own API key.")
            }

            Section {
                SecureField(coach.hasClaudeKey ? "Saved — paste a new key to replace" : "sk-ant-…", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(savedKey ? "Saved" : "Save Key") {
                    coach.setClaudeKey(key)
                    key = ""
                    savedKey = true
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                if coach.hasClaudeKey {
                    Button("Remove Key", role: .destructive) { coach.setClaudeKey("") }
                }
                Picker("Model", selection: $model) {
                    Text("Claude Sonnet 5.5 (best)").tag("claude-sonnet-5-5")
                    Text("Claude Haiku 5.5 (fastest, cheapest)").tag("claude-haiku-5-5")
                }
                Button("Get an API key") {
                    if let url = URL(string: "https://console.anthropic.com/settings/keys") { openURL(url) }
                }
            } header: {
                Text("Claude")
            } footer: {
                Text("With Claude, a text summary of your recent steps, workouts and sleep is sent to Anthropic each time you tap Analyze. The key is stored in your iPhone's Keychain. API use is billed by Anthropic.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("AI Coach")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}
