import Foundation
import HealthKit
import SwiftUI

enum SleepStage: Int, CaseIterable, Identifiable {
    case awake, rem, core, deep, asleep   // asleep = no stage detail

    var id: Self { self }

    var title: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        case .asleep: "Asleep"
        }
    }

    var color: Color {
        switch self {
        case .awake: Color(red: 1.0, green: 0.55, blue: 0.45)
        case .rem: Color(red: 0.45, green: 0.80, blue: 1.0)
        case .core: Color(red: 0.25, green: 0.50, blue: 1.0)
        case .deep: Color(red: 0.45, green: 0.30, blue: 0.95)
        case .asleep: Color(red: 0.30, green: 0.55, blue: 1.0)
        }
    }

    init?(_ value: Int) {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .awake: self = .awake
        case .asleepREM: self = .rem
        case .asleepCore: self = .core
        case .asleepDeep: self = .deep
        case .asleepUnspecified: self = .asleep
        default: return nil   // in bed is handled separately
        }
    }
}

struct SleepSegment: Identifiable {
    let id = UUID()
    var stage: SleepStage
    var start: Date
    var end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SleepNight: Identifiable {
    /// The day you woke up.
    var day: Date
    var segments: [SleepSegment]
    var inBedStart: Date
    var inBedEnd: Date
    var source: String
    var id: Date { day }

    var hasStages: Bool { segments.contains { [.rem, .core, .deep].contains($0.stage) } }

    func total(_ stage: SleepStage) -> TimeInterval {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }

    var asleep: TimeInterval { segments.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration } }
    var awake: TimeInterval { total(.awake) }
    var inBed: TimeInterval { max(inBedEnd.timeIntervalSince(inBedStart), asleep) }
    var efficiency: Double { inBed > 0 ? min(asleep / inBed, 1) : 0 }
    var bedtime: Date { segments.first { $0.stage != .awake }?.start ?? inBedStart }
    var wake: Date { segments.last { $0.stage != .awake }?.end ?? inBedEnd }

    /// Minutes after 6 PM the evening before — used to compare bedtimes.
    var bedtimeMinutes: Double {
        let cal = Calendar.current
        let evening = cal.date(bySettingHour: 18, minute: 0, second: 0,
                               of: cal.date(byAdding: .day, value: -1, to: day)!)!
        return bedtime.timeIntervalSince(evening) / 60
    }

    /// 0–100 estimate from duration, efficiency, deep+REM share and bedtime consistency.
    func score(goalHours: Double, usualBedtime: Double?) -> Int {
        let goal = max(goalHours, 1) * 3600
        var pts = min(asleep / goal, 1) * 50
        pts += min(max((efficiency - 0.70) / 0.25, 0), 1) * 20
        if hasStages {
            let share = asleep > 0 ? (total(.deep) + total(.rem)) / asleep : 0
            pts += min(share / 0.35, 1) * 15
        } else {
            pts += efficiency * 15
        }
        if let usual = usualBedtime {
            pts += max(0, 1 - abs(bedtimeMinutes - usual) / 90) * 15
        } else {
            pts += 10
        }
        return Int(pts.rounded())
    }
}

extension Array where Element == SleepNight {
    /// Average bedtime (minutes after 6 PM) over the nights before `night`.
    func usualBedtime(before night: SleepNight) -> Double? {
        let prior = filter { $0.day < night.day }.suffix(7)
        guard prior.count >= 3 else { return nil }
        return prior.map(\.bedtimeMinutes).reduce(0, +) / Double(prior.count)
    }
}

extension HealthStore {
    /// Sleep for the last `days` nights from Apple Health. When several apps
    /// recorded the same night (Watch, Oura, iPhone), the most detailed one wins
    /// so time isn't counted twice.
    func loadSleep(days: Int = 30) async -> [SleepNight] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now))!.addingTimeInterval(-6 * 3600)
        let store = self.store
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis),
                                  predicate: HKQuery.predicateForSamples(withStart: start, end: nil),
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, _ in
                cont.resume(returning: s as? [HKCategorySample] ?? [])
            }
            store.execute(q)
        }

        // A sample belongs to the day you woke up (shift by 6 h so 11 PM counts toward tomorrow).
        let byNight = Dictionary(grouping: samples) { cal.startOfDay(for: $0.startDate.addingTimeInterval(6 * 3600)) }

        var nights: [SleepNight] = []
        for (day, daySamples) in byNight {
            let bySource = Dictionary(grouping: daySamples) { $0.sourceRevision.source.bundleIdentifier }
            var best: (score: Double, night: SleepNight)?
            for (_, list) in bySource {
                var segs: [SleepSegment] = []
                var bedStart: Date?, bedEnd: Date?
                for s in list {
                    if s.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                        bedStart = Swift.min(bedStart ?? s.startDate, s.startDate)
                        bedEnd = Swift.max(bedEnd ?? s.endDate, s.endDate)
                    } else if let stage = SleepStage(s.value) {
                        segs.append(SleepSegment(stage: stage, start: s.startDate, end: s.endDate))
                    }
                }
                // Clip overlaps so nothing is counted twice.
                segs.sort { $0.start < $1.start }
                var clean: [SleepSegment] = []
                for var seg in segs {
                    if let last = clean.last, seg.start < last.end { seg.start = last.end }
                    if seg.end > seg.start { clean.append(seg) }
                }
                guard let first = clean.first, let last = clean.last else { continue }
                let night = SleepNight(day: day, segments: clean,
                                       inBedStart: Swift.min(bedStart ?? first.start, first.start),
                                       inBedEnd: Swift.max(bedEnd ?? last.end, last.end),
                                       source: list[0].sourceRevision.source.name)
                let score = (night.hasStages ? 1_000_000 : 0) + night.asleep
                if best == nil || score > best!.score { best = (score, night) }
            }
            if let n = best?.night, n.asleep >= 20 * 60 { nights.append(n) }
        }
        return nights.sorted { $0.day < $1.day }
    }
}

enum SleepFmt {
    /// 27000 → "7h 30m"
    static func hours(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    /// Bedtime minutes-after-6PM → "10:45 PM"
    static func clockTime(minutesAfter6pm m: Double) -> String {
        let cal = Calendar.current
        let base = cal.date(bySettingHour: 18, minute: 0, second: 0, of: .now)!
        return base.addingTimeInterval(m * 60).formatted(date: .omitted, time: .shortened)
    }
}
