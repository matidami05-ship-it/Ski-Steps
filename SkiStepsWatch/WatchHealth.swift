import Foundation
import HealthKit
import WatchConnectivity

/// Today's totals on the watch, plus goals synced from the iPhone.
@MainActor
final class WatchHealth: NSObject, ObservableObject {
    @Published var steps: Double = 0
    @Published var distance: Double = 0
    @Published var energy: Double = 0
    @Published var activeMinutes: Double = 0
    @Published var goalsVersion = 0   // bumps when the phone sends new goals

    let store = HKHealthStore()
    private var observer: HKObserverQuery?

    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceSwimming),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.swimmingStrokeCount),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.heartRate),
        HKObjectType.workoutType(),
        HKObjectType.activitySummaryType(),
    ]

    static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute(),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceSwimming),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.swimmingStrokeCount),
        HKQuantityType(.heartRate),
    ]

    var useMetric: Bool { UserDefaults.standard.bool(forKey: "useMetric") }

    func value(_ m: Metric) -> Double {
        switch m {
        case .steps: steps
        case .distance: distance
        case .calories: energy
        case .active: activeMinutes
        }
    }

    func start() async {
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        try? await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        if observer == nil {
            let q = HKObserverQuery(sampleType: HKQuantityType(.stepCount), predicate: nil) { [weak self] _, done, _ in
                Task { @MainActor in await self?.refresh() }
                done()
            }
            observer = q
            store.execute(q)
        }
        await refresh()
    }

    func refresh() async {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        async let s = sum(.stepCount, .count(), start, now)
        async let d = sum(.distanceWalkingRunning, .meter(), start, now)
        async let e = sum(.activeEnergyBurned, .kilocalorie(), start, now)
        async let a = sum(.appleExerciseTime, .minute(), start, now)
        steps = await s
        distance = await d
        energy = await e
        activeMinutes = await a
    }

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ start: Date, _ end: Date) async -> Double {
        let store = self.store
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(id),
                                      quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    fileprivate func apply(_ context: [String: Any]) {
        let defaults = UserDefaults.standard
        for m in Metric.allCases {
            if let g = context[m.goalKey] as? Double { defaults.set(g, forKey: m.goalKey) }
        }
        if let metric = context["useMetric"] as? Bool { defaults.set(metric, forKey: "useMetric") }
        goalsVersion += 1
    }
}

extension WatchHealth: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
}
