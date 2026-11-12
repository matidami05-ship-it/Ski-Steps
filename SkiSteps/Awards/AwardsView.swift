import SwiftUI

/// A medal: gradient circle with a symbol; locked ones are grey with a progress ring.
struct AwardBadge: View {
    let award: Award
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            if award.isEarned {
                Circle()
                    .fill(LinearGradient(colors: award.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: award.colors[0].opacity(0.45), radius: size * 0.12)
                Circle()
                    .strokeBorder(.white.opacity(0.55), lineWidth: size * 0.04)
                    .padding(size * 0.07)
                Image(systemName: award.icon)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            } else {
                Circle().fill(Color.white.opacity(0.06))
                Circle()
                    .trim(from: 0, to: award.progress)
                    .stroke(award.colors[0].opacity(0.8), style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(size * 0.03)
                Image(systemName: award.icon)
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
                if award.progress < 1 {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .offset(y: size * 0.3)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct AwardsView: View {
    @EnvironmentObject private var health: HealthStore
    @State private var shown: Award?
    @State private var filter: Award.Category?

    private var earned: [Award] { health.awards.filter(\.isEarned) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary
                if let next = nextUp { nextCard(next) }
                categoryChips
                ForEach(Award.Category.allCases.filter { filter == nil || $0 == filter }) { cat in
                    let items = health.awards.filter { $0.category == cat }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(cat.rawValue).font(.title3.weight(.bold))
                                Spacer()
                                Text("\(items.filter(\.isEarned).count)/\(items.count)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
                                ForEach(items) { a in
                                    Button { shown = a } label: { tile(a) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Awards")
        .refreshable { await health.refresh() }
        .sheet(item: $shown) { a in
            AwardDetailView(award: a).presentationDetents([.medium, .large])
        }
        .onAppear { UserDefaults.standard.removeObject(forKey: "awardsNew") }
    }

    private var summary: some View {
        let total = health.awards.count
        return HStack(spacing: 16) {
            ZStack {
                ProgressRing(progress: total > 0 ? Double(earned.count) / Double(total) : 0, lineWidth: 10,
                             colors: [Theme.gold, Theme.active])
                VStack(spacing: 0) {
                    Text("\(earned.count)").font(.title.weight(.bold))
                    Text("of \(total)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                let pts = AwardsEngine.points(health.awards)
                let lv = AwardLevel.info(points: pts)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Level \(lv.level)").font(.headline)
                    Text(AwardLevel.title(lv.level)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                }
                GoalBar(progress: Double(lv.into) / Double(lv.needed), color: Theme.gold)
                Text("\(pts) pts · \(lv.needed - lv.into) to level \(lv.level + 1)")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: -10) {
                    ForEach(earned.sorted { ($0.earned ?? .distantPast) > ($1.earned ?? .distantPast) }.prefix(5)) { a in
                        AwardBadge(award: a, size: 34).overlay(Circle().stroke(Theme.bgTop, lineWidth: 2))
                    }
                }
                Text(earned.isEmpty ? "Your first badge is close — keep moving!" : "Latest: \(latest?.title ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card()
    }

    private var latest: Award? { earned.max { ($0.earned ?? .distantPast) < ($1.earned ?? .distantPast) } }

    /// The locked award you're closest to.
    private var nextUp: Award? {
        health.awards.filter { !$0.isEarned && $0.progress > 0 && $0.category != .monthly }.max { $0.progress < $1.progress }
    }

    private func nextCard(_ a: Award) -> some View {
        Button { shown = a } label: {
            HStack(spacing: 14) {
                AwardBadge(award: a, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Up next").font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
                    Text(a.title).font(.headline)
                    GoalBar(progress: a.progress, color: a.colors[0])
                    Text(a.progressText).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .card()
        }
        .buttonStyle(.plain)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", filter == nil) { filter = nil }
                ForEach(Award.Category.allCases) { c in chip(c.rawValue, filter == c) { filter = c } }
            }
        }
    }

    private func chip(_ t: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Text(t).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(on ? .black : .primary)
                .background(on ? Theme.gold : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func tile(_ a: Award) -> some View {
        VStack(spacing: 6) {
            AwardBadge(award: a)
            Text(a.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(a.isEarned ? .primary : .secondary)
            if a.isEarned {
                Text(a.count > 1 ? "×\(a.count)" : a.earned!.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2).foregroundStyle(a.colors[0])
            } else {
                Text("\(Int((a.progress * 100).rounded()))%").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct AwardDetailView: View {
    let award: Award
    @Environment(\.displayScale) private var scale

    var body: some View {
        VStack(spacing: 16) {
            AwardBadge(award: award, size: 140)
                .padding(.top, 30)
            Text(award.title).font(.title.weight(.bold))
            Text(award.detail).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 30)
            Text("+\(award.tier.points) pts").font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
            if let date = award.earned {
                Label("Earned \(date.formatted(date: .long, time: .omitted))", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(award.colors[0])
                if award.count > 1 {
                    Text("Achieved \(award.count) times").font(.caption).foregroundStyle(.secondary)
                }
                if let image = shareImage {
                    ShareLink(item: image, preview: SharePreview(award.title, image: image)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline).foregroundStyle(.black)
                            .padding(.horizontal, 28).padding(.vertical, 12)
                            .background(award.colors[0], in: Capsule())
                    }
                }
            } else {
                VStack(spacing: 6) {
                    GoalBar(progress: award.progress, color: award.colors[0], height: 10)
                    Text(award.progressText).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @MainActor
    private var shareImage: Image? {
        let card = VStack(spacing: 14) {
            AwardBadge(award: award, size: 180)
            Text(award.title).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(award.detail).font(.title3).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            if let d = award.earned {
                Text(d.formatted(date: .long, time: .omitted)).font(.headline).foregroundStyle(award.colors[0])
            }
            Text("Ski Steps").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.5)).padding(.top, 8)
        }
        .padding(40)
        .frame(width: 600)
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom))
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

/// Card on the Today tab.
struct AwardsTodayCard: View {
    @EnvironmentObject private var health: HealthStore

    var body: some View {
        let earned = health.awards.filter(\.isEarned)
        let newIDs = Set(UserDefaults.standard.stringArray(forKey: "awardsNew") ?? [])
        let fresh = earned.filter { newIDs.contains($0.id) }
        let next = health.awards.filter { !$0.isEarned && $0.progress > 0 && $0.category != .monthly }
            .max { $0.progress < $1.progress }
        let month = health.awards.first { $0.category == .monthly }
        NavigationLink {
            AwardsView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Awards", systemImage: "medal.fill").font(.headline).foregroundStyle(Theme.gold)
                    Text("Lv \(AwardLevel.info(points: AwardsEngine.points(health.awards)).level)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.gold.opacity(0.2), in: Capsule())
                    if !fresh.isEmpty {
                        Text("\(fresh.count) NEW").font(.caption2.weight(.heavy))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.calorie, in: Capsule())
                    }
                    Spacer()
                    Text("\(earned.count) of \(health.awards.count)").font(.subheadline).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    if let a = fresh.first ?? next {
                        AwardBadge(award: a, size: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(a.isEarned ? "New: \(a.title)" : "Next: \(a.title)").font(.subheadline.weight(.semibold))
                            if !a.isEarned {
                                GoalBar(progress: a.progress, color: a.colors[0])
                            }
                            Text(a.isEarned ? a.detail : a.progressText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                if let m = month {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(m.title).font(.caption.weight(.semibold))
                            Spacer()
                            Text(m.isEarned ? "Complete 🎉" : "\(Int((m.progress * 100).rounded()))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        GoalBar(progress: m.progress, color: Theme.accent)
                    }
                }
            }
            .padding(16)
            .card()
        }
        .buttonStyle(.plain)
    }
}
