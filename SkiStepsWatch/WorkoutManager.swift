import Foundation
import HealthKit
import CoreLocation
import WatchKit

/// The workouts you can start on the watch.
enum WatchWorkout: String, CaseIterable, Identifiable {
    case outdoorRun, indoorRun, outdoorWalk, indoorWalk, poolSwim, openWaterSwim, outdoorCycle, strength, hiit

    var id: Self { self }

    var title: String {
        switch self {
        case .outdoorRun: "Outdoor Run"
        case .indoorRun: "Indoor Run"
        case .outdoorWalk: "Outdoor Walk"
        case .indoorWalk: "Indoor Walk"
        case .poolSwim: "Pool Swim"
        case .openWaterSwim: "Open Water"
        case .outdoorCycle: "Outdoor Cycle"
        case .strength: "Strength"
        case .hiit: "HIIT"
        }
    }

    var icon: String {
        switch self {
        case .outdoorRun, .indoorRun: "figure.run"
        case .outdoorWalk, .indoorWalk: "figure.walk"
        case .poolSwim: "figure.pool.swim"
        case .openWaterSwim: "figure.open.water.swim"
        case .outdoorCycle: "figure.outdoor.cycle"
        case .strength: "dumbbell.fill"
        case .hiit: "figure.highintensity.intervaltraining"
        }
    }

    var kind: WatchKind {
        switch self {
        case .outdoorRun, .indoorRun: .run
        case .outdoorWalk, .indoorWalk: .walk
        case .poolSwim, .openWaterSwim: .swim
        case .outdoorCycle: .cycle
        case .strength, .hiit: .other
        }
    }

    var usesGPS: Bool { self == .outdoorRun || self == .outdoorWalk || self == .outdoorCycle || self == .openWaterSwim }

    var configuration: HKWorkoutConfiguration {
        let c = HKWorkoutConfiguration()
        switch self {
        case .outdoorRun: c.activityType = .running; c.locationType = .outdoor
        case .indoorRun: c.activityType = .running; c.locationType = .indoor
        case .outdoorWalk: c.activityType = .walking; c.locationType = .outdoor
        case .indoorWalk: c.activityType = .walking; c.locationType = .indoor
        case .poolSwim:
            c.activityType = .swimming
            c.locationType = .indoor
            c.swimmingLocationType = .pool
            let metric = UserDefaults.standard.bool(forKey: "useMetric")
            c.lapLength = metric ? HKQuantity(unit: .meter(), doubleValue: 25)
                                 : HKQuantity(unit: .yard(), doubleValue: 25)
        case .openWaterSwim:
            c.activityType = .swimming
            c.locationType = .outdoor
            c.swimmingLocationType = .openWater
        case .outdoorCycle: c.activityType = .cycling; c.locationType = .outdoor
        case .strength: c.activityType = .traditionalStrengthTraining; c.locationType = .indoor
        case .hiit: c.activityType = .highIntensityIntervalTraining; c.locationType = .indoor
        }
        return c
    }
}

enum WatchKind { case run, walk, swim, cycle, other }

struct WorkoutResult {
    var title: String
    var duration: TimeInterval
    var distance: Double
    var energy: Double
    var averageHeartRate: Double
    var laps: Int
    var kind: WatchKind
}

@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    @Published var current: WatchWorkout?
    @Published var state: HKWorkoutSessionState = .notStarted
    @Published var heartRate: Double = 0
    @Published var averageHeartRate: Double = 0
    @Published var energy: Double = 0
    @Published var distance: Double = 0
    @Published var strokes: Double = 0
    @Published var laps = 0
    @Published var result: WorkoutResult?

    private let store: HKHealthStore
    private var session: HKWorkoutSession?
    private(set) var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let location = CLLocationManager()

    init(store: HKHealthStore) {
        self.store = store
        super.init()
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
    }

    var isActive: Bool { current != nil && result == nil }
    var isPaused: Bool { state == .paused }

    func elapsed(at date: Date) -> TimeInterval { builder?.elapsedTime(at: date) ?? 0 }

    // MARK: Control

    func start(_ workout: WatchWorkout) {
        let config = workout.configuration
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            reset()
            current = workout

            if workout.usesGPS {
                routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
                if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
                location.startUpdatingLocation()
            }

            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }

            if workout.kind == .swim {
                WKInterfaceDevice.current().enableWaterLock()
            }
            WKInterfaceDevice.current().play(.start)
        } catch {
            current = nil
        }
    }

    func togglePause() {
        guard let session else { return }
        if session.state == .running { session.pause() } else { session.resume() }
    }

    func end() {
        session?.end()
        location.stopUpdatingLocation()
    }

    func dismissSummary() {
        result = nil
        current = nil
        session = nil
        builder = nil
        routeBuilder = nil
        state = .notStarted
    }

    private func reset() {
        heartRate = 0; averageHeartRate = 0; energy = 0; distance = 0; strokes = 0; laps = 0
        result = nil
        state = .notStarted
    }

    private func finish(at date: Date) async {
        guard let builder, let workout = current else { return }
        do {
            try await builder.endCollection(at: date)
            let saved = try await builder.finishWorkout()
            if let saved, let routeBuilder {
                _ = try? await routeBuilder.finishRoute(with: saved, metadata: nil)
            }
        } catch {}
        WKInterfaceDevice.current().play(.success)
        result = WorkoutResult(title: workout.title, duration: builder.elapsedTime, distance: distance,
                               energy: energy, averageHeartRate: averageHeartRate, laps: laps, kind: workout.kind)
    }

    // MARK: Live data

    private func update(_ stats: HKStatistics) {
        let type = stats.quantityType
        switch type {
        case HKQuantityType(.heartRate):
            let bpm = HKUnit.count().unitDivided(by: .minute())
            heartRate = stats.mostRecentQuantity()?.doubleValue(for: bpm) ?? heartRate
            averageHeartRate = stats.averageQuantity()?.doubleValue(for: bpm) ?? averageHeartRate
        case HKQuantityType(.activeEnergyBurned):
            energy = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? energy
        case HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming):
            distance = stats.sumQuantity()?.doubleValue(for: .meter()) ?? distance
        case HKQuantityType(.swimmingStrokeCount):
            strokes = stats.sumQuantity()?.doubleValue(for: .count()) ?? strokes
        default:
            break
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            self.state = toState
            if toState == .paused { WKInterfaceDevice.current().play(.stop) }
            if toState == .running, fromState == .paused { WKInterfaceDevice.current().play(.start) }
            if toState == .ended { await self.finish(at: date) }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var all: [HKStatistics] = []
        for type in collectedTypes {
            if let q = type as? HKQuantityType, let stats = workoutBuilder.statistics(for: q) { all.append(stats) }
        }
        Task { @MainActor in all.forEach { self.update($0) } }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        let laps = workoutBuilder.workoutEvents.filter { $0.type == .lap }.count
        Task { @MainActor in self.laps = laps }
    }
}

extension WorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let good = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        guard !good.isEmpty else { return }
        Task { @MainActor in
            guard self.state == .running else { return }
            self.routeBuilder?.insertRouteData(good) { _, _ in }
        }
    }
}
