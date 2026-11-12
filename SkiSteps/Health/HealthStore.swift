import Foundation
import HealthKit
import CoreLocation
import UserNotifications
import WidgetKit
import UIKit
import MapKit

struct DayCurve {
    var today: [StepPoint]
    var average: [StepPoint]
    var todayTotal: Double
    var averageNow: Double
    static let empty = DayCurve(today: [], average: [], todayTotal: 0, averageNow: 0)
}

/// Draws a route on a dark map snapshot.
enum RouteSnapshot {
    static func make(_ coords: [CLLocationCoordinate2D], size: CGSize) async -> UIImage? {
        let poly = MKPolyline(coordinates: coords, count: coords.count)
        var rect = poly.boundingMapRect
        let pad = max(rect.size.width, rect.size.height) * 0.25 + 300
        rect = rect.insetBy(dx: -pad, dy: -pad)
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll
        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { cont in
            snapshotter.start { snap, _ in cont.resume(returning: snap) }
        }
        guard let snapshot else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            snapshot.image.draw(at: .zero)
            let path = UIBezierPath()
            for (i, c) in coords.enumerated() {
                let p = snapshot.point(for: c)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.lineWidth = 7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.black.withAlphaComponent(0.6).setStroke()
            path.stroke()
            path.lineWidth = 4.5
            UIColor(red: 1.0, green: 0.48, blue: 0.36, alpha: 1).setStroke()
            path.stroke()
        }
    }
}

struct DeviceSteps: Identifiable {
    var name: String
    var value: Double
    var isWatch: Bool
    var id: String { name }
}

struct StepPoint: Identifiable, Equatable {
    var date: Date
    var value: Double
    var id: Date { date }
}

/// Reads data from Apple Health and keeps it live.
@MainActor
final class HealthStore: ObservableObject {
    enum Access { case unknown, needsRequest, ready, unavailable }

    @Published var access: Access = .unknown
    @Published var steps: Double = 0
    @Published var distance: Double = 0      // meters
    @Published var flights: Double = 0
    @Published var energy: Double = 0        // kcal
    @Published var activeMinutes: Double = 0 // minutes
    @Published var hourly: [StepPoint] = []  // 24 hours of today
    @Published var history: [Metric: [StepPoint]] = [:]  // last 400 days per metric, oldest first
    @Published var workouts: [WorkoutSummary] = []
    @Published var stepsByDevice: [DeviceSteps] = []
    @Published var restingEnergy: Double = 0
    @Published var energyCurve: DayCurve = .empty
    @Published var exerciseCurve: DayCurve = .empty
    @Published var restingHR: Double = 60
    @Published var maxHR: Double = 190
    @Published var training: TrainingLoad = .empty
    @Published var nights: [SleepNight] = []

    private var routeImages: [UUID: UIImage] = [:]
    private var placeNames: [UUID: String] = [:]
    private var noRoute: Set<UUID> = []
    @Published var lastUpdated: Date?
    @Published var lastError: String?

    let store = HKHealthStore()
    let detector = RunDetector()
    private let cal = Calendar.current
    private var observers: [HKObserverQuery] = []
    private var refreshing = false

    private static let quantityIDs: [Metric: (HKQuantityTypeIdentifier, HKUnit)] = [
        .steps: (.stepCount, .count()),
        .distance: (.distanceWalkingRunning, .meter()),
        .calories: (.activeEnergyBurned, .kilocalorie()),
        .active: (.appleExerciseTime, .minute()),
    ]

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.flightsClimbed),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.bodyMass),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.swimmingStrokeCount),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.basalEnergyBurned),
            HKCategoryType(.sleepAnalysis),
            HKCharacteristicType(.dateOfBirth),
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
    }

    private var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.activeEnergyBurned),
        ]
    }

    var daily: [StepPoint] { history[.steps] ?? [] }
    var healthReadTypes: Set<HKObjectType> { readTypes }
    var healthShareTypes: Set<HKSampleType> { shareTypes }

    /// Remembers a Health error so it can be shown instead of silently showing zeros.
    nonisolated func note(_ error: Error?) {
        guard let error, (error as? HKError)?.code != .errorNoData else { return }
        let text = error.localizedDescription
        Task { @MainActor in self.lastError = text }
    }

    init() {
        // Observers are set up right away so iOS can wake the app in the
        // background when new data arrives (goal alerts + fresh widget).
        guard HKHealthStore.isHealthDataAvailable() else { return }
        startObserving()
    }

    func today(_ m: Metric) -> Double {
        switch m {
        case .steps: steps
        case .distance: distance
        case .calories: energy
        case .active: activeMinutes
        }
    }

    // MARK: - Access

    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            access = .unavailable
            return
        }
        let status = (try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)) ?? .shouldRequest
        if status == .unnecessary {
            access = .ready
            await refresh()
        } else {
            access = .needsRequest
        }
    }

    func requestAccess() async {
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        access = .ready
        await refresh()
    }

    // MARK: - Loading

    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable(), !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let now = Date()
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let historyStart = cal.date(byAdding: .day, value: -399, to: today)!
        let day = DateComponents(day: 1)

        async let s = sum(.stepCount, unit: .count(), from: today, to: now)
        async let d = sum(.distanceWalkingRunning, unit: .meter(), from: today, to: now)
        async let f = sum(.flightsClimbed, unit: .count(), from: today, to: now)
        async let e = sum(.activeEnergyBurned, unit: .kilocalorie(), from: today, to: now)
        async let a = sum(.appleExerciseTime, unit: .minute(), from: today, to: now)
        async let h = series(.stepCount, unit: .count(), from: today, to: tomorrow, every: DateComponents(hour: 1))
        async let hs = series(.stepCount, unit: .count(), from: historyStart, to: tomorrow, every: day)
        async let hd = series(.distanceWalkingRunning, unit: .meter(), from: historyStart, to: tomorrow, every: day)
        async let he = series(.activeEnergyBurned, unit: .kilocalorie(), from: historyStart, to: tomorrow, every: day)
        async let ha = series(.appleExerciseTime, unit: .minute(), from: historyStart, to: tomorrow, every: day)
        async let r = loadWorkouts()
        async let bySource = stepsBySource(from: today, to: now)
        async let basal = sum(.basalEnergyBurned, unit: .kilocalorie(), from: today, to: now)
        async let eCurve = curve(.activeEnergyBurned, unit: .kilocalorie())
        async let xCurve = curve(.appleExerciseTime, unit: .minute())
        async let sleep = loadSleep()
        async let rhr = latest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))

        steps = await s
        distance = await d
        flights = await f
        energy = await e
        activeMinutes = await a
        hourly = await h

        let stepsHistory = await hs
        let distanceHistory = await hd
        let energyHistory = await he
        let activeHistory = await ha
        var all: [Metric: [StepPoint]] = [.steps: stepsHistory, .distance: distanceHistory,
                                          .calories: energyHistory, .active: activeHistory]
        // Keep today's bar in step with the headline numbers.
        for m in Metric.allCases {
            if var pts = all[m], let last = pts.indices.last, cal.isDate(pts[last].date, inSameDayAs: today) {
                pts[last].value = max(pts[last].value, self.today(m))
                all[m] = pts
            }
        }
        history = all
        workouts = await r
        stepsByDevice = await bySource
        restingEnergy = await basal
        energyCurve = await eCurve
        exerciseCurve = await xCurve
        if let r = await rhr, r > 30 { restingHR = r }
        if let dob = try? store.dateOfBirthComponents().date,
           let age = cal.dateComponents([.year], from: dob, to: now).year, age > 5 {
            maxHR = Double(220 - age)
        }
        nights = await sleep
        training = TrainingLoad.compute(workouts: workouts, restingHR: restingHR, maxHR: maxHR)
        await detector.scan(existing: workouts)
        if await autoSaveDetected() {
            workouts = await loadWorkouts()
        }
        lastUpdated = now

        saveSnapshot()
        notifyGoals()
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double {
        let store = self.store
        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: HKQuantityType(id),
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { [weak self] _, stats, error in
                self?.note(error)
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    /// Today's running total by hour, next to the average running total of the last 28 days.
    private func curve(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> DayCurve {
        let now = Date()
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -28, to: today)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let points = await series(id, unit: unit, from: start, to: tomorrow, every: DateComponents(hour: 1))

        var byDay: [Date: [Double]] = [:]
        for p in points {
            let day = cal.startOfDay(for: p.date)
            let hour = cal.component(.hour, from: p.date)
            var arr = byDay[day] ?? Array(repeating: 0, count: 24)
            arr[hour] += p.value
            byDay[day] = arr
        }
        func cumulative(_ a: [Double]) -> [Double] {
            var total = 0.0
            return a.map { total += $0; return total }
        }
        let past = byDay.filter { $0.key < today }.map { cumulative($0.value) }
        var avg = Array(repeating: 0.0, count: 24)
        if !past.isEmpty {
            for h in 0..<24 { avg[h] = past.map { $0[h] }.reduce(0, +) / Double(past.count) }
        }
        let todayCum = cumulative(byDay[today] ?? Array(repeating: 0, count: 24))
        let nowHour = cal.component(.hour, from: now)
        func date(_ h: Int) -> Date { cal.date(byAdding: .hour, value: h + 1, to: today)! }
        var todayPts = [StepPoint(date: today, value: 0)]
        todayPts += (0...nowHour).map { StepPoint(date: $0 == nowHour ? now : date($0), value: todayCum[$0]) }
        var avgPts = [StepPoint(date: today, value: 0)]
        avgPts += (0..<24).map { StepPoint(date: date($0), value: avg[$0]) }
        // Average up to this moment, interpolated within the current hour.
        let frac = now.timeIntervalSince(cal.date(byAdding: .hour, value: nowHour, to: today)!) / 3600
        let before = nowHour > 0 ? avg[nowHour - 1] : 0
        let avgNow = before + (avg[nowHour] - before) * frac
        return DayCurve(today: todayPts, average: avgPts, todayTotal: todayCum[nowHour], averageNow: avgNow)
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let store = self.store
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let q = HKSampleQuery(sampleType: HKQuantityType(id), predicate: nil, limit: 1, sortDescriptors: [sort]) { _, s, _ in
                cont.resume(returning: (s?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    // MARK: - Route previews

    /// A small map image of the workout's route, cached.
    func routeImage(for w: WorkoutSummary, size: CGSize) async -> UIImage? {
        if let img = routeImages[w.id] { return img }
        if noRoute.contains(w.id) { return nil }
        let points = await route(for: w.workout)
        guard points.count > 1 else { noRoute.insert(w.id); return nil }
        let img = await RouteSnapshot.make(points.map(\.coordinate), size: size)
        routeImages[w.id] = img
        if placeNames[w.id] == nil, let first = points.first {
            let place = try? await CLGeocoder().reverseGeocodeLocation(first).first
            if let name = place?.locality ?? place?.name { placeNames[w.id] = name }
        }
        return img
    }

    func placeName(for w: WorkoutSummary) -> String? { placeNames[w.id] }

    private func stepsBySource(from start: Date, to end: Date) async -> [DeviceSteps] {
        let store = self.store
        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: HKQuantityType(.stepCount),
                                          quantitySamplePredicate: predicate,
                                          options: [.cumulativeSum, .separateBySource]) { _, stats, _ in
                let list = (stats?.sources ?? []).compactMap { source -> DeviceSteps? in
                    let v = stats?.sumQuantity(for: source)?.doubleValue(for: .count()) ?? 0
                    guard v > 0 else { return nil }
                    return DeviceSteps(name: source.name, value: v,
                                       isWatch: source.name.localizedCaseInsensitiveContains("watch"))
                }
                cont.resume(returning: list.sorted { $0.value > $1.value })
            }
            store.execute(query)
        }
    }

    private func series(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date,
                        every interval: DateComponents) async -> [StepPoint] {
        let store = self.store
        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsCollectionQuery(quantityType: HKQuantityType(id),
                                                    quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum,
                                                    anchorDate: start,
                                                    intervalComponents: interval)
            query.initialResultsHandler = { [weak self] _, results, error in
                self?.note(error)
                var points: [StepPoint] = []
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    points.append(StepPoint(date: stats.startDate,
                                            value: stats.sumQuantity()?.doubleValue(for: unit) ?? 0))
                }
                cont.resume(returning: points)
            }
            store.execute(query)
        }
    }

    private func loadWorkouts() async -> [WorkoutSummary] {
        let store = self.store
        let start = cal.date(byAdding: .day, value: -400, to: Date())!
        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1000,
                                      sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout] ?? []).map { WorkoutSummary(workout: $0) })
            }
            store.execute(query)
        }
    }

    /// Saves a run to Apple Health: from the run recorder (with GPS route)
    /// or from an auto-detected run (no route).
    func saveRun(start: Date, end: Date, meters: Double, locations: [CLLocation] = [],
                 pauses: [DateInterval] = [], detected: Bool = false) async throws {
        try await saveWorkout(.running, start: start, end: end, meters: meters, locations: locations,
                              pauses: pauses, metadata: detected ? ["SkiStepsAutoDetected": true] : [:])
    }

    /// Saves any workout to Apple Health.
    /// - kcal: active calories; when nil, estimated from distance for runs and walks.
    func saveWorkout(_ activity: HKWorkoutActivityType, start: Date, end: Date,
                     meters: Double = 0, distanceType: HKQuantityTypeIdentifier = .distanceWalkingRunning,
                     kcal: Double? = nil, indoor: Bool? = nil, locations: [CLLocation] = [],
                     pauses: [DateInterval] = [], events: [HKWorkoutEvent] = [],
                     metadata: [String: Any] = [:], refreshAfter: Bool = true) async throws {
        var energy = kcal ?? 0
        if kcal == nil {
            let kg = await bodyMassKg()
            switch activity {
            case .running: energy = kg * (meters / 1000) * 1.0
            case .walking, .hiking: energy = kg * (meters / 1000) * 0.5
            default: energy = 0
            }
        }

        let config = HKWorkoutConfiguration()
        config.activityType = activity
        if let indoor {
            config.locationType = indoor ? .indoor : .outdoor
        } else {
            config.locationType = locations.isEmpty ? .unknown : .outdoor
        }
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: start)

        var samples: [HKSample] = []
        if meters > 0 {
            samples.append(HKQuantitySample(type: HKQuantityType(distanceType),
                                            quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                                            start: start, end: end))
        }
        if energy > 0 {
            samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy),
                                            start: start, end: end))
        }
        if !samples.isEmpty { try await builder.addSamples(samples) }

        var allEvents = events
        allEvents += pauses.flatMap { p in
            [HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: p.start, duration: 0), metadata: nil),
             HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: p.end, duration: 0), metadata: nil)]
        }
        if !allEvents.isEmpty { try await builder.addWorkoutEvents(allEvents) }

        var meta = metadata
        if let indoor { meta[HKMetadataKeyIndoorWorkout] = indoor }
        if !meta.isEmpty { try await builder.addMetadata(meta) }

        try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else { return }

        if locations.count > 1 {
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            try await routeBuilder.insertRouteData(locations)
            _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
        }
        if refreshAfter { await refresh() }
    }

    /// Saves runs and walks the phone detected, when auto-save is on.
    private func autoSaveDetected() async -> Bool {
        var saved = false
        for run in detector.toAutoSave {
            do {
                try await saveWorkout(run.activity, start: run.start, end: run.end, meters: run.meters,
                                      locations: routePoints(for: run),
                                      metadata: ["SkiStepsAutoDetected": true], refreshAfter: false)
                detector.dismiss(run)
                detector.notifySaved(run)
                saved = true
            } catch {
                lastError = "Couldn't save a detected \(run.title.lowercased()): \(error.localizedDescription)"
            }
        }
        return saved
    }

    /// GPS points the background recorder captured during a detected run/walk.
    func routePoints(for run: DetectedRun) -> [CLLocation] {
        RouteRecorder.shared.points(from: run.start.addingTimeInterval(-30), to: run.end.addingTimeInterval(30))
    }

    /// Deletes a workout Ski Steps saved (e.g. a detected walk that wasn't one).
    func deleteWorkout(_ summary: WorkoutSummary) async throws {
        try await store.delete(summary.workout)
        detector.forget(start: summary.start)
        workouts.removeAll { $0.id == summary.id }
        await refresh()
    }

    /// GPS points for a workout, if it has a route.
    func route(for workout: HKWorkout) async -> [CLLocation] {
        let store = self.store
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(),
                                      predicate: HKQuery.predicateForObjects(from: workout),
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }
            store.execute(query)
        }
        var all: [CLLocation] = []
        for route in routes {
            let points: [CLLocation] = await withCheckedContinuation { cont in
                var collected: [CLLocation] = []
                var finished = false
                let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    guard !finished else { return }
                    collected.append(contentsOf: locations ?? [])
                    if done || error != nil {
                        finished = true
                        cont.resume(returning: collected)
                    }
                }
                store.execute(query)
            }
            all.append(contentsOf: points)
        }
        return all.sorted { $0.timestamp < $1.timestamp }
    }

    /// Latest body weight in kg (for calorie estimates on recorded runs).
    func bodyMassKg() async -> Double {
        let store = self.store
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: HKQuantityType(.bodyMass), predicate: nil, limit: 1,
                                      sortDescriptors: [sort]) { _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                cont.resume(returning: kg ?? 75)
            }
            store.execute(query)
        }
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        let types: [HKSampleType] = [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned),
                                     HKQuantityType(.appleExerciseTime), .workoutType()]
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                Task { @MainActor in
                    await self?.refresh()
                    completion()
                }
            }
            observers.append(query)
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    // MARK: - Widget + notifications

    private func saveSnapshot() {
        let metric = UserDefaults.standard.bool(forKey: "useMetric")
        var goals: [String: Double] = [:]
        for m in Metric.allCases { goals[m.rawValue] = m.goal() }
        StepSnapshot(day: Date(), steps: steps, distanceMeters: distance, energy: energy,
                     activeMinutes: activeMinutes, goals: goals, useMetric: metric).save()
        WidgetCenter.shared.reloadAllTimelines()
        WatchLink.shared.sendSettings()
    }

    /// Call when a goal or units change so the widget updates right away.
    func settingsChanged() {
        saveSnapshot()
    }

    private func notifyGoals() {
        guard UserDefaults.standard.object(forKey: "goalAlerts") as? Bool ?? true else { return }
        let dayKey = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let useMetric = UserDefaults.standard.bool(forKey: "useMetric")
        for m in Metric.allCases {
            let goal = m.goal()
            guard today(m) >= goal else { continue }
            let key = "lastGoalAlert.\(m.rawValue)"
            guard UserDefaults.standard.string(forKey: key) != dayKey else { continue }
            UserDefaults.standard.set(dayKey, forKey: key)

            let content = UNMutableNotificationContent()
            let goalText = "\(m.text(m.display(goal, useMetric: useMetric))) \(m.unit(useMetric: useMetric))"
            switch m {
            case .steps: content.title = "Step goal reached! 🎉"
            case .distance: content.title = "Distance goal reached! 📍"
            case .calories: content.title = "Calorie goal reached! 🔥"
            case .active: content.title = "Active time goal reached! ⏱️"
            }
            content.body = "You hit \(goalText) today. Keep it going!"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "goal-\(m.rawValue)-\(dayKey)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Stats

    /// Days in a row the goal was met. Today only counts once it's met,
    /// and an unfinished today doesn't break the streak.
    func streak(_ m: Metric = .steps, goal: Double) -> Int {
        let days = Array((history[m] ?? []).reversed())
        guard !days.isEmpty else { return 0 }
        var i = days[0].value >= goal ? 0 : 1
        var count = 0
        while i < days.count, days[i].value >= goal {
            count += 1
            i += 1
        }
        return count
    }

    var bestDay: StepPoint? { daily.max { $0.value < $1.value } }

    var hasAnyData: Bool { steps > 0 || daily.contains { $0.value > 0 } }
}
