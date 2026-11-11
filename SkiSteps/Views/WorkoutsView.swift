import SwiftUI
import MapKit
import CoreLocation

struct WorkoutsView: View {
    @EnvironmentObject private var health: HealthStore
    @EnvironmentObject private var detector: RunDetector
    @AppStorage("useMetric") private var metric = false
    @State private var filter: WorkoutKind = .all
    @State private var showTracker = false
    @State private var savingRun: DetectedRun?
    @State private var errorText: String?

    private var kindsPresent: [WorkoutKind] {
        let present = Set(health.workouts.map(\.kind))
        return WorkoutKind.allCases.filter { $0 == .all || present.contains($0) }
    }

    private var shown: [WorkoutSummary] {
        filter == .all ? health.workouts : health.workouts.filter { $0.kind == filter }
    }

    private var thisWeek: [WorkoutSummary] {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return health.workouts.filter { $0.start >= start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    startRunCard
                    ForEach(detector.found) { run in detectedCard(run) }
                    weekCard
                    if kindsPresent.count > 2 { filterChips }
                    if shown.isEmpty {
                        emptyCard
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(shown) { w in
                                NavigationLink {
                                    WorkoutDetailView(summary: w)
                                } label: {
                                    WorkoutRow(summary: w, metric: metric)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    watchTip
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Workouts")
            .refreshable { await health.refresh() }
            .fullScreenCover(isPresented: $showTracker) {
                RunTrackerView()
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: Cards

    private var startRunCard: some View {
        Button {
            showTracker = true
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "figure.run")
                    .font(.system(size: 30, weight: .bold))
                    .frame(width: 60, height: 60)
                    .background(.white.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start a Run").font(.title3.weight(.bold))
                    Text("GPS route, pace and spoken splits")
                        .font(.subheadline)
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.headline)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(
                LinearGradient(colors: [Theme.run, Theme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func detectedCard(_ run: DetectedRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.gold)
                Text("Run detected").font(.headline)
                Spacer()
                Text(run.start.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                labeled("Distance", "\(Fmt.distance(run.meters, metric: metric)) \(Fmt.distanceUnit(metric))")
                labeled("Time", Fmt.clock(run.end.timeIntervalSince(run.start)))
                labeled("Pace", Fmt.pace(seconds: run.end.timeIntervalSince(run.start), meters: run.meters, metric: metric))
            }
            Text("\(run.start.formatted(.dateTime.weekday(.wide).hour().minute())) – \(run.end.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    savingRun = run
                    Task {
                        do {
                            try await health.saveRun(start: run.start, end: run.end, meters: run.meters, detected: true)
                            detector.dismiss(run)
                        } catch {
                            errorText = "Ski Steps needs permission to save workouts. Open Health › Sharing › Apps › Ski Steps and turn on Workouts."
                        }
                        savingRun = nil
                    }
                } label: {
                    HStack {
                        if savingRun == run { ProgressView().tint(.black) }
                        Text("Save to Health")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                }
                Button {
                    withAnimation { detector.dismiss(run) }
                } label: {
                    Text("Not a run")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .card()
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.gold.opacity(0.5)))
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private var weekCard: some View {
        let time = thisWeek.map(\.duration).reduce(0, +)
        let cal = thisWeek.map(\.energy).reduce(0, +)
        let runMeters = thisWeek.filter { $0.kind == .running }.map(\.distance).reduce(0, +)
        return VStack(alignment: .leading, spacing: 12) {
            Text("This week").font(.headline)
            HStack(spacing: 0) {
                weekStat("\(thisWeek.count)", "workouts", Theme.accent)
                weekStat(Fmt.minutes(time / 60), time >= 3600 ? "time" : "min", Theme.active)
                weekStat(Fmt.steps(cal), "cal", Theme.calorie)
                weekStat(Fmt.distance(runMeters, metric: metric), "\(Fmt.distanceUnit(metric)) run", Theme.run)
            }
        }
        .padding(16)
        .card()
    }

    private func weekStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(kindsPresent) { kind in
                    Button {
                        withAnimation(.snappy) { filter = kind }
                    } label: {
                        Label(kind.title, systemImage: kind.icon)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(filter == kind ? .black : .primary)
                            .background(filter == kind ? kind.color : Color.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: filter.icon)
                .font(.largeTitle)
                .foregroundStyle(filter == .all ? Theme.accent : filter.color)
            Text(filter == .all ? "No workouts yet" : "No \(filter.title.lowercased()) workouts yet")
                .font(.headline)
            Text("Record a run above, or work out with your Apple Watch — it shows up here automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .card()
    }

    private var watchTip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "applewatch")
                .foregroundStyle(Theme.accent2)
            Text("Swims, rides and other workouts are detected by Apple Watch and appear here automatically. Runs are also detected from your iPhone's motion data.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Row

struct WorkoutRow: View {
    let summary: WorkoutSummary
    let metric: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: summary.kind.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(summary.kind.color)
                .frame(width: 48, height: 48)
                .background(summary.kind.color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.name).font(.headline)
                    if summary.autoDetected {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(Theme.gold)
                    }
                }
                Text(summary.distanceText(metric: metric) ?? Fmt.clock(summary.duration))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(summary.kind.color)
                Text(summary.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if summary.distance > 0 {
                    Text(Fmt.clock(summary.duration)).font(.subheadline.monospacedDigit())
                }
                if let pace = summary.paceText(metric: metric) {
                    Text(pace).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if summary.energy > 0 {
                    Text("\(Fmt.steps(summary.energy)) cal").font(.caption).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
        .card()
    }
}

// MARK: - Detail

struct WorkoutDetailView: View {
    let summary: WorkoutSummary
    @EnvironmentObject private var health: HealthStore
    @AppStorage("useMetric") private var metric = false
    @State private var route: [CLLocation] = []
    @State private var loaded = false

    private var splits: [(Int, TimeInterval)] {
        guard route.count > 2, summary.kind == .running || summary.kind == .walking || summary.kind == .cycling else { return [] }
        let unit = metric ? 1000.0 : 1609.344
        var result: [(Int, TimeInterval)] = []
        var dist = 0.0
        var lastSplitTime = route[0].timestamp
        for i in 1..<route.count {
            dist += route[i].distance(from: route[i - 1])
            if dist >= unit * Double(result.count + 1) {
                result.append((result.count + 1, route[i].timestamp.timeIntervalSince(lastSplitTime)))
                lastSplitTime = route[i].timestamp
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if route.count > 1 { routeMap }
                statsGrid
                if !splits.isEmpty { splitsCard }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            loaded = true
            route = await health.route(for: summary.workout)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: summary.kind.icon)
                .font(.title.weight(.semibold))
                .foregroundStyle(summary.kind.color)
                .frame(width: 64, height: 64)
                .background(summary.kind.color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.name).font(.title2.weight(.bold))
                Text(summary.start.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("\(summary.start.formatted(date: .omitted, time: .shortened)) – \(summary.end.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .card()
    }

    private var routeMap: some View {
        Map(initialPosition: .automatic, interactionModes: [.zoom, .pan]) {
            MapPolyline(coordinates: route.map(\.coordinate))
                .stroke(summary.kind.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            if let first = route.first {
                Annotation("Start", coordinate: first.coordinate) {
                    Circle().fill(Theme.accent).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if let last = route.last {
                Annotation("Finish", coordinate: last.coordinate) {
                    Circle().fill(Theme.calorie).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statsGrid: some View {
        let items: [(String, String, String, Color)] = {
            var list: [(String, String, String, Color)] = [
                ("Workout time", Fmt.clock(summary.duration), "timer", Theme.active),
            ]
            if let d = summary.distanceText(metric: metric) { list.append(("Distance", d, "location.fill", Theme.accent2)) }
            if let p = summary.paceText(metric: metric) {
                list.append((summary.kind == .cycling ? "Avg speed" : "Avg pace", p, "speedometer", Theme.run))
            }
            if summary.energy > 0 { list.append(("Active calories", "\(Fmt.steps(summary.energy)) cal", "flame.fill", Theme.calorie)) }
            if summary.averageHeartRate > 0 {
                list.append(("Avg heart rate", "\(Int(summary.averageHeartRate)) bpm", "heart.fill", .red))
            }
            if summary.maxHeartRate > 0 {
                list.append(("Max heart rate", "\(Int(summary.maxHeartRate)) bpm", "bolt.heart.fill", .red))
            }
            if summary.laps > 0 { list.append(("Laps", "\(summary.laps)", "arrow.left.arrow.right", Theme.accent2)) }
            if summary.strokes > 0 { list.append(("Strokes", Fmt.steps(summary.strokes), "water.waves", Theme.accent2)) }
            list.append(("Recorded by", summary.source, "applewatch", .gray))
            return list
        }()
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Label(item.0, systemImage: item.2)
                        .font(.caption)
                        .foregroundStyle(item.3)
                    Text(item.1)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .card()
            }
        }
    }

    private var splitsCard: some View {
        let fastest = splits.map(\.1).min() ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text("Splits").font(.headline)
            ForEach(splits, id: \.0) { split in
                HStack {
                    Text("\(metric ? "km" : "Mile") \(split.0)")
                        .frame(width: 70, alignment: .leading)
                    GoalBar(progress: fastest / max(split.1, 1), color: Theme.run, height: 8)
                    Text(Fmt.clock(split.1))
                        .font(.body.monospacedDigit().weight(split.1 == fastest ? .bold : .regular))
                        .foregroundStyle(split.1 == fastest ? Theme.gold : .primary)
                        .frame(width: 64, alignment: .trailing)
                }
                .font(.subheadline)
            }
        }
        .padding(16)
        .card()
    }
}
