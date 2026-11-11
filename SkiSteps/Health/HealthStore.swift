import Foundation
import HealthKit
import UserNotifications
import WidgetKit

struct StepPoint: Identifiable, Equatable {
    var date: Date
    var value: Double
    var id: Date { date }
}

/// Reads step data from Apple Health and keeps it live.
@MainActor
final class HealthStore: ObservableObject {
    enum Access { case unknown, needsRequest, ready, unavailable }

    @Published var access: Access = .unknown
    @Published var steps: Double = 0
    @Published var distance: Double = 0      // meters
    @Published var flights: Double = 0
    @Published var energy: Double = 0        // kcal
    @Published var hourly: [StepPoint] = []  // 24 hours of today
    @Published var daily: [StepPoint] = []   // last 400 days, oldest first, today last
    @Published var lastUpdated: Date?

    private let store = HKHealthStore()
    private let cal = Calendar.current
    private var observer: HKObserverQuery?
    private var refreshing = false

    private let stepType = HKQuantityType(.stepCount)
    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.flightsClimbed),
            HKQuantityType(.activeEnergyBurned),
        ]
    }

    var goal: Double {
        let g = UserDefaults.standard.double(forKey: "dailyGoal")
        return g > 0 ? g : 10_000
    }

    init() {
        // Set up the observer right away so iOS can wake the app in the
        // background when new steps arrive (needed for the goal notification
        // and keeping the widget fresh).
        guard HKHealthStore.isHealthDataAvailable() else { return }
        startObserving()
        store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { _, _ in }
    }

    // MARK: - Access

    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            access = .unavailable
            return
        }
        let status = (try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)) ?? .shouldRequest
        if status == .unnecessary {
            access = .ready
            await refresh()
        } else {
            access = .needsRequest
        }
    }

    func requestAccess() async {
        try? await store.requestAuthorization(toShare: [], read: readTypes)
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

        async let s = sum(.stepCount, unit: .count(), from: today, to: now)
        async let d = sum(.distanceWalkingRunning, unit: .meter(), from: today, to: now)
        async let f = sum(.flightsClimbed, unit: .count(), from: today, to: now)
        async let e = sum(.activeEnergyBurned, unit: .kilocalorie(), from: today, to: now)
        async let h = series(.stepCount, unit: .count(), from: today, to: tomorrow, every: DateComponents(hour: 1))
        async let dd = series(.stepCount, unit: .count(), from: historyStart, to: tomorrow, every: DateComponents(day: 1))

        let newSteps = await s
        steps = newSteps
        distance = await d
        flights = await f
        energy = await e
        hourly = await h
        var days = await dd
        // Keep today's bar in step with the headline number.
        if let last = days.indices.last, cal.isDate(days[last].date, inSameDayAs: today) {
            days[last].value = max(days[last].value, newSteps)
        }
        daily = days
        lastUpdated = now

        saveSnapshot()
        notifyIfGoalReached()
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double {
        let store = self.store
        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: HKQuantityType(id),
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
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
            query.initialResultsHandler = { _, results, _ in
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

    private func startObserving() {
        guard observer == nil else { return }
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completion, _ in
            Task { @MainActor in
                await self?.refresh()
                completion()
            }
        }
        observer = query
        store.execute(query)
    }

    // MARK: - Widget + notification

    private func saveSnapshot() {
        let metric = UserDefaults.standard.bool(forKey: "useMetric")
        StepSnapshot(day: Date(), steps: steps, distanceMeters: distance, goal: goal, useMetric: metric).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Call when the goal or units change so the widget updates right away.
    func settingsChanged() {
        saveSnapshot()
    }

    private func notifyIfGoalReached() {
        guard UserDefaults.standard.object(forKey: "goalAlerts") as? Bool ?? true else { return }
        guard steps >= goal else { return }
        let dayKey = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        guard UserDefaults.standard.string(forKey: "lastGoalAlertDay") != dayKey else { return }
        UserDefaults.standard.set(dayKey, forKey: "lastGoalAlertDay")

        let content = UNMutableNotificationContent()
        content.title = "Goal reached! 🎉"
        content.body = "You hit \(Fmt.steps(goal)) steps today. Keep it going!"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "goal-\(dayKey)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Stats

    /// Days in a row the goal was met. Today only counts once it's met,
    /// and an unfinished today doesn't break the streak.
    func streak(goal: Double) -> Int {
        let days = Array(daily.reversed())
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
