import SwiftUI
import HealthKit
import UserNotifications

/// A badge you earn from your Apple Health data.
struct Award: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case steps = "Daily Steps", streaks = "Streaks", lifetime = "Lifetime", distance = "Distance",
             workouts = "Workouts", running = "Running", special = "Special", sleep = "Sleep", monthly = "Monthly"
        var id: Self { self }
    }

    enum Tier: Int { case bronze, silver, gold, platinum, special }

    let id: String
    let title: String
    let detail: String
    let icon: String
    let category: Category
    let tier: Tier
    /// When it was earned (from your data), nil if not yet.
    var earned: Date?
    /// Progress toward it, 0…1, with a readable label like "7,412 / 10,000 steps".
    var progress: Double
    var progressText: String
    /// How many times it's been achieved (for repeatable daily badges).
    var count: Int = 0

    var isEarned: Bool { earned != nil }

    var colors: [Color] {
        switch tier {
        case .bronze: [Color(red: 0.80, green: 0.50, blue: 0.25), Color(red: 0.55, green: 0.30, blue: 0.12)]
        case .silver: [Color(red: 0.85, green: 0.88, blue: 0.92), Color(red: 0.50, green: 0.55, blue: 0.62)]
        case .gold: [Color(red: 1.0, green: 0.85, blue: 0.35), Color(red: 0.85, green: 0.55, blue: 0.10)]
        case .platinum: [Color(red: 0.70, green: 0.95, blue: 1.0), Color(red: 0.45, green: 0.45, blue: 0.95)]
        case .special: [Theme.accent, Theme.accent2]
        }
    }

    static func == (a: Award, b: Award) -> Bool { a.id == b.id && a.earned == b.earned && a.progress == b.progress }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Engine

enum AwardsEngine {
    @MainActor
    static func evaluate(_ health: HealthStore) -> [Award] {
        var out: [Award] = []
        let cal = Calendar.current
        let metric = UserDefaults.standard.bool(forKey: "useMetric")
        let stepGoal = Metric.steps.goal()
        let steps = health.history[.steps] ?? []
        let dist = health.history[.distance] ?? []
        let cals = health.history[.calories] ?? []
        let active = health.history[.active] ?? []
        let workouts = health.workouts.sorted { $0.start < $1.start }
        let nf = NumberFormatter(); nf.numberStyle = .decimal
        func n(_ v: Double) -> String { nf.string(from: NSNumber(value: Int(v.rounded()))) ?? "\(Int(v))" }

        // Daily step thresholds
        let best = steps.map(\.value).max() ?? 0
        for (t, title, tier) in [(5_000.0, "Step It Up", Award.Tier.bronze), (10_000, "10K Club", .silver),
                                 (15_000, "15K Strider", .gold), (20_000, "20K Trailblazer", .gold),
                                 (25_000, "25K Legend", .platinum), (30_000, "30K Unstoppable", .platinum)] {
            let days = steps.filter { $0.value >= t }
            out.append(Award(id: "steps-\(Int(t))", title: title, detail: "Walk \(n(t)) steps in one day.",
                             icon: "figure.walk", category: .steps, tier: tier, earned: days.first?.date,
                             progress: min(best / t, 1), progressText: "Best day: \(n(best)) / \(n(t)) steps",
                             count: days.count))
        }
        let doubles = steps.filter { $0.value >= stepGoal * 2 }
        out.append(Award(id: "double-goal", title: "Double Down", detail: "Hit twice your step goal (\(n(stepGoal * 2)) steps) in a day.",
                         icon: "multiply.circle.fill", category: .steps, tier: .gold, earned: doubles.first?.date,
                         progress: min(best / (stepGoal * 2), 1), progressText: "Best day: \(n(best)) / \(n(stepGoal * 2))",
                         count: doubles.count))

        // Streaks (step goal)
        var run = 0, longest = 0
        var reached: [Int: Date] = [:]
        for p in steps {
            run = p.value >= stepGoal ? run + 1 : 0
            longest = max(longest, run)
            for t in [3, 7, 14, 30, 60, 100, 365] where run == t && reached[t] == nil { reached[t] = p.date }
        }
        let current = health.streak(.steps, goal: stepGoal)
        for (t, title, tier) in [(3, "Getting Started", Award.Tier.bronze), (7, "Week Warrior", .silver),
                                 (14, "Two-Week Titan", .silver), (30, "Monthly Machine", .gold),
                                 (60, "Habit Hero", .gold), (100, "Century Streak", .platinum), (365, "Year of Steps", .platinum)] {
            out.append(Award(id: "streak-\(t)", title: title, detail: "Hit your step goal \(t) days in a row.",
                             icon: "flame.fill", category: .streaks, tier: tier, earned: reached[t],
                             progress: min(Double(max(current, longest)) / Double(t), 1),
                             progressText: "Current streak \(current) · best \(longest) / \(t) days"))
        }

        // Perfect week & all-goals day
        var perfectWeek: Date?
        let byWeek = Dictionary(grouping: steps) { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        for (_, days) in byWeek.sorted(by: { $0.key < $1.key }) where days.count == 7 && days.allSatisfy({ $0.value >= stepGoal }) {
            perfectWeek = days.map(\.date).max(); break
        }
        let thisWeek = steps.filter { cal.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
        out.append(Award(id: "perfect-week", title: "Perfect Week", detail: "Hit your step goal every day of a calendar week.",
                         icon: "calendar.badge.checkmark", category: .streaks, tier: .gold, earned: perfectWeek,
                         progress: Double(thisWeek.filter { $0.value >= stepGoal }.count) / 7,
                         progressText: "This week: \(thisWeek.filter { $0.value >= stepGoal }.count) / 7 days"))

        func value(_ list: [StepPoint], _ d: Date) -> Double { list.first { cal.isDate($0.date, inSameDayAs: d) }?.value ?? 0 }
        let allGoals = steps.filter { p in
            p.value >= stepGoal && value(dist, p.date) >= Metric.distance.goal()
                && value(cals, p.date) >= Metric.calories.goal() && value(active, p.date) >= Metric.active.goal()
        }
        let todayMet = Metric.allCases.filter { health.today($0) >= $0.goal() }.count
        out.append(Award(id: "all-goals", title: "Full House", detail: "Hit all four daily goals — steps, distance, calories and active time — on the same day.",
                         icon: "checkmark.seal.fill", category: .special, tier: .gold, earned: allGoals.first?.date,
                         progress: Double(todayMet) / 4, progressText: "Today: \(todayMet) / 4 goals", count: allGoals.count))

        // Lifetime steps
        var total = 0.0
        var crossed: [Double: Date] = [:]
        let lifetimeTargets: [Double] = [100_000, 250_000, 500_000, 1_000_000, 2_500_000, 5_000_000]
        for p in steps {
            total += p.value
            for t in lifetimeTargets where total >= t && crossed[t] == nil { crossed[t] = p.date }
        }
        let lifetimeInfo: [(Double, String, Award.Tier)] = [
            (100_000, "100K Steps", .bronze), (250_000, "Quarter Million", .silver), (500_000, "Half Million", .silver),
            (1_000_000, "Millionaire", .gold), (2_500_000, "2.5 Million", .platinum), (5_000_000, "5 Million Club", .platinum),
        ]
        for (t, title, tier) in lifetimeInfo {
            out.append(Award(id: "life-\(Int(t))", title: title, detail: "Take \(n(t)) steps in total.",
                             icon: "shoeprints.fill", category: .lifetime, tier: tier, earned: crossed[t],
                             progress: min(total / t, 1), progressText: "\(n(total)) / \(n(t)) steps"))
        }

        // Lifetime distance
        let unitM = metric ? 1000.0 : 1609.344
        let unit = metric ? "km" : "mi"
        let distTargets: [(Double, String, Award.Tier)] = metric
            ? [(42.195, "Marathon Distance", .bronze), (100, "100 km", .silver), (250, "250 km", .silver),
               (500, "500 km", .gold), (1000, "1,000 km", .platinum)]
            : [(26.2, "Marathon Distance", .bronze), (50, "50 Miles", .silver), (100, "Century", .silver),
               (250, "250 Miles", .gold), (500, "500 Miles", .gold), (1000, "1,000 Miles", .platinum)]
        var dTotal = 0.0
        var dCrossed: [Double: Date] = [:]
        for p in dist {
            dTotal += p.value / unitM
            for (t, _, _) in distTargets where dTotal >= t && dCrossed[t] == nil { dCrossed[t] = p.date }
        }
        for (t, title, tier) in distTargets {
            out.append(Award(id: "dist-\(unit)-\(Int(t))", title: title,
                             detail: "Walk and run \(t == 42.195 || t == 26.2 ? "a marathon's distance" : "\(n(t)) \(unit)") in total.",
                             icon: "map.fill", category: .distance, tier: tier, earned: dCrossed[t],
                             progress: min(dTotal / t, 1), progressText: String(format: "%.1f / %@ %@", dTotal, t == 42.195 ? "42.2" : n(t), unit)))
        }

        // Workouts
        for (t, title, tier) in [(1, "First Workout", Award.Tier.bronze), (10, "Ten Down", .bronze),
                                 (25, "Committed", .silver), (50, "Fifty Strong", .gold), (100, "Centurion", .platinum)] {
            out.append(Award(id: "workouts-\(t)", title: title, detail: t == 1 ? "Record your first workout." : "Complete \(t) workouts.",
                             icon: "trophy.fill", category: .workouts, tier: tier,
                             earned: workouts.count >= t ? workouts[t - 1].start : nil,
                             progress: min(Double(workouts.count) / Double(t), 1), progressText: "\(workouts.count) / \(t) workouts"))
        }
        let gym = workouts.filter { $0.workout.metadata?["SkiStepsGymLog"] != nil || $0.type == .traditionalStrengthTraining }
        out.append(Award(id: "gym-1", title: "Iron Starter", detail: "Log your first gym workout.", icon: "dumbbell.fill",
                         category: .workouts, tier: .bronze, earned: gym.first?.start,
                         progress: gym.isEmpty ? 0 : 1, progressText: "\(gym.count) gym workouts"))
        out.append(Award(id: "gym-10", title: "Gym Regular", detail: "Log 10 gym workouts.", icon: "dumbbell.fill",
                         category: .workouts, tier: .silver, earned: gym.count >= 10 ? gym[9].start : nil,
                         progress: min(Double(gym.count) / 10, 1), progressText: "\(gym.count) / 10 gym workouts"))
        let circuits = workouts.filter { [.highIntensityIntervalTraining, .functionalStrengthTraining, .coreTraining].contains($0.type) }
        out.append(Award(id: "circuit-1", title: "Circuit Breaker", detail: "Finish a guided circuit or HIIT workout.", icon: "bolt.heart.fill",
                         category: .workouts, tier: .bronze, earned: circuits.first?.start,
                         progress: circuits.isEmpty ? 0 : 1, progressText: "\(circuits.count) circuits"))
        let swims = workouts.filter { $0.kind == .swimming }
        out.append(Award(id: "swim-1", title: "Making Waves", detail: "Record your first swim.", icon: "figure.pool.swim",
                         category: .workouts, tier: .silver, earned: swims.first?.start,
                         progress: swims.isEmpty ? 0 : 1, progressText: "\(swims.count) swims"))

        // Running
        let runs = workouts.filter { $0.kind == .running }
        let longestRun = runs.map(\.distance).max() ?? 0
        for (m, title, tier) in [(1.0, "First Run", Award.Tier.bronze), (5_000.0, "5K Finisher", .silver),
                                 (10_000.0, "10K Finisher", .gold), (21_097.5, "Half Marathoner", .platinum)] {
            let hit = runs.first { $0.distance >= m }
            let label = m == 1 ? "Record your first run." : "Run \(m == 21_097.5 ? "a half marathon (21.1 km)" : "\(Int(m / 1000)) km") in one go."
            out.append(Award(id: "run-\(Int(m))", title: title, detail: label, icon: "figure.run",
                             category: .running, tier: tier, earned: hit?.start,
                             progress: m == 1 ? (runs.isEmpty ? 0 : 1) : min(longestRun / m, 1),
                             progressText: m == 1 ? "\(runs.count) runs" : String(format: "Longest: %.2f / %.1f km", longestRun / 1000, m / 1000)))
        }

        // Special
        let early = workouts.first { cal.component(.hour, from: $0.start) < 6 }
        out.append(Award(id: "early-bird", title: "Early Bird", detail: "Start a workout before 6 AM.", icon: "sunrise.fill",
                         category: .special, tier: .special, earned: early?.start,
                         progress: early == nil ? 0 : 1, progressText: early == nil ? "Not yet" : "Done"))
        let owl = workouts.first { cal.component(.hour, from: $0.start) >= 21 }
        out.append(Award(id: "night-owl", title: "Night Owl", detail: "Start a workout after 9 PM.", icon: "moon.stars.fill",
                         category: .special, tier: .special, earned: owl?.start,
                         progress: owl == nil ? 0 : 1, progressText: owl == nil ? "Not yet" : "Done"))
        var weekend: Date?
        let sats = Set(workouts.filter { cal.component(.weekday, from: $0.start) == 7 }.map { cal.startOfDay(for: $0.start) })
        for w in workouts where cal.component(.weekday, from: w.start) == 1 {
            let sat = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: w.start))!
            if sats.contains(sat) { weekend = w.start; break }
        }
        out.append(Award(id: "weekend-warrior", title: "Weekend Warrior", detail: "Work out on both Saturday and Sunday of the same weekend.",
                         icon: "figure.mixed.cardio", category: .special, tier: .special, earned: weekend,
                         progress: weekend == nil ? 0 : 1, progressText: weekend == nil ? "Not yet" : "Done"))
        let bestCal = cals.map(\.value).max() ?? 0
        for (t, title, tier) in [(500.0, "Calorie Crusher", Award.Tier.silver), (1000, "Inferno", .gold)] {
            out.append(Award(id: "cal-\(Int(t))", title: title, detail: "Burn \(Int(t)) active calories in one day.", icon: "flame.circle.fill",
                             category: .special, tier: tier, earned: cals.first { $0.value >= t }?.date,
                             progress: min(bestCal / t, 1), progressText: "Best day: \(n(bestCal)) / \(Int(t)) cal"))
        }
        let bestActive = active.map(\.value).max() ?? 0
        out.append(Award(id: "active-60", title: "Power Hour", detail: "Get 60 active minutes in one day.", icon: "timer",
                         category: .special, tier: .silver, earned: active.first { $0.value >= 60 }?.date,
                         progress: min(bestActive / 60, 1), progressText: "Best day: \(Int(bestActive)) / 60 min"))

        // Sleep
        let nights = health.nights
        let sleepGoal = { let g = UserDefaults.standard.double(forKey: "sleepGoal"); return g > 0 ? g : 8 }() * 3600
        let goodNight = nights.first { $0.asleep >= 8 * 3600 }
        let bestNight = nights.map(\.asleep).max() ?? 0
        out.append(Award(id: "sleep-8", title: "Well Rested", detail: "Sleep 8 hours in one night.", icon: "bed.double.fill",
                         category: .sleep, tier: .silver, earned: goodNight?.day,
                         progress: min(bestNight / (8 * 3600), 1), progressText: "Best night: \(SleepFmt.hours(bestNight)) / 8h"))
        var sRun = 0, sBest = 0
        var sleepWeek: Date?
        for nt in nights {
            sRun = nt.asleep >= sleepGoal ? sRun + 1 : 0
            sBest = max(sBest, sRun)
            if sRun == 7, sleepWeek == nil { sleepWeek = nt.day }
        }
        out.append(Award(id: "sleep-week", title: "Dream Week", detail: "Meet your sleep goal 7 nights in a row.", icon: "moon.zzz.fill",
                         category: .sleep, tier: .gold, earned: sleepWeek,
                         progress: min(Double(sBest) / 7, 1), progressText: "Best run: \(sBest) / 7 nights"))

        // This month's challenge
        let monthDays = cal.range(of: .day, in: .month, for: .now)?.count ?? 30
        let monthTarget = (stepGoal * Double(monthDays) * 0.8 / 10_000).rounded() * 10_000
        let monthSteps = steps.filter { cal.isDate($0.date, equalTo: .now, toGranularity: .month) }.map(\.value).reduce(0, +)
        var monthDone: Date?
        var acc = 0.0
        for p in steps where cal.isDate(p.date, equalTo: .now, toGranularity: .month) {
            acc += p.value
            if acc >= monthTarget, monthDone == nil { monthDone = p.date }
        }
        let monthName = Date.now.formatted(.dateTime.month(.wide))
        out.append(Award(id: "month-\(Date.now.formatted(.dateTime.year().month(.twoDigits)))",
                         title: "\(monthName) Challenge", detail: "Walk \(n(monthTarget)) steps in \(monthName).",
                         icon: "calendar", category: .monthly, tier: .special, earned: monthDone,
                         progress: min(monthSteps / max(monthTarget, 1), 1),
                         progressText: "\(n(monthSteps)) / \(n(monthTarget)) steps"))

        return out
    }

    /// Sends a notification for awards earned since the last check.
    /// The first time it runs it just remembers what's already earned.
    @MainActor
    static func notifyNew(_ awards: [Award]) -> [String] {
        let key = "awardsSeen.v1"
        let earned = awards.filter(\.isEarned)
        guard let seenList = UserDefaults.standard.stringArray(forKey: key) else {
            UserDefaults.standard.set(earned.map(\.id), forKey: key)
            return []
        }
        var seen = Set(seenList)
        let fresh = earned.filter { !seen.contains($0.id) }
        for a in fresh {
            seen.insert(a.id)
            let content = UNMutableNotificationContent()
            content.title = "🏅 New award: \(a.title)"
            content.body = a.detail
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "award-\(a.id)", content: content, trigger: nil))
        }
        UserDefaults.standard.set(Array(seen), forKey: key)
        var recent = UserDefaults.standard.stringArray(forKey: "awardsNew") ?? []
        recent = fresh.map(\.id) + recent.filter { id in !fresh.contains { $0.id == id } }
        UserDefaults.standard.set(Array(recent.prefix(10)), forKey: "awardsNew")
        return fresh.map(\.id)
    }
}
