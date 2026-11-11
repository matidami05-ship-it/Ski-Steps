import SwiftUI

/// Colors and helpers shared by the app and the widget.
enum Theme {
    static let accent = Color(red: 0.24, green: 0.95, blue: 0.62)
    static let accent2 = Color(red: 0.10, green: 0.74, blue: 0.98)
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.30)
    static let calorie = Color(red: 1.0, green: 0.36, blue: 0.50)
    static let active = Color(red: 1.0, green: 0.62, blue: 0.20)
    static let run = Color(red: 0.62, green: 0.48, blue: 1.0)
    static let bgTop = Color(red: 0.035, green: 0.055, blue: 0.10)
    static let bgBottom = Color(red: 0.02, green: 0.10, blue: 0.12)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.08)

    static var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// The four things you can set a daily goal for.
enum Metric: String, CaseIterable, Identifiable, Codable {
    case steps, distance, calories, active

    var id: Self { self }

    var title: String {
        switch self {
        case .steps: "Steps"
        case .distance: "Distance"
        case .calories: "Calories"
        case .active: "Active time"
        }
    }

    var icon: String {
        switch self {
        case .steps: "figure.walk"
        case .distance: "location.fill"
        case .calories: "flame.fill"
        case .active: "timer"
        }
    }

    var color: Color {
        switch self {
        case .steps: Theme.accent
        case .distance: Theme.accent2
        case .calories: Theme.calorie
        case .active: Theme.active
        }
    }

    /// UserDefaults key for the goal. Steps keeps its original key.
    var goalKey: String {
        switch self {
        case .steps: "dailyGoal"
        case .distance: "distanceGoal"   // meters
        case .calories: "calorieGoal"    // kcal
        case .active: "activeGoal"       // minutes
        }
    }

    /// Raw units: steps, meters, kcal, minutes.
    var defaultGoal: Double {
        switch self {
        case .steps: 10_000
        case .distance: 5 * 1609.344
        case .calories: 500
        case .active: 30
        }
    }

    /// Raw goal from the app's settings.
    func goal(_ defaults: UserDefaults = .standard) -> Double {
        let g = defaults.double(forKey: goalKey)
        return g > 0 ? g : defaultGoal
    }

    /// Converts a raw value (meters for distance) to what's shown on screen.
    func display(_ raw: Double, useMetric: Bool) -> Double {
        guard self == .distance else { return raw }
        return useMetric ? raw / 1000 : raw / 1609.344
    }

    /// Text for a value that's already in display units.
    func text(_ value: Double) -> String {
        switch self {
        case .distance:
            return String(format: value < 10 ? "%.2f" : "%.1f", value)
        case .active:
            return Fmt.minutes(value)
        default:
            return Fmt.steps(value)
        }
    }

    func unit(useMetric: Bool) -> String {
        switch self {
        case .steps: "steps"
        case .distance: useMetric ? "km" : "mi"
        case .calories: "cal"
        case .active: "min"
        }
    }

    func short(_ value: Double) -> String {
        self == .distance ? text(value) : Fmt.compact(value)
    }
}

/// Today's numbers, saved by the app for the widget to read.
struct StepSnapshot: Codable {
    var day: Date
    var steps: Double
    var distanceMeters: Double
    var energy: Double
    var activeMinutes: Double
    var goals: [String: Double]
    var useMetric: Bool

    static let groupID = "group.com.skistudio.steps"
    private static let key = "todaySnapshot.v2"

    static func load() -> StepSnapshot? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StepSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: StepSnapshot.groupID)?.set(data, forKey: StepSnapshot.key)
    }

    func value(_ m: Metric) -> Double {
        switch m {
        case .steps: steps
        case .distance: distanceMeters
        case .calories: energy
        case .active: activeMinutes
        }
    }

    func goal(_ m: Metric) -> Double { goals[m.rawValue] ?? m.defaultGoal }

    static let empty = StepSnapshot(day: .now, steps: 0, distanceMeters: 0, energy: 0, activeMinutes: 0,
                                    goals: [:], useMetric: false)
}

enum Fmt {
    static func steps(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.grouping(.automatic))
    }

    static func compact(_ value: Double) -> String {
        if value >= 1000 {
            let k = value / 1000
            return (k >= 10 ? String(format: "%.0fk", k) : String(format: "%.1fk", k))
        }
        return steps(value)
    }

    static func distance(_ meters: Double, metric: Bool) -> String {
        Metric.distance.text(Metric.distance.display(meters, useMetric: metric))
    }

    static func distanceUnit(_ metric: Bool) -> String { metric ? "km" : "mi" }

    /// 75 → "1h 15m", 42 → "42"
    static func minutes(_ value: Double) -> String {
        let m = Int(value.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)"
    }

    /// Seconds → "1:02:03" or "32:10"
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// Pace as "m:ss" per mile or km, from seconds and meters.
    static func pace(seconds: TimeInterval, meters: Double, metric: Bool) -> String {
        let unit = metric ? 1000.0 : 1609.344
        guard meters > 10, seconds > 0 else { return "--:--" }
        let perUnit = seconds / (meters / unit)
        guard perUnit.isFinite, perUnit < 60 * 60 else { return "--:--" }
        return clock(perUnit)
    }
}

/// A circular progress ring that goes past 100% with a second, brighter lap.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 22
    var colors: [Color] = [Theme.accent2, Theme.accent]

    var body: some View {
        let p = max(progress, 0)
        let first = min(p, 1)
        let second = min(max(p - 1, 0), 1)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: first)
                .stroke(
                    AngularGradient(colors: colors, center: .center, startAngle: .degrees(0),
                                    endAngle: .degrees(360 * max(first, 0.01))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if second > 0 {
                Circle()
                    .trim(from: 0, to: second)
                    .stroke(
                        AngularGradient(colors: [colors.last ?? Theme.accent, Theme.gold], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(second, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.5), radius: lineWidth / 4)
            }
        }
        .padding(lineWidth / 2)
    }
}

/// A thin horizontal progress bar.
struct GoalBar: View {
    var progress: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.7), progress >= 1 ? Theme.gold : color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: height)
    }
}
