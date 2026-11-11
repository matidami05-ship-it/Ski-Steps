import SwiftUI

/// Colors and helpers shared by the app and the widget.
enum Theme {
    static let accent = Color(red: 0.24, green: 0.95, blue: 0.62)
    static let accent2 = Color(red: 0.10, green: 0.74, blue: 0.98)
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.30)
    static let bgTop = Color(red: 0.035, green: 0.055, blue: 0.10)
    static let bgBottom = Color(red: 0.02, green: 0.10, blue: 0.12)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.08)

    static var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// Today's numbers, saved by the app for the widget to read.
struct StepSnapshot: Codable {
    var day: Date
    var steps: Double
    var distanceMeters: Double
    var goal: Double
    var useMetric: Bool

    static let groupID = "group.com.ski.steps"
    private static let key = "todaySnapshot"

    static func load() -> StepSnapshot? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StepSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: StepSnapshot.groupID)?.set(data, forKey: StepSnapshot.key)
    }

    /// The snapshot only counts if it's from today; otherwise it's a fresh day at 0.
    var isToday: Bool { Calendar.current.isDateInToday(day) }
    var todaySteps: Double { isToday ? steps : 0 }
    var todayDistance: Double { isToday ? distanceMeters : 0 }
    var progress: Double { goal > 0 ? todaySteps / goal : 0 }
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
        let value = metric ? meters / 1000 : meters / 1609.344
        return String(format: value < 10 ? "%.2f" : "%.1f", value)
    }

    static func distanceUnit(_ metric: Bool) -> String { metric ? "km" : "mi" }
}

/// A circular progress ring that goes past 100% with a second, brighter lap.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 22

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
                    AngularGradient(
                        colors: [Theme.accent2, Theme.accent],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(first, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if second > 0 {
                Circle()
                    .trim(from: 0, to: second)
                    .stroke(
                        AngularGradient(
                            colors: [Theme.accent, Theme.gold],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * max(second, 0.01))
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.5), radius: lineWidth / 4)
            }
        }
        .padding(lineWidth / 2)
    }
}
