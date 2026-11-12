import SwiftUI
import HealthKit

/// The second big batch of awards: walking, journeys, goal days, effort,
/// variety, cycling, swimming, more running and sleep, holidays and past months.
extension AwardsEngine {
    @MainActor
    static func evaluateMore(_ health: HealthStore) -> [Award] {
        var out: [Award] = []
        let cal = Calendar.current
        let metric = UserDefaults.standard.bool(forKey: "useMetric")
        let steps = health.history[.steps] ?? []
        let dist = health.history[.distance] ?? []
        let cals = health.history[.calories] ?? []
        let active = health.history[.active] ?? []
        let workouts = health.workouts.sorted { $0.start < $1.start }
        let nf = NumberFormatter(); nf.numberStyle = .decimal
        func n(_ v: Double) -> String { nf.string(from: NSNumber(value: Int(v.rounded()))) ?? "\(Int(v))" }
        let mile = 1609.344
        func miles(_ m: Double) -> String {
            metric ? String(format: "%.1f km", m / 1000) : String(format: "%.1f mi", m / mile)
        }

        /// Badge for reaching `target` on a running total (or a count), with the date it was crossed.
        func milestone(_ id: String, _ title: String, _ detail: String, _ icon: String, _ cat: Award.Category,
                       _ tier: Award.Tier, value: Double, target: Double, date: Date?, label: String) -> Award {
            Award(id: id, title: title, detail: detail, icon: icon, category: cat, tier: tier,
                  earned: value >= target ? date : nil, progress: min(value / max(target, 0.0001), 1), progressText: label)
        }

        /// Date when a running sum over `points` first reaches `target`.
        func crossing(_ points: [StepPoint], _ target: Double, scale: Double = 1) -> Date? {
            var acc = 0.0
            for p in points { acc += p.value * scale; if acc >= target { return p.date } }
            return nil
        }

        // MARK: Bigger step days
        let best = steps.map(\.value).max() ?? 0
        for (t, title, tier) in [(35_000.0, "35K Marathoner", Award.Tier.platinum), (40_000, "40K Ultra Day", .platinum),
                                 (50_000, "50K Mythic", .platinum)] {
            let days = steps.filter { $0.value >= t }
            out.append(Award(id: "steps-\(Int(t))", title: title, detail: "Walk \(n(t)) steps in one day.",
                             icon: "figure.walk.motion", category: .steps, tier: tier, earned: days.first?.date,
                             progress: min(best / t, 1), progressText: "Best day: \(n(best)) / \(n(t)) steps", count: days.count))
        }
        // New personal record (after you have 30 days of history)
        var record = 0.0, prDate: Date?, prCount = 0
        for (i, p) in steps.enumerated() {
            if p.value > record {
                if i >= 30, p.value > 0 { prDate = prDate ?? p.date; prCount += 1 }
                record = p.value
            }
        }
        out.append(Award(id: "personal-best", title: "Personal Best", detail: "Beat your all-time best step day.",
                         icon: "chart.line.uptrend.xyaxis", category: .steps, tier: .gold, earned: prDate,
                         progress: prDate == nil ? min((steps.last?.value ?? 0) / max(record, 1), 1) : 1,
                         progressText: "Record: \(n(record)) steps", count: prCount))

        // MARK: Goal days (total days you hit each goal)
        for m in Metric.allCases {
            let goal = m.goal()
            let list = health.history[m] ?? []
            let hits = list.filter { $0.value >= goal }
            let name: String
            let icon: String
            switch m {
            case .steps: name = "Step"; icon = "figure.walk"
            case .distance: name = "Distance"; icon = "location.fill"
            case .calories: name = "Calorie"; icon = "flame.fill"
            case .active: name = "Active"; icon = "timer"
            }
            let targets: [(Int, Award.Tier)] = m == .steps
                ? [(10, .bronze), (50, .silver), (100, .gold), (250, .platinum), (365, .platinum)]
                : [(10, .bronze), (50, .silver), (100, .gold)]
            for (t, tier) in targets {
                out.append(Award(id: "goaldays-\(m.rawValue)-\(t)", title: "\(t) \(name) Goal Days",
                                 detail: "Hit your \(m.title.lowercased()) goal on \(t) different days.",
                                 icon: icon, category: .goals, tier: tier,
                                 earned: hits.count >= t ? hits[t - 1].date : nil,
                                 progress: min(Double(hits.count) / Double(t), 1), progressText: "\(hits.count) / \(t) days"))
            }
            if m != .steps {
                var r = 0, longest = 0, hit7: Date?
                for p in list {
                    r = p.value >= goal ? r + 1 : 0
                    longest = max(longest, r)
                    if r == 7, hit7 == nil { hit7 = p.date }
                }
                out.append(Award(id: "streak7-\(m.rawValue)", title: "\(name) Week Streak",
                                 detail: "Hit your \(m.title.lowercased()) goal 7 days in a row.",
                                 icon: "flame.fill", category: .streaks, tier: .silver, earned: hit7,
                                 progress: min(Double(longest) / 7, 1), progressText: "Best run: \(longest) / 7 days"))
            }
        }
        // Comeback: hit the goal after missing it 7+ days
        var missed = 0, comeback: Date?
        for p in steps {
            if p.value >= Metric.steps.goal() {
                if missed >= 7, comeback == nil { comeback = p.date }
                missed = 0
            } else { missed += 1 }
        }
        out.append(Award(id: "comeback", title: "The Comeback", detail: "Hit your step goal after a week or more of missing it.",
                         icon: "arrow.uturn.up.circle.fill", category: .goals, tier: .special, earned: comeback,
                         progress: comeback == nil ? 0 : 1, progressText: comeback == nil ? "Not yet" : "Done"))
        // Weekend steps
        var weekendDate: Date?
        for p in steps where cal.component(.weekday, from: p.date) == 1 && p.value >= Metric.steps.goal() {
            let sat = cal.date(byAdding: .day, value: -1, to: p.date)!
            if steps.contains(where: { cal.isDate($0.date, inSameDayAs: sat) && $0.value >= Metric.steps.goal() }) {
                weekendDate = p.date; break
            }
        }
        out.append(Award(id: "weekend-steps", title: "Weekend Strider", detail: "Hit your step goal on both Saturday and Sunday.",
                         icon: "sun.max.fill", category: .goals, tier: .silver, earned: weekendDate,
                         progress: weekendDate == nil ? 0 : 1, progressText: weekendDate == nil ? "Not yet" : "Done"))

        // MARK: Lifetime extras
        let totalSteps = steps.map(\.value).reduce(0, +)
        for (t, title) in [(10_000_000.0, "10 Million Club")] {
            out.append(milestone("life-\(Int(t))", title, "Take \(n(t)) steps in total.", "shoeprints.fill", .lifetime, .platinum,
                                 value: totalSteps, target: t, date: crossing(steps, t), label: "\(n(totalSteps)) / \(n(t)) steps"))
        }
        let totalCal = cals.map(\.value).reduce(0, +)
        for (t, title, tier) in [(10_000.0, "Spark", Award.Tier.bronze), (50_000, "Bonfire", .silver),
                                 (100_000, "Furnace", .gold), (250_000, "Supernova", .platinum)] {
            out.append(milestone("lifecal-\(Int(t))", title, "Burn \(n(t)) active calories in total.", "flame.circle.fill",
                                 .lifetime, tier, value: totalCal, target: t, date: crossing(cals, t),
                                 label: "\(n(totalCal)) / \(n(t)) cal"))
        }
        let totalActive = active.map(\.value).reduce(0, +)
        for (h, title, tier) in [(10.0, "10 Active Hours", Award.Tier.bronze), (50, "50 Active Hours", .silver),
                                 (100, "100 Active Hours", .gold), (500, "500 Active Hours", .platinum)] {
            out.append(milestone("lifeactive-\(Int(h))", title, "Log \(Int(h)) hours of exercise minutes in total.", "hourglass",
                                 .lifetime, tier, value: totalActive / 60, target: h, date: crossing(active, h * 60),
                                 label: String(format: "%.1f / %.0f hours", totalActive / 60, h)))
        }

        // MARK: Journeys (lifetime walking + running distance)
        let totalM = dist.map(\.value).reduce(0, +)
        let journeys: [(String, String, Double, String, Award.Tier)] = [
            ("shorepath", "Shore Path Explorer", 21 * mile, "the Geneva Lake Shore Path (21 mi)", .bronze),
            ("lg-madison", "Lake Geneva → Madison", 70 * mile, "Lake Geneva to Madison (70 mi)", .silver),
            ("lg-chicago", "Lake Geneva → Chicago", 80 * mile, "Lake Geneva to Chicago (80 mi)", .silver),
            ("across-wi", "Across Wisconsin", 300 * mile, "across Wisconsin (300 mi)", .gold),
            ("route66", "Route 66", 2448 * mile, "the length of Route 66 (2,448 mi)", .platinum),
            ("coast", "Coast to Coast", 2800 * mile, "across the USA (2,800 mi)", .platinum),
        ]
        for (id, title, meters, what, tier) in journeys {
            out.append(milestone("journey-\(id)", title, "Walk and run the distance of \(what).", "map.fill", .journeys, tier,
                                 value: totalM, target: meters, date: crossing(dist, meters),
                                 label: "\(miles(totalM)) / \(miles(meters))"))
        }

        // MARK: Walking
        let walks = workouts.filter { $0.kind == .walking }
        let longestWalk = walks.map(\.distance).max() ?? 0
        for (m, title, tier) in [(1 * mile, "Mile Walker", Award.Tier.bronze), (3 * mile, "Long Walk", .silver),
                                 (5 * mile, "Trekker", .gold), (10 * mile, "Epic Trek", .platinum)] {
            out.append(Award(id: "walk-\(Int(m))", title: title, detail: "Walk \(miles(m)) in one go.", icon: "figure.walk",
                             category: .walking, tier: tier, earned: walks.first { $0.distance >= m }?.start,
                             progress: min(longestWalk / m, 1), progressText: "Longest: \(miles(longestWalk)) / \(miles(m))"))
        }
        for (t, title, tier) in [(10, "10 Walks", Award.Tier.bronze), (50, "50 Walks", .silver),
                                 (100, "100 Walks", .gold), (250, "250 Walks", .platinum)] {
            out.append(Award(id: "walks-\(t)", title: title, detail: "Record \(t) walks.", icon: "figure.walk.circle.fill",
                             category: .walking, tier: tier, earned: walks.count >= t ? walks[t - 1].start : nil,
                             progress: min(Double(walks.count) / Double(t), 1), progressText: "\(walks.count) / \(t) walks"))
        }
        let morning = walks.filter { cal.component(.hour, from: $0.start) < 9 }
        out.append(Award(id: "morning-routine", title: "Morning Routine", detail: "Take 10 walks before 9 AM.", icon: "sunrise.fill",
                         category: .walking, tier: .silver, earned: morning.count >= 10 ? morning[9].start : nil,
                         progress: min(Double(morning.count) / 10, 1), progressText: "\(morning.count) / 10 morning walks"))
        let auto = walks.filter(\.autoDetected) + workouts.filter { $0.kind == .running && $0.autoDetected }
        let autoSorted = auto.sorted { $0.start < $1.start }
        out.append(Award(id: "autopilot", title: "Autopilot", detail: "Have 10 walks or runs recorded automatically.", icon: "sparkles",
                         category: .walking, tier: .special, earned: autoSorted.count >= 10 ? autoSorted[9].start : nil,
                         progress: min(Double(autoSorted.count) / 10, 1), progressText: "\(autoSorted.count) / 10 auto-recorded"))

        // MARK: More running
        let runs = workouts.filter { $0.kind == .running }
        let runTotal = runs.map(\.distance).reduce(0, +)
        out.append(Award(id: "run-42195", title: "Marathoner", detail: "Run a full marathon (42.2 km / 26.2 mi) in one go.",
                         icon: "medal.fill", category: .running, tier: .platinum,
                         earned: runs.first { $0.distance >= 42_195 }?.start,
                         progress: min((runs.map(\.distance).max() ?? 0) / 42_195, 1),
                         progressText: "Longest: \(miles(runs.map(\.distance).max() ?? 0)) / 26.2 mi"))
        for (t, title, tier) in [(10, "10 Runs", Award.Tier.bronze), (25, "25 Runs", .silver), (100, "100 Runs", .gold)] {
            out.append(Award(id: "runs-\(t)", title: title, detail: "Complete \(t) runs.", icon: "figure.run.circle.fill",
                             category: .running, tier: tier, earned: runs.count >= t ? runs[t - 1].start : nil,
                             progress: min(Double(runs.count) / Double(t), 1), progressText: "\(runs.count) / \(t) runs"))
        }
        for (mi, title, tier) in [(50.0, "50 Running Miles", Award.Tier.silver), (100, "100 Running Miles", .gold),
                                  (500, "500 Running Miles", .platinum)] {
            var acc = 0.0, when: Date?
            for r in runs { acc += r.distance; if acc >= mi * mile, when == nil { when = r.start } }
            out.append(milestone("runmiles-\(Int(mi))", title, "Run \(miles(mi * mile)) in total.", "figure.run", .running, tier,
                                 value: runTotal, target: mi * mile, date: when, label: "\(miles(runTotal)) / \(miles(mi * mile))"))
        }
        let fast = runs.first { $0.distance >= mile && $0.duration / ($0.distance / mile) < 9 * 60 }
        out.append(Award(id: "speedster", title: "Speedster", detail: "Run a mile or more at faster than 9:00 per mile (5:35/km).",
                         icon: "hare.fill", category: .running, tier: .gold, earned: fast?.start,
                         progress: fast == nil ? 0 : 1, progressText: fast == nil ? "Not yet" : "Done"))
        var runWeek: Date?
        let runWeeks = Dictionary(grouping: runs) { cal.dateInterval(of: .weekOfYear, for: $0.start)?.start ?? $0.start }
        for (_, list) in runWeeks.sorted(by: { $0.key < $1.key }) where list.count >= 3 {
            runWeek = list.sorted { $0.start < $1.start }[2].start; break
        }
        out.append(Award(id: "run-week-3", title: "Three-Run Week", detail: "Run 3 times in one week.", icon: "calendar",
                         category: .running, tier: .silver, earned: runWeek,
                         progress: runWeek == nil ? 0 : 1, progressText: runWeek == nil ? "Not yet" : "Done"))

        // MARK: Workout variety, time and frequency
        let totalWorkoutHours = workouts.map(\.duration).reduce(0, +) / 3600
        for (h, title, tier) in [(10.0, "Time Well Spent", Award.Tier.bronze), (50, "Dedicated", .silver),
                                 (100, "Iron Will", .gold), (250, "Lifer", .platinum)] {
            var acc = 0.0, when: Date?
            for w in workouts { acc += w.duration / 3600; if acc >= h, when == nil { when = w.start } }
            out.append(milestone("workhours-\(Int(h))", title, "Spend \(Int(h)) hours working out.", "clock.fill", .workouts, tier,
                                 value: totalWorkoutHours, target: h, date: when,
                                 label: String(format: "%.1f / %.0f hours", totalWorkoutHours, h)))
        }
        for (t, title, tier) in [(250, "Quarter Thousand", Award.Tier.platinum), (500, "Five Hundred", .platinum)] {
            out.append(Award(id: "workouts-\(t)", title: title, detail: "Complete \(t) workouts.", icon: "trophy.fill",
                             category: .workouts, tier: tier, earned: workouts.count >= t ? workouts[t - 1].start : nil,
                             progress: min(Double(workouts.count) / Double(t), 1), progressText: "\(workouts.count) / \(t) workouts"))
        }
        let longestWorkout = workouts.map(\.duration).max() ?? 0
        for (min, title, tier) in [(60.0, "Hour of Power", Award.Tier.silver), (120, "Endurance", .gold)] {
            out.append(Award(id: "long-\(Int(min))", title: title, detail: "Do a single workout of \(Int(min)) minutes or more.",
                             icon: "stopwatch.fill", category: .workouts, tier: tier,
                             earned: workouts.first { $0.duration >= min * 60 }?.start,
                             progress: Swift.min(longestWorkout / (min * 60), 1),
                             progressText: "Longest: \(Fmt.clock(longestWorkout)) / \(Int(min)) min"))
        }
        var seenKinds: [WorkoutKind] = []
        var variety3: Date?, variety5: Date?
        for w in workouts where !seenKinds.contains(w.kind) {
            seenKinds.append(w.kind)
            if seenKinds.count == 3 { variety3 = w.start }
            if seenKinds.count == 5 { variety5 = w.start }
        }
        out.append(Award(id: "variety-3", title: "Variety Pack", detail: "Try 3 different kinds of workout.", icon: "square.grid.3x3.fill",
                         category: .workouts, tier: .silver, earned: variety3,
                         progress: min(Double(seenKinds.count) / 3, 1), progressText: "\(seenKinds.count) / 3 kinds"))
        out.append(Award(id: "variety-5", title: "All-Rounder", detail: "Try 5 different kinds of workout.", icon: "circle.hexagongrid.fill",
                         category: .workouts, tier: .gold, earned: variety5,
                         progress: min(Double(seenKinds.count) / 5, 1), progressText: "\(seenKinds.count) / 5 kinds"))
        var fiveWeek: Date?
        let byWeek = Dictionary(grouping: workouts) { cal.dateInterval(of: .weekOfYear, for: $0.start)?.start ?? $0.start }
        for (_, list) in byWeek.sorted(by: { $0.key < $1.key }) where list.count >= 5 {
            fiveWeek = list.sorted { $0.start < $1.start }[4].start; break
        }
        let thisWeekCount = byWeek[cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now]?.count ?? 0
        out.append(Award(id: "five-a-week", title: "Five-a-Week", detail: "Do 5 workouts in one week.", icon: "5.circle.fill",
                         category: .workouts, tier: .gold, earned: fiveWeek,
                         progress: fiveWeek == nil ? min(Double(thisWeekCount) / 5, 1) : 1,
                         progressText: "This week: \(thisWeekCount) / 5"))
        // Gym & circuits
        let gym = workouts.filter { $0.workout.metadata?["SkiStepsGymLog"] != nil || $0.type == .traditionalStrengthTraining }
        for (t, title, tier) in [(25, "Gym Rat", Award.Tier.gold), (50, "Iron Legend", .platinum)] {
            out.append(Award(id: "gym-\(t)", title: title, detail: "Log \(t) gym workouts.", icon: "dumbbell.fill",
                             category: .workouts, tier: tier, earned: gym.count >= t ? gym[t - 1].start : nil,
                             progress: min(Double(gym.count) / Double(t), 1), progressText: "\(gym.count) / \(t) gym workouts"))
        }
        let circuits = workouts.filter { [.highIntensityIntervalTraining, .functionalStrengthTraining, .coreTraining].contains($0.type) }
        out.append(Award(id: "circuit-10", title: "Circuit Master", detail: "Finish 10 circuits or HIIT workouts.", icon: "bolt.heart.fill",
                         category: .workouts, tier: .silver, earned: circuits.count >= 10 ? circuits[9].start : nil,
                         progress: min(Double(circuits.count) / 10, 1), progressText: "\(circuits.count) / 10 circuits"))
        // Cycling & swimming
        let rides = workouts.filter { $0.kind == .cycling }
        out.append(Award(id: "ride-1", title: "First Ride", detail: "Record your first bike ride.", icon: "bicycle",
                         category: .workouts, tier: .bronze, earned: rides.first?.start,
                         progress: rides.isEmpty ? 0 : 1, progressText: "\(rides.count) rides"))
        out.append(Award(id: "ride-25mi", title: "Quarter Century Ride", detail: "Ride 25 miles (40 km) in one go.", icon: "bicycle",
                         category: .workouts, tier: .gold, earned: rides.first { $0.distance >= 25 * mile }?.start,
                         progress: min((rides.map(\.distance).max() ?? 0) / (25 * mile), 1),
                         progressText: "Longest: \(miles(rides.map(\.distance).max() ?? 0)) / 25 mi"))
        let swims = workouts.filter { $0.kind == .swimming }
        let swimTotal = swims.map(\.distance).reduce(0, +)
        for (m, title, tier) in [(1_000.0, "1K Swimmer", Award.Tier.silver), (10_000, "10K Swimmer", .gold)] {
            var acc = 0.0, when: Date?
            for s in swims { acc += s.distance; if acc >= m, when == nil { when = s.start } }
            out.append(milestone("swimtotal-\(Int(m))", title, "Swim \(n(m)) m in total.", "figure.pool.swim", .workouts, tier,
                                 value: swimTotal, target: m, date: when, label: "\(n(swimTotal)) / \(n(m)) m"))
        }

        // MARK: Effort days
        let bestCal = cals.map(\.value).max() ?? 0
        out.append(Award(id: "cal-1500", title: "Blaze", detail: "Burn 1,500 active calories in one day.", icon: "flame.circle.fill",
                         category: .special, tier: .platinum, earned: cals.first { $0.value >= 1500 }?.date,
                         progress: min(bestCal / 1500, 1), progressText: "Best day: \(n(bestCal)) / 1,500 cal"))
        let bestActive = active.map(\.value).max() ?? 0
        for (t, title, tier) in [(90.0, "Ninety Minute Mover", Award.Tier.gold), (120, "Two-Hour Hustle", .platinum)] {
            out.append(Award(id: "active-\(Int(t))", title: title, detail: "Get \(Int(t)) active minutes in one day.", icon: "timer",
                             category: .special, tier: tier, earned: active.first { $0.value >= t }?.date,
                             progress: min(bestActive / t, 1), progressText: "Best day: \(Int(bestActive)) / \(Int(t)) min"))
        }
        var heartWeek: Date?
        let activeWeeks = Dictionary(grouping: active) { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        for (_, days) in activeWeeks.sorted(by: { $0.key < $1.key }) where days.map(\.value).reduce(0, +) >= 150 {
            var acc = 0.0
            for d in days.sorted(by: { $0.date < $1.date }) { acc += d.value; if acc >= 150 { heartWeek = d.date; break } }
            break
        }
        let weekActive = active.filter { cal.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }.map(\.value).reduce(0, +)
        out.append(Award(id: "heart-week", title: "Heart Healthy Week", detail: "Get 150 active minutes in one week — the weekly amount health guidelines recommend.",
                         icon: "heart.circle.fill", category: .special, tier: .gold, earned: heartWeek,
                         progress: heartWeek == nil ? min(weekActive / 150, 1) : 1,
                         progressText: "This week: \(Int(weekActive)) / 150 min"))

        // MARK: Holidays
        func holiday(_ id: String, _ title: String, _ detail: String, _ icon: String, match: (Date) -> Bool) {
            let w = workouts.first { match($0.start) }
            let s = steps.first { match($0.date) && $0.value >= Metric.steps.goal() }
            let when = [w?.start, s?.date].compactMap { $0 }.min()
            out.append(Award(id: id, title: title, detail: detail, icon: icon, category: .special, tier: .special,
                             earned: when, progress: when == nil ? 0 : 1, progressText: when == nil ? "Not yet" : "Done"))
        }
        holiday("new-year", "Fresh Start", "Work out or hit your step goal on New Year's Day.", "party.popper.fill") {
            cal.component(.month, from: $0) == 1 && cal.component(.day, from: $0) == 1
        }
        holiday("turkey-trot", "Turkey Trot", "Work out or hit your step goal on Thanksgiving.", "leaf.fill") { d in
            let c = cal.dateComponents([.month, .day, .weekday], from: d)
            return c.month == 11 && c.weekday == 5 && (22...28).contains(c.day ?? 0)
        }
        holiday("independence", "Independence Day", "Work out or hit your step goal on the 4th of July.", "star.fill") {
            cal.component(.month, from: $0) == 7 && cal.component(.day, from: $0) == 4
        }
        holiday("holiday-cheer", "Holiday Cheer", "Work out or hit your step goal on Christmas Day.", "gift.fill") {
            cal.component(.month, from: $0) == 12 && cal.component(.day, from: $0) == 25
        }

        // MARK: Sleep extras
        let nights = health.nights
        let savedSleepGoal = UserDefaults.standard.double(forKey: "sleepGoal")
        let sleepGoalHours: Double = savedSleepGoal > 0 ? savedSleepGoal : 8
        out.append(Award(id: "sleep-tracked-30", title: "Sleep Tracker", detail: "Track 30 nights of sleep.", icon: "moon.fill",
                         category: .sleep, tier: .silver, earned: nights.count >= 30 ? nights[29].day : nil,
                         progress: min(Double(nights.count) / 30, 1), progressText: "\(nights.count) / 30 nights"))
        let long = nights.first { $0.asleep >= 9 * 3600 }
        out.append(Award(id: "sleep-9", title: "Hibernator", detail: "Sleep 9 hours in one night.", icon: "powersleep",
                         category: .sleep, tier: .gold, earned: long?.day,
                         progress: min((nights.map(\.asleep).max() ?? 0) / (9 * 3600), 1),
                         progressText: "Best night: \(SleepFmt.hours(nights.map(\.asleep).max() ?? 0)) / 9h"))
        let earlyBed = nights.filter { $0.bedtimeMinutes <= 4 * 60 }   // asleep by 10 PM
        out.append(Award(id: "early-to-bed", title: "Early to Bed", detail: "Fall asleep by 10 PM on 5 nights.", icon: "bed.double.circle.fill",
                         category: .sleep, tier: .silver, earned: earlyBed.count >= 5 ? earlyBed[4].day : nil,
                         progress: min(Double(earlyBed.count) / 5, 1), progressText: "\(earlyBed.count) / 5 nights"))
        let great = nights.first { $0.score(goalHours: sleepGoalHours, usualBedtime: nights.usualBedtime(before: $0)) >= 90 }
        let bestScore = nights.map { $0.score(goalHours: sleepGoalHours, usualBedtime: nights.usualBedtime(before: $0)) }.max() ?? 0
        out.append(Award(id: "sleep-score-90", title: "Perfect Night", detail: "Get a sleep score of 90 or more.", icon: "star.circle.fill",
                         category: .sleep, tier: .gold, earned: great?.day,
                         progress: min(Double(bestScore) / 90, 1), progressText: "Best score: \(bestScore) / 90"))
        var steady: Date?
        if nights.count >= 7 {
            for i in 6..<nights.count {
                let w = nights[(i - 6)...i].map(\.bedtimeMinutes)
                let mean = w.reduce(0, +) / 7
                let sd = sqrt(w.map { pow($0 - mean, 2) }.reduce(0, +) / 7)
                if sd <= 30 { steady = nights[i].day; break }
            }
        }
        out.append(Award(id: "sleep-steady", title: "Clockwork", detail: "Keep your bedtime within about 30 minutes for 7 nights straight.",
                         icon: "clock.badge.checkmark.fill", category: .sleep, tier: .gold, earned: steady,
                         progress: steady == nil ? 0 : 1, progressText: steady == nil ? "Not yet" : "Done"))

        // MARK: Past monthly challenges (last 12 months you completed)
        let stepGoal = Metric.steps.goal()
        for back in 1...12 {
            guard let monthDate = cal.date(byAdding: .month, value: -back, to: .now),
                  let interval = cal.dateInterval(of: .month, for: monthDate) else { continue }
            let days = steps.filter { interval.contains($0.date) }
            guard days.count >= 20 else { continue }   // need history for that month
            let monthDays = cal.range(of: .day, in: .month, for: monthDate)?.count ?? 30
            let target = (stepGoal * Double(monthDays) * 0.8 / 10_000).rounded() * 10_000
            if let done = crossing(days, target) {
                let name = monthDate.formatted(.dateTime.month(.wide).year())
                out.append(Award(id: "month-\(monthDate.formatted(.dateTime.year().month(.twoDigits)))",
                                 title: "\(name) Challenge", detail: "Walked \(n(target)) steps in \(name).",
                                 icon: "calendar", category: .monthly, tier: .special, earned: done,
                                 progress: 1, progressText: "Completed"))
            }
        }
        return out
    }
}

// MARK: - Levels

extension Award.Tier {
    var points: Int {
        switch self {
        case .bronze: 10
        case .silver: 25
        case .gold: 50
        case .platinum: 100
        case .special: 30
        }
    }
}

enum AwardLevel {
    /// Level from points; each level needs a bit more than the last.
    static func info(points: Int) -> (level: Int, into: Int, needed: Int) {
        var level = 1, need = 100, remaining = points
        while remaining >= need {
            remaining -= need
            level += 1
            need = 100 + (level - 1) * 25
        }
        return (level, remaining, need)
    }

    static func title(_ level: Int) -> String {
        switch level {
        case ..<3: "Rookie"
        case 3..<6: "Mover"
        case 6..<10: "Pacer"
        case 10..<15: "Trailblazer"
        case 15..<20: "Champion"
        case 20..<30: "Legend"
        default: "Mythic"
        }
    }
}
