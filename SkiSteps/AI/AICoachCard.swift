import SwiftUI

/// The AI Coach box: headline, insight rows and a "try this week" checklist,
/// with a glowing animated border while it thinks.
struct AICoachCard: View {
    let kind: String
    let title: String
    let icon: String
    let color: Color
    var instructions: String = AICoach.instructions
    /// Refresh by itself when shown (skipped if updated in the last 15 minutes).
    var autoRefresh: Bool = false
    let prompt: () -> String

    @ObservedObject private var coach = AICoach.shared
    @EnvironmentObject private var health: HealthStore
    @State private var showSettings = false
    @State private var spin = false

    private var loading: Bool { coach.loading.contains(kind) }
    private var result: AICoach.Result? { coach.results[kind] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if loading && result == nil {
                skeleton
            } else if let r = result {
                CoachContent(text: r.text, color: color)
                    .opacity(loading ? 0.45 : 1)
                    .animation(.easeInOut, value: loading)
            } else if coach.active != nil {
                Text("Your personal summary will appear here, with patterns from your data and tips for the week ahead.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            if let err = coach.errors[kind] {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.yellow)
            }

            if coach.active == nil {
                setupPrompt
            } else if result == nil && !loading && !autoRefresh {
                Button { run() } label: {
                    Label("Analyze", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .leading, endPoint: .trailing),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if let r = result {
                Text("\(r.provider) · general wellness info, not medical advice")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.bgTop)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.20), color.opacity(0.04), Theme.accent2.opacity(0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        )
        .overlay(border)
        .shadow(color: color.opacity(loading ? 0.35 : 0.15), radius: loading ? 18 : 10)
        .animation(.easeInOut(duration: 0.4), value: loading)
        .task(id: kind) { autoRun() }
        .onChange(of: health.lastUpdated) { _, _ in autoRun() }
        .sheet(isPresented: $showSettings) {
            NavigationStack { AISettingsView() }
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: [color, Theme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: loading)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if coach.active != nil {
                Button { run() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .rotationEffect(.degrees(loading ? 360 : 0))
                        .animation(loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: loading)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(loading)
                .accessibilityLabel("Refresh analysis")
            }
        }
    }

    private var subtitle: String {
        if loading { return "Reading your data…" }
        if let r = result { return "Updated " + r.date.formatted(.relative(presentation: .named)) }
        return coach.active == nil ? "Not set up" : "Ready"
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(
                AngularGradient(colors: [color, Theme.accent2, color.opacity(0.2), Theme.gold.opacity(0.6), color],
                                center: .center, angle: .degrees(spin ? 360 : 0)),
                lineWidth: loading ? 2 : 1.2
            )
            .opacity(loading ? 1 : 0.55)
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { spin = true }
            }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([0.85, 1.0, 0.92, 0.7, 0.95, 0.6], id: \.self) { w in
                GeometryReader { geo in
                    Capsule().fill(Color.white.opacity(0.08))
                        .frame(width: geo.size.width * w, height: 10)
                        .overlay(alignment: .leading) {
                            Capsule().fill(LinearGradient(colors: [.clear, color.opacity(0.35), .clear],
                                                          startPoint: .leading, endPoint: .trailing))
                                .frame(width: 90, height: 10)
                                .offset(x: spin ? geo.size.width : -90)
                        }
                        .clipShape(Capsule())
                }
                .frame(height: 10)
            }
        }
        .padding(.vertical, 4)
    }

    private var setupPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Turn on AI Coach to get a personal summary of your data.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { showSettings = true } label: {
                Label("Set up AI Coach", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(color, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    private func run() {
        Task { await coach.analyze(kind, prompt: prompt(), instructions: instructions) }
    }

    private func autoRun() {
        guard autoRefresh, coach.active != nil, !loading, health.lastUpdated != nil else { return }
        if let r = result, Date().timeIntervalSince(r.date) < 15 * 60 { return }
        run()
    }
}

/// Lays out the coach's markdown as a headline, insight rows and a checklist.
struct CoachContent: View {
    let text: String
    let color: Color

    private struct Parsed {
        var headline: String?
        var paragraphs: [String] = []
        var insights: [String] = []
        var tryTitle: String?
        var tries: [String] = []
    }

    private var parsed: Parsed {
        var p = Parsed()
        var inTry = false
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let bullet = line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ")
            let body = bullet ? String(line.dropFirst(2)) : line.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
            let plain = body.replacingOccurrences(of: "**", with: "").lowercased()
            if !bullet && (plain.hasPrefix("this week") || plain.hasPrefix("try") || plain.hasPrefix("next week")) {
                inTry = true
                p.tryTitle = body.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                continue
            }
            if bullet {
                if inTry { p.tries.append(body) } else { p.insights.append(body) }
            } else if p.headline == nil && p.insights.isEmpty && p.paragraphs.isEmpty && body.count < 160 && line.contains("**") {
                p.headline = body.replacingOccurrences(of: "**", with: "")
            } else if inTry {
                p.tries.append(body)
            } else {
                p.paragraphs.append(body)
            }
        }
        return p
    }

    var body: some View {
        let p = parsed
        VStack(alignment: .leading, spacing: 12) {
            if let h = p.headline {
                Text(h)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(p.paragraphs.enumerated()), id: \.offset) { _, para in
                inline(para).font(.subheadline).foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !p.insights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(p.insights.enumerated()), id: \.offset) { i, item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: insightIcon(i))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(color)
                                .frame(width: 24, height: 24)
                                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            inline(item).font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !p.tries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(p.tryTitle ?? "This week, try", systemImage: "target")
                        .font(.caption.weight(.heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.gold)
                    ForEach(Array(p.tries.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle")
                                .font(.subheadline)
                                .foregroundStyle(Theme.gold.opacity(0.8))
                            inline(item).font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.gold.opacity(0.25)))
            }
        }
    }

    private func insightIcon(_ i: Int) -> String {
        ["chart.line.uptrend.xyaxis", "lightbulb.fill", "heart.fill", "flame.fill", "moon.fill", "figure.walk"][i % 6]
    }

    private func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s) { return Text(a) }
        return Text(s)
    }
}
