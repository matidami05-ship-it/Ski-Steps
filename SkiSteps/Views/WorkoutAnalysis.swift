import SwiftUI
import Charts
import HealthKit
import CoreLocation

// MARK: - Heart rate data

struct HRSample: Identifiable {
    let date: Date
    let bpm: Double
    var id: Date { date }
}

struct HRZone: Identifiable {
    let number: Int
    let name: String
    let low: Double     // bpm, inclusive
    let high: Double?   // bpm, exclusive; nil = no top
    let color: Color
    var seconds: Double = 0
    var id: Int { number }

    var range: String {
        if let high { return "\(Int(low))–\(Int(high) - 1) bpm" }
        return "≥ \(Int(low)) bpm"
    }

    /// Zones as a percent of max heart rate: 50/60/70/80/90 %.
    static func zones(maxHR: Double) -> [HRZone] {
        let b = [0.5, 0.6, 0.7, 0.8, 0.9].map { ($0 * maxHR).rounded() }
        return [
            HRZone(number: 5, name: "Very hard", low: b[4], high: nil, color: Color(red: 1.0, green: 0.36, blue: 0.40)),
            HRZone(number: 4, name: "Hard", low: b[3], high: b[4], color: Color(red: 1.0, green: 0.62, blue: 0.30)),
            HRZone(number: 3, name: "Moderate", low: b[2], high: b[3], color: Color(red: 1.0, green: 0.88, blue: 0.20)),
            HRZone(number: 2, name: "Easy", low: b[1], high: b[2], color: Color(red: 0.35, green: 0.85, blue: 0.45)),
            HRZone(number: 1, name: "Very easy", low: b[0], high: b[1], color: Color(red: 0.40, green: 0.72, blue: 1.0)),
        ]
    }

    /// Time spent in each zone (plus time below zone 1).
    static func timeInZones(_ samples: [HRSample], maxHR: Double) -> (zones: [HRZone], below: Double) {
        var zones = zones(maxHR: maxHR)
        var below = 0.0
        for (i, s) in samples.enumerated() {
            let next = i + 1 < samples.count ? samples[i + 1].date : s.date.addingTimeInterval(5)
            let dt = min(max(next.timeIntervalSince(s.date), 0), 60)
            if let idx = zones.firstIndex(where: { s.bpm >= $0.low && ($0.high == nil || s.bpm < $0.high!) }) {
                zones[idx].seconds += dt
            } else {
                below += dt
            }
        }
        return (zones, below)
    }
}

extension HealthStore {
    func heartRateSamples(for workout: HKWorkout) async -> [HRSample] {
        let store = self.store
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKQuantityType(.heartRate),
                                  predicate: HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate),
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, _ in
                let list = (s as? [HKQuantitySample] ?? []).map { HRSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit)) }
                cont.resume(returning: list)
            }
            store.execute(q)
        }
    }

    /// TRIMP training load for one workout (same formula as Insights).
    func trainingLoad(_ w: WorkoutSummary) -> Double {
        let minutes = w.duration / 60
        guard w.averageHeartRate > 0, maxHR > restingHR else { return w.energy > 0 ? w.energy / 8 : minutes * 0.6 }
        let hrr = min(max((w.averageHeartRate - restingHR) / (maxHR - restingHR), 0), 1)
        return minutes * hrr * 0.64 * exp(1.92 * hrr)
    }
}

// MARK: - Heart rate zones card

struct HRZonesCard: View {
    let samples: [HRSample]
    let maxHR: Double

    var body: some View {
        let result = HRZone.timeInZones(samples, maxHR: maxHR)
        let total = max(result.zones.reduce(0) { $0 + $1.seconds } + result.below, 1)
        VStack(alignment: .leading, spacing: 14) {
            Text("Heart Rate Zones").font(.headline).foregroundStyle(HRZone.zones(maxHR: maxHR)[0].color)
            Chart {
                ForEach(result.zones.reversed()) { z in
                    SectorMark(angle: .value("Time", max(z.seconds, 0.0001)), innerRadius: .ratio(0.62), angularInset: 2)
                        .foregroundStyle(z.color)
                        .cornerRadius(5)
                        .opacity(z.seconds > 0 ? 1 : 0)
                }
                if result.below > 0 {
                    SectorMark(angle: .value("Time", result.below), innerRadius: .ratio(0.62), angularInset: 2)
                        .foregroundStyle(Color.white.opacity(0.18))
                        .cornerRadius(5)
                }
            }
            .chartLegend(.hidden)
            .frame(height: 200)
            .overlay {
                if let top = result.zones.max(by: { $0.seconds < $1.seconds }), top.seconds > 0 {
                    VStack(spacing: 0) {
                        Text("Zone \(top.number)").font(.title3.weight(.bold)).foregroundStyle(top.color)
                        Text("\(Int((top.seconds / total * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(result.zones) { z in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Zone \(z.number) · \(z.name)").font(.subheadline.weight(.semibold)).foregroundStyle(z.color)
                            Text(z.range).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if z.seconds > 0 {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(Int((z.seconds / total * 100).rounded()))%").font(.subheadline.weight(.bold))
                                Text(Fmt.clock(z.seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    GoalBar(progress: z.seconds / total, color: z.color, height: 6)
                }
            }
            if result.below > 0 {
                Text("Below zone 1: \(Fmt.clock(result.below)) (\(Int((result.below / total * 100).rounded()))%)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Label("Zones are % of max heart rate (\(Int(maxHR)) bpm, from your age in Health).", systemImage: "info.circle")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .card()
    }
}

// MARK: - Heart rate profile (distribution)

struct HRProfileCard: View {
    let samples: [HRSample]
    let maxHR: Double

    private struct Point: Identifiable { let bpm: Double; let y: Double; var id: Double { bpm } }

    var body: some View {
        let values = samples.map(\.bpm)
        let n = Double(values.count)
        let mean = values.reduce(0, +) / max(n, 1)
        let sd = sqrt(values.map { pow($0 - mean, 2) }.reduce(0, +) / max(n, 1))
        let lo = (values.min() ?? mean) - max(sd, 3) * 1.5
        let hi = (values.max() ?? mean) + max(sd, 3) * 1.5
        let bw = max(2, 1.06 * max(sd, 1) * pow(max(n, 1), -0.2))
        let xs = stride(from: lo, through: hi, by: (hi - lo) / 80).map { $0 }
        let density = xs.map { x in
            Point(bpm: x, y: values.reduce(0) { $0 + exp(-0.5 * pow((x - $1) / bw, 2)) } / (max(n, 1) * bw * 2.5066))
        }
        let normal = xs.map { x in
            Point(bpm: x, y: exp(-0.5 * pow((x - mean) / max(sd, 1), 2)) / (max(sd, 1) * 2.5066))
        }
        let label = sd < 6 ? "Steady" : (sd < 12 ? "Variable" : "Very variable")
        let zoneLines = HRZone.zones(maxHR: maxHR).filter { $0.low > lo && $0.low < hi }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Heart Rate Profile").font(.headline).foregroundStyle(.red)
                Spacer()
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent2)
            }
            Chart {
                ForEach(density) { p in
                    AreaMark(x: .value("bpm", p.bpm), y: .value("Density", p.y))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent2.opacity(0.45), Theme.accent.opacity(0.25)],
                                                        startPoint: .leading, endPoint: .trailing))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("bpm", p.bpm), y: .value("Density", p.y), series: .value("S", "Workout"))
                        .foregroundStyle(Theme.accent2)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                }
                ForEach(normal) { p in
                    LineMark(x: .value("bpm", p.bpm), y: .value("Density", p.y), series: .value("S", "Normal"))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(x: .value("Average", mean))
                    .foregroundStyle(.white)
                    .annotation(position: .bottom) {
                        Text("\(Int(mean.rounded())) bpm avg").font(.caption.weight(.semibold)).foregroundStyle(.red)
                    }
                ForEach(zoneLines) { z in
                    RuleMark(x: .value("Zone", z.low))
                        .foregroundStyle(z.color.opacity(0.8))
                        .annotation(position: .top) {
                            Text("Z\(z.number)").font(.caption2.weight(.bold)).foregroundStyle(z.color)
                        }
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: 190)
            Text("How your heart rate was spread during the workout. Narrow = steady effort, wide = changing pace. Dashed line is a perfectly even spread for comparison.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .card()
    }
}

// MARK: - Speed

struct SpeedPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct SpeedCard: View {
    let summary: WorkoutSummary
    let route: [CLLocation]
    let metric: Bool

    var body: some View {
        let factor = metric ? 3.6 : 2.23694   // m/s → km/h or mph
        let unit = metric ? "km/h" : "mph"
        let avg = summary.duration > 0 ? summary.distance / summary.duration * factor : 0
        // Smooth GPS speed over ~5 points to drop spikes.
        let speeds = route.map { max($0.speed, 0) }.filter { $0 < 15 }
        let smoothed = speeds.indices.map { i -> Double in
            let w = speeds[max(0, i - 2)...min(speeds.count - 1, i + 2)]
            return w.reduce(0, +) / Double(w.count)
        }
        let maxSpeed = max((smoothed.max() ?? 0) * factor, avg)
        VStack(alignment: .leading, spacing: 0) {
            Text("Speed").font(.headline).foregroundStyle(Theme.accent2).padding(.bottom, 10)
            row("Avg. Speed", String(format: "%.2f %@", avg, unit))
            Divider().overlay(Theme.stroke)
            row("Max. Speed", String(format: "%.2f %@", maxSpeed, unit))
            if summary.kind == .running || summary.kind == .walking {
                Divider().overlay(Theme.stroke)
                row("Avg. Pace", "\(Fmt.pace(seconds: summary.duration, meters: summary.distance, metric: metric)) /\(Fmt.distanceUnit(metric))")
            }
            if !smoothed.isEmpty, route.count > 10 {
                let pts = zip(route, smoothed).map { SpeedPoint(date: $0.timestamp, value: $1 * factor) }
                Chart(pts) { p in
                    AreaMark(x: .value("Time", p.date), y: .value("Speed", p.value))
                        .foregroundStyle(Theme.accent2.opacity(0.25))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", p.date), y: .value("Speed", p.value))
                        .foregroundStyle(Theme.accent2)
                        .interpolationMethod(.monotone)
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel()
                    }
                }
                .frame(height: 120)
                .padding(.top, 10)
            }
        }
        .padding(16)
        .card()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.headline.monospacedDigit())
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Effort profile (radar)

struct EffortRadarCard: View {
    let summary: WorkoutSummary
    let all: [WorkoutSummary]

    private struct Axis { let name: String; let color: Color; let value: (WorkoutSummary) -> Double }

    private var axes: [Axis] {
        [
            Axis(name: "Avg Speed", color: Theme.accent2) { $0.duration > 0 ? $0.distance / $0.duration : 0 },
            Axis(name: "kcal/min", color: Theme.calorie) { $0.duration > 0 ? $0.energy / ($0.duration / 60) : 0 },
            Axis(name: "Avg HR", color: .red) { $0.averageHeartRate },
            Axis(name: "Distance", color: Theme.run) { $0.distance },
            Axis(name: "Duration", color: Theme.active) { $0.duration },
        ]
    }

    var body: some View {
        let peers = all.filter { $0.kind == summary.kind }
        let pool = peers.isEmpty ? [summary] : peers
        let maxes = axes.map { a in max(pool.map(a.value).max() ?? 0, a.value(summary), 0.0001) }
        let mine = axes.indices.map { i in min(axes[i].value(summary) / maxes[i], 1) }
        let avg = axes.indices.map { i in
            pool.map { axes[i].value($0) / maxes[i] }.reduce(0, +) / Double(pool.count)
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("Effort Profile").font(.headline).foregroundStyle(Theme.accent2)
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let r = size / 2 - 34
                ZStack {
                    Canvas { ctx, _ in
                        func point(_ i: Int, _ v: Double) -> CGPoint {
                            let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(axes.count)
                            return CGPoint(x: center.x + CGFloat(cos(a) * v) * r, y: center.y + CGFloat(sin(a) * v) * r)
                        }
                        func polygon(_ vals: [Double]) -> Path {
                            var p = Path()
                            for (i, v) in vals.enumerated() {
                                if i == 0 { p.move(to: point(i, v)) } else { p.addLine(to: point(i, v)) }
                            }
                            p.closeSubpath()
                            return p
                        }
                        // Grid
                        for level in [0.25, 0.5, 0.75] {
                            ctx.stroke(polygon(Array(repeating: level, count: axes.count)),
                                       with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                        ctx.stroke(polygon(Array(repeating: 1, count: axes.count)), with: .color(.white.opacity(0.4)), lineWidth: 1.2)
                        for i in axes.indices {
                            var spoke = Path()
                            spoke.move(to: center)
                            spoke.addLine(to: point(i, 1))
                            ctx.stroke(spoke, with: .color(.white.opacity(0.15)), lineWidth: 1)
                        }
                        // Average (dashed) and this workout (filled)
                        ctx.stroke(polygon(avg.map { max($0, 0.04) }), with: .color(Theme.calorie),
                                   style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        let shape = polygon(mine.map { max($0, 0.04) })
                        ctx.fill(shape, with: .color(Theme.accent2.opacity(0.3)))
                        ctx.stroke(shape, with: .color(Theme.accent2), lineWidth: 3)
                        for (i, v) in mine.enumerated() {
                            let pt = point(i, max(v, 0.04))
                            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(Theme.accent2))
                            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)), with: .color(Theme.bgTop))
                        }
                    }
                    ForEach(axes.indices, id: \.self) { i in
                        let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(axes.count)
                        Text(axes[i].name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(axes[i].color)
                            .fixedSize()
                            .position(x: center.x + CGFloat(cos(a)) * (r + 24), y: center.y + CGFloat(sin(a)) * (r + 18))
                    }
                }
            }
            .frame(height: 290)
            HStack(spacing: 16) {
                legend(Theme.accent2, "This workout")
                legend(Theme.calorie, "Your average (\(pool.count) \(summary.kind.title.lowercased()))")
            }
            .font(.caption)
        }
        .padding(16)
        .card()
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 10, height: 10)
            Text(t).foregroundStyle(.secondary)
        }
    }
}

// MARK: - AI prompt for one workout

extension HealthStore {
    nonisolated static let workoutInstructions = """
    You analyze a single workout inside the Ski Steps app. Write exactly two short paragraphs, \
    under 90 words in total, plain text with no headings or bullets. Paragraph 1: what kind of \
    session it was (effort, heart-rate zones, pace/speed, training load), quoting the numbers. \
    Paragraph 2: what it means compared with the user's usual workouts, and one specific \
    suggestion for next time. Don't invent data. General wellness only, not medical advice.
    """

    func workoutPrompt(_ w: WorkoutSummary, samples: [HRSample]) -> String {
        let metric = UserDefaults.standard.bool(forKey: "useMetric")
        var lines = ["Workout: \(w.name) on \(w.start.formatted(date: .abbreviated, time: .shortened)), recorded by \(w.source)."]
        lines.append("Duration \(Fmt.clock(w.duration)).")
        if let d = w.distanceText(metric: metric) { lines.append("Distance \(d).") }
        if let p = w.paceText(metric: metric) { lines.append("Pace/speed \(p).") }
        if w.energy > 0 { lines.append("Active calories \(Int(w.energy)).") }
        if w.averageHeartRate > 0 { lines.append("Avg HR \(Int(w.averageHeartRate)), max HR \(Int(w.maxHeartRate)). Resting HR \(Int(restingHR)), estimated max HR \(Int(maxHR)).") }
        lines.append("Training load (TRIMP) \(Int(trainingLoad(w).rounded())).")
        if !samples.isEmpty {
            let r = HRZone.timeInZones(samples, maxHR: maxHR)
            let total = max(r.zones.reduce(0) { $0 + $1.seconds } + r.below, 1)
            let z = r.zones.reversed().map { "Z\($0.number) \(Int(($0.seconds / total * 100).rounded()))%" }.joined(separator: ", ")
            lines.append("Time in zones: \(z), below Z1 \(Int((r.below / total * 100).rounded()))%.")
        }
        let peers = workouts.filter { $0.kind == w.kind && $0.id != w.id }
        if !peers.isEmpty {
            let n = Double(peers.count)
            let avgDur = peers.map(\.duration).reduce(0, +) / n
            let avgDist = peers.map(\.distance).reduce(0, +) / n
            let hrPeers = peers.filter { $0.averageHeartRate > 0 }
            let avgHR = hrPeers.isEmpty ? 0 : hrPeers.map(\.averageHeartRate).reduce(0, +) / Double(hrPeers.count)
            lines.append("User's average for \(peers.count) other \(w.kind.title.lowercased()) workouts: duration \(Fmt.clock(avgDur)), distance \(Fmt.distance(avgDist, metric: metric)) \(Fmt.distanceUnit(metric))" + (avgHR > 0 ? ", avg HR \(Int(avgHR))." : "."))
        }
        return lines.joined(separator: "\n")
    }
}
