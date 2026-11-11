import Foundation
import HealthKit
import CoreMotion
import SwiftUI
import UserNotifications

// MARK: - Workout model

enum WorkoutKind: String, CaseIterable, Identifiable {
    case all, running, walking, swimming, cycling, strength, other
    var id: Self { self }

    init(_ type: HKWorkoutActivityType) {
        switch type {
        case .running: self = .running
        case .walking, .hiking: self = .walking
        case .swimming: self = .swimming
        case .cycling, .handCycling: self = .cycling
        case .traditionalStrengthTraining, .functionalStrengthTraining, .highIntensityIntervalTraining,
             .coreTraining, .crossTraining: self = .strength
        default: self = .other
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .running: "Running"
        case .walking: "Walking"
        case .swimming: "Swimming"
        case .cycling: "Cycling"
        case .strength: "Strength"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .swimming: "figure.pool.swim"
        case .cycling: "figure.outdoor.cycle"
        case .strength: "dumbbell.fill"
        case .other: "figure.mixed.cardio"
        }
    }

    var color: Color {
        switch self {
        case .all: .white
        case .running: Theme.run
        case .walking: Theme.accent
        case .swimming: Theme.accent2
        case .cycling: Theme.gold
        case .strength: Theme.calorie
        case .other: Theme.active
        }
    }
}

struct WorkoutSummary: Identifiable {
    let workout: HKWorkout
    var id: UUID { workout.uuid }
    var type: HKWorkoutActivityType { workout.workoutActivityType }
    var kind: WorkoutKind { WorkoutKind(type) }
    var start: Date { workout.startDate }
    var end: Date { workout.endDate }
    var duration: TimeInterval { workout.duration }

    private func total(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) -> Double {
        workout.statistics(for: HKQuantityType(id))?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    /// Meters, from whichever distance type fits the workout.
    var distance: Double {
        switch kind {
        case .swimming: total(.distanceSwimming, .meter())
        case .cycling: total(.distanceCycling, .meter())
        default: total(.distanceWalkingRunning, .meter())
        }
    }

    var energy: Double { total(.activeEnergyBurned, .kilocalorie()) }

    private static let bpm = HKUnit.count().unitDivided(by: .minute())
    var averageHeartRate: Double {
        workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: Self.bpm) ?? 0
    }
    var maxHeartRate: Double {
        workout.statistics(for: HKQuantityType(.heartRate))?.maximumQuantity()?.doubleValue(for: Self.bpm) ?? 0
    }
    var strokes: Double { total(.swimmingStrokeCount, .count()) }
    var laps: Int { workout.workoutEvents?.filter { $0.type == .lap }.count ?? 0 }
    var isIndoor: Bool { (workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) ?? false }
    var autoDetected: Bool { (workout.metadata?["SkiStepsAutoDetected"] as? Bool) ?? false }
    var source: String { workout.sourceRevision.source.name }

    var name: String {
        if let routine = workout.metadata?["SkiStepsRoutine"] as? String { return routine }
        switch type {
        case .running: return isIndoor ? "Indoor Run" : "Outdoor Run"
        case .walking: return isIndoor ? "Indoor Walk" : "Outdoor Walk"
        case .hiking: return "Hike"
        case .swimming:
            let open = (workout.metadata?[HKMetadataKeySwimmingLocationType] as? NSNumber)?.intValue
                == HKWorkoutSwimmingLocationType.openWater.rawValue
            return open ? "Open Water Swim" : "Pool Swim"
        case .cycling: return isIndoor ? "Indoor Cycle" : "Outdoor Cycle"
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining: return "Functional Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining: return "Core Training"
        case .crossTraining: return "Cross Training"
        case .yoga: return "Yoga"
        case .elliptical: return "Elliptical"
        case .stairClimbing where isIndoor: return "Stair Climber"
        case .rowing: return "Rowing"
        case .stairClimbing, .stairs: return "Stairs"
        case .dance, .socialDance, .cardioDance: return "Dance"
        case .pilates: return "Pilates"
        case .mixedCardio: return "Mixed Cardio"
        case .golf: return "Golf"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .tennis: return "Tennis"
        case .cooldown: return "Cooldown"
        default: return "Workout"
        }
    }

    /// Distance text in the right units: yards/meters for swims, mi/km otherwise.
    func distanceText(metric: Bool) -> String? {
        guard distance > 0 else { return nil }
        if kind == .swimming {
            return metric ? "\(Fmt.steps(distance)) m" : "\(Fmt.steps(distance / 0.9144)) yd"
        }
        return "\(Fmt.distance(distance, metric: metric)) \(Fmt.distanceUnit(metric))"
    }

    /// Pace: per mi/km for runs and walks, per 100 yd/m for swims, speed for rides.
    func paceText(metric: Bool) -> String? {
        guard distance > 0, duration > 0 else { return nil }
        switch kind {
        case .running, .walking:
            return "\(Fmt.pace(seconds: duration, meters: distance, metric: metric)) /\(Fmt.distanceUnit(metric))"
        case .swimming:
            let unit = metric ? 100.0 : 91.44
            return "\(Fmt.clock(duration / (distance / unit))) /100\(metric ? "m" : "yd")"
        case .cycling:
            let speed = (distance / (metric ? 1000 : 1609.344)) / (duration / 3600)
            return String(format: "%.1f %@", speed, metric ? "km/h" : "mph")
        default:
            return nil
        }
    }
}

// MARK: - Run & walk auto-detection

/// A run or walk the phone noticed but nobody recorded.
struct DetectedRun: Identifiable, Equatable {
    enum Kind: String { case run, walk }
    var kind: Kind
    var start: Date
    var end: Date
    var meters: Double
    var steps: Double
    var id: Date { start }

    var title: String { kind == .run ? "Run" : "Walk" }
    var icon: String { kind == .run ? "figure.run" : "figure.walk" }
    var activity: HKWorkoutActivityType { kind == .run ? .running : .walking }
}

/// Looks through the phone's motion history (kept for 7 days) for runs and
/// walks that weren't recorded as workouts. New ones are saved to Health
/// automatically (or offered, if auto-save is off).
@MainActor
final class RunDetector: ObservableObject {
    @Published var found: [DetectedRun] = []

    private let activity = CMMotionActivityManager()
    private let pedometer = CMPedometer()

    var enabled: Bool { UserDefaults.standard.object(forKey: "autoDetectRuns") as? Bool ?? true }
    var walksEnabled: Bool { UserDefaults.standard.object(forKey: "autoDetectWalks") as? Bool ?? true }
    var autoSave: Bool { UserDefaults.standard.object(forKey: "autoSaveDetected") as? Bool ?? true }

    /// Only activity after this moment is saved automatically, so turning the
    /// feature on doesn't flood Health with a week of old walks.
    var autoSaveSince: Date {
        let key = "autoSaveSince"
        if let d = UserDefaults.standard.object(forKey: key) as? Date { return d }
        let now = Date()
        UserDefaults.standard.set(now, forKey: key)
        return now
    }

    private var dismissed: Set<Double> {
        get { Set(UserDefaults.standard.array(forKey: "dismissedRuns") as? [Double] ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(400)), forKey: "dismissedRuns") }
    }

    private var notified: Set<Double> {
        get { Set(UserDefaults.standard.array(forKey: "notifiedRuns") as? [Double] ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(400)), forKey: "notifiedRuns") }
    }

    func dismiss(_ run: DetectedRun) {
        dismissed.insert(run.start.timeIntervalSince1970)
        found.removeAll { $0 == run }
    }

    /// Stops a deleted auto-saved workout from being detected again.
    func forget(start: Date) {
        dismissed.insert(start.timeIntervalSince1970)
    }

    func scan(existing workouts: [WorkoutSummary]) async {
        guard enabled || walksEnabled, CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() != .denied,
              CMMotionActivityManager.authorizationStatus() != .restricted else {
            found = []
            return
        }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end)!
        let activities = await query(from: start, to: end)

        let runs = enabled
            ? segments(activities, end: end, maxGap: 2 * 60) { $0.running && $0.confidence != .low }
            : []
        let walks = walksEnabled
            ? segments(activities, end: end, maxGap: 3 * 60) { $0.walking && $0.confidence != .low }
            : []

        let skip = dismissed
        var results: [DetectedRun] = []

        func covered(_ seg: DateInterval, by others: [DateInterval]) -> Bool {
            others.contains { o in o.intersection(with: seg).map { $0.duration > seg.duration * 0.3 } ?? false }
        }
        let recorded = workouts.map { DateInterval(start: $0.start, end: max($0.end, $0.start)) }

        for (kind, segs, minLength, minMeters) in [(DetectedRun.Kind.run, runs, 5.0 * 60, 400.0),
                                                   (.walk, walks, 10.0 * 60, 700.0)] {
            for seg in segs where seg.duration >= minLength {
                // Still going right now? Wait until it's finished.
                if end.timeIntervalSince(seg.end) < 3 * 60 { continue }
                if skip.contains(seg.start.timeIntervalSince1970) { continue }
                if covered(seg, by: recorded) { continue }
                // A walk that's mostly a detected run is part of that run.
                if kind == .walk, covered(seg, by: runs.filter { $0.duration >= 5 * 60 }) { continue }
                let (meters, steps) = await pedometerData(from: seg.start, to: seg.end)
                guard meters >= minMeters else { continue }
                results.append(DetectedRun(kind: kind, start: seg.start, end: seg.end, meters: meters, steps: steps))
            }
        }
        found = results.sorted { $0.start > $1.start }
        if !autoSave { notifyFound() }
    }

    /// Detected items that should be saved without asking.
    var toAutoSave: [DetectedRun] {
        guard autoSave else { return [] }
        let since = autoSaveSince
        return found.filter { $0.start >= since }
    }

    private func segments(_ activities: [CMMotionActivity], end: Date, maxGap: TimeInterval,
                          match: (CMMotionActivity) -> Bool) -> [DateInterval] {
        var raw: [DateInterval] = []
        var segStart: Date?
        for a in activities {
            let on = match(a)
            if on, segStart == nil { segStart = a.startDate }
            if !on, let s = segStart {
                raw.append(DateInterval(start: s, end: max(a.startDate, s)))
                segStart = nil
            }
        }
        if let s = segStart { raw.append(DateInterval(start: s, end: end)) }

        // Merge pieces separated by short stops (traffic lights, crossings).
        var merged: [DateInterval] = []
        for seg in raw {
            if let last = merged.last, seg.start.timeIntervalSince(last.end) <= maxGap {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, seg.end))
            } else {
                merged.append(seg)
            }
        }
        return merged
    }

    /// "Run detected — open to save" (used when auto-save is off).
    private func notifyFound() {
        var sent = notified
        let metric = UserDefaults.standard.bool(forKey: "useMetric")
        for run in found where !sent.contains(run.start.timeIntervalSince1970) {
            sent.insert(run.start.timeIntervalSince1970)
            guard Date().timeIntervalSince(run.end) < 6 * 3600 else { continue }
            let content = UNMutableNotificationContent()
            content.title = run.kind == .run ? "Run detected 🏃" : "Walk detected 🚶"
            content.body = "\(Fmt.distance(run.meters, metric: metric)) \(Fmt.distanceUnit(metric)) in "
                + "\(Fmt.clock(run.end.timeIntervalSince(run.start))) at "
                + "\(run.start.formatted(date: .omitted, time: .shortened)). Open Ski Steps to save it."
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "run-\(Int(run.start.timeIntervalSince1970))",
                                      content: content, trigger: nil))
        }
        notified = sent
    }

    /// "Walk recorded" after an automatic save.
    func notifySaved(_ run: DetectedRun) {
        var sent = notified
        guard !sent.contains(run.start.timeIntervalSince1970) else { return }
        sent.insert(run.start.timeIntervalSince1970)
        notified = sent
        guard UserDefaults.standard.object(forKey: "detectAlerts") as? Bool ?? true else { return }
        let metric = UserDefaults.standard.bool(forKey: "useMetric")
        let content = UNMutableNotificationContent()
        content.title = run.kind == .run ? "Run recorded 🏃" : "Walk recorded 🚶"
        content.body = "\(Fmt.distance(run.meters, metric: metric)) \(Fmt.distanceUnit(metric)) in "
            + "\(Fmt.clock(run.end.timeIntervalSince(run.start))) from "
            + "\(run.start.formatted(date: .omitted, time: .shortened)). Saved to Apple Health."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "saved-\(Int(run.start.timeIntervalSince1970))",
                                  content: content, trigger: nil))
    }

    private func query(from start: Date, to end: Date) async -> [CMMotionActivity] {
        let manager = activity
        return await withCheckedContinuation { cont in
            manager.queryActivityStarting(from: start, to: end, to: OperationQueue()) { list, _ in
                cont.resume(returning: list ?? [])
            }
        }
    }

    private func pedometerData(from start: Date, to end: Date) async -> (Double, Double) {
        guard CMPedometer.isStepCountingAvailable() else { return (0, 0) }
        let pedometer = self.pedometer
        return await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                cont.resume(returning: (data?.distance?.doubleValue ?? 0, data?.numberOfSteps.doubleValue ?? 0))
            }
        }
    }
}
