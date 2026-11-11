import SwiftUI
import HealthKit

struct GymMachine: Identifiable, Hashable {
    enum Kind { case strength, cardio }

    let id: String
    let name: String
    let icon: String
    let kind: Kind
    let area: BodyArea
    let muscles: String
    let setup: [String]
    let tip: String
    /// Effort level used to estimate calories (MET).
    let met: Double
    /// Cardio machines: what to save to Health.
    var activity: HKWorkoutActivityType = .traditionalStrengthTraining
    var distanceType: HKQuantityTypeIdentifier? = nil

    static func == (a: GymMachine, b: GymMachine) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum GymLibrary {
    static let strength: [GymMachine] = [
        GymMachine(id: "chestpress", name: "Chest Press", icon: "figure.strengthtraining.traditional", kind: .strength, area: .upper,
                   muscles: "Chest, shoulders, triceps",
                   setup: ["Set the seat so the handles line up with the middle of your chest.",
                           "Press the handles forward until your arms are almost straight.",
                           "Return slowly until you feel a light stretch in your chest."],
                   tip: "Keep your shoulder blades pinned to the pad.", met: 5),
        GymMachine(id: "pecdeck", name: "Pec Deck / Chest Fly", icon: "figure.strengthtraining.functional", kind: .strength, area: .upper,
                   muscles: "Chest, front shoulders",
                   setup: ["Sit with your back flat and handles at chest height.",
                           "With a slight bend in your elbows, bring the handles together in front of you.",
                           "Open back up slowly."],
                   tip: "Think about hugging a big tree.", met: 4.5),
        GymMachine(id: "shoulderpress", name: "Shoulder Press", icon: "figure.strengthtraining.traditional", kind: .strength, area: .upper,
                   muscles: "Shoulders, triceps",
                   setup: ["Set the seat so the handles start at shoulder height.",
                           "Press straight up until your arms are nearly locked.",
                           "Lower with control."],
                   tip: "Don't arch your lower back off the pad.", met: 5),
        GymMachine(id: "latpulldown", name: "Lat Pulldown", icon: "figure.strengthtraining.functional", kind: .strength, area: .upper,
                   muscles: "Lats, upper back, biceps",
                   setup: ["Lock your thighs under the pads and grab the bar wide.",
                           "Pull the bar to your upper chest, driving your elbows down.",
                           "Let it rise slowly until your arms are straight."],
                   tip: "Lean back slightly and lead with your elbows, not your hands.", met: 5),
        GymMachine(id: "seatedrow", name: "Seated Row", icon: "figure.rower", kind: .strength, area: .upper,
                   muscles: "Mid back, lats, biceps",
                   setup: ["Sit tall with your chest against the pad (or feet on the platform).",
                           "Pull the handles to your stomach, squeezing your shoulder blades.",
                           "Extend your arms slowly."],
                   tip: "Keep your torso still — no rocking.", met: 5),
        GymMachine(id: "assistedpullup", name: "Assisted Pull-Up", icon: "figure.play", kind: .strength, area: .upper,
                   muscles: "Lats, biceps, core",
                   setup: ["Kneel or stand on the platform and grip the handles.",
                           "Pull up until your chin clears the handles.",
                           "Lower all the way down."],
                   tip: "More weight means MORE help — lower it as you get stronger.", met: 6),
        GymMachine(id: "bicepcurl", name: "Bicep Curl Machine", icon: "dumbbell.fill", kind: .strength, area: .upper,
                   muscles: "Biceps",
                   setup: ["Rest the backs of your arms on the pad.",
                           "Curl the handles up toward your shoulders.",
                           "Lower slowly to almost straight."],
                   tip: "Pause and squeeze at the top.", met: 4),
        GymMachine(id: "tricepext", name: "Tricep Extension Machine", icon: "dumbbell.fill", kind: .strength, area: .upper,
                   muscles: "Triceps",
                   setup: ["Rest your arms on the pad, elbows lined up with the pivot.",
                           "Push the handles down until your arms are straight.",
                           "Return slowly."],
                   tip: "Keep your elbows from flaring out.", met: 4),
        GymMachine(id: "cable", name: "Cable Crossover", icon: "figure.strengthtraining.functional", kind: .strength, area: .upper,
                   muscles: "Chest, shoulders",
                   setup: ["Set both pulleys high and grab a handle in each hand.",
                           "Step forward and bring your hands together in front of your hips.",
                           "Return slowly with control."],
                   tip: "Use a split stance for balance.", met: 4.5),
        GymMachine(id: "legpress", name: "Leg Press", icon: "figure.strengthtraining.traditional", kind: .strength, area: .lower,
                   muscles: "Quads, glutes, hamstrings",
                   setup: ["Feet shoulder-width on the platform, back flat on the seat.",
                           "Release the safety and lower until your knees are about 90°.",
                           "Press back up without locking your knees."],
                   tip: "Higher feet = more glutes; lower feet = more quads.", met: 5.5),
        GymMachine(id: "legext", name: "Leg Extension", icon: "figure.strengthtraining.functional", kind: .strength, area: .lower,
                   muscles: "Quads",
                   setup: ["Line your knees up with the machine's pivot, pad on your lower shins.",
                           "Straighten your legs.",
                           "Lower slowly."],
                   tip: "Hold the top for a second for extra burn.", met: 4),
        GymMachine(id: "legcurl", name: "Leg Curl", icon: "figure.strengthtraining.functional", kind: .strength, area: .lower,
                   muscles: "Hamstrings",
                   setup: ["Set the pad just above your heels.",
                           "Curl your heels toward your glutes.",
                           "Return slowly."],
                   tip: "Keep your hips pressed into the seat or bench.", met: 4),
        GymMachine(id: "calfraise", name: "Calf Raise", icon: "figure.step.training", kind: .strength, area: .lower,
                   muscles: "Calves",
                   setup: ["Balls of your feet on the edge of the platform.",
                           "Rise up onto your toes as high as you can.",
                           "Lower your heels below the platform for a stretch."],
                   tip: "Go slow — calves respond to control, not bouncing.", met: 4),
        GymMachine(id: "abductor", name: "Hip Abductor", icon: "figure.flexibility", kind: .strength, area: .lower,
                   muscles: "Outer hips, glutes",
                   setup: ["Sit with the pads on the outside of your knees.",
                           "Push your knees apart.",
                           "Return slowly."],
                   tip: "Lean slightly forward to hit more glute.", met: 4),
        GymMachine(id: "adductor", name: "Hip Adductor", icon: "figure.flexibility", kind: .strength, area: .lower,
                   muscles: "Inner thighs",
                   setup: ["Sit with the pads on the inside of your knees.",
                           "Squeeze your knees together.",
                           "Open back up with control."],
                   tip: "Start with a range of motion that feels comfortable.", met: 4),
        GymMachine(id: "smithsquat", name: "Smith Machine Squat", icon: "figure.strengthtraining.traditional", kind: .strength, area: .lower,
                   muscles: "Quads, glutes",
                   setup: ["Set the bar at shoulder height and step under it.",
                           "Unhook and squat until your thighs are parallel.",
                           "Drive up through your heels."],
                   tip: "Feet slightly in front of the bar.", met: 6),
        GymMachine(id: "abcrunch", name: "Ab Crunch Machine", icon: "figure.core.training", kind: .strength, area: .core,
                   muscles: "Abs",
                   setup: ["Sit and hold the handles, feet under the rollers.",
                           "Crunch forward, bringing your chest toward your knees.",
                           "Return slowly."],
                   tip: "Exhale as you crunch.", met: 4),
        GymMachine(id: "backext", name: "Back Extension", icon: "figure.cooldown", kind: .strength, area: .core,
                   muscles: "Lower back, glutes, hamstrings",
                   setup: ["Hips on the pad, ankles locked in.",
                           "Lower your torso forward with a flat back.",
                           "Lift until your body is in a straight line."],
                   tip: "Don't hyperextend at the top.", met: 4),
    ]

    static let cardio: [GymMachine] = [
        GymMachine(id: "treadmillrun", name: "Treadmill Run", icon: "figure.run", kind: .cardio, area: .cardio,
                   muscles: "Legs, heart", setup: ["Start slow to warm up, then build to your running pace."],
                   tip: "Set a 1% incline to feel more like running outside.", met: 9,
                   activity: .running, distanceType: .distanceWalkingRunning),
        GymMachine(id: "treadmillwalk", name: "Treadmill Walk", icon: "figure.walk", kind: .cardio, area: .cardio,
                   muscles: "Legs, heart", setup: ["Walk at a brisk pace. Add incline to make it harder."],
                   tip: "Don't hold the rails — swing your arms.", met: 4.5,
                   activity: .walking, distanceType: .distanceWalkingRunning),
        GymMachine(id: "elliptical", name: "Elliptical", icon: "figure.elliptical", kind: .cardio, area: .cardio,
                   muscles: "Full body", setup: ["Push and pull the handles while you stride."],
                   tip: "Stand tall and keep your heels down.", met: 5),
        GymMachine(id: "bike", name: "Stationary Bike", icon: "figure.indoor.cycle", kind: .cardio, area: .cardio,
                   muscles: "Legs, heart", setup: ["Set the seat so your knee is slightly bent at the bottom."],
                   tip: "Mix in 30-second hard efforts.", met: 7,
                   activity: .cycling, distanceType: .distanceCycling),
        GymMachine(id: "rower", name: "Rowing Machine", icon: "figure.rower", kind: .cardio, area: .cardio,
                   muscles: "Full body", setup: ["Legs, then lean back, then arms. Reverse on the way in."],
                   tip: "Most of the power comes from your legs.", met: 7,
                   activity: .rowing),
        GymMachine(id: "stair", name: "Stair Climber", icon: "figure.stair.stepper", kind: .cardio, area: .cardio,
                   muscles: "Glutes, legs, heart", setup: ["Climb at a steady pace, standing tall."],
                   tip: "Lightly touch the rails for balance only.", met: 9,
                   activity: .stairClimbing),
    ]

    static let byID: [String: GymMachine] =
        Dictionary(uniqueKeysWithValues: (strength + cardio).map { ($0.id, $0) })
}

// MARK: - Logged sets

struct LoggedSet: Identifiable, Codable, Hashable {
    var id = UUID()
    var weightKg: Double
    var reps: Int
    var done = false
}

/// Remembers your last sets on each machine so the next workout starts there.
enum GymMemory {
    private static let key = "gymLastSets.v1"

    static func lastSets(_ machineID: String) -> [LoggedSet] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([String: [LoggedSet]].self, from: data) else { return [] }
        return (all[machineID] ?? []).map { LoggedSet(weightKg: $0.weightKg, reps: $0.reps) }
    }

    static func save(_ sets: [LoggedSet], for machineID: String) {
        var all: [String: [LoggedSet]] = [:]
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: [LoggedSet]].self, from: data) { all = saved }
        all[machineID] = sets
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }

    static var useKg: Bool { UserDefaults.standard.bool(forKey: "useMetric") }
    static var unit: String { useKg ? "kg" : "lb" }
    static func display(_ kg: Double) -> Double { useKg ? kg : kg / 0.45359237 }
    static func toKg(_ value: Double) -> Double { useKg ? value : value * 0.45359237 }

    static func summary(_ sets: [LoggedSet]) -> String {
        guard !sets.isEmpty else { return "" }
        let weights = Set(sets.map { Int(display($0.weightKg).rounded()) })
        let reps = Set(sets.map(\.reps))
        if weights.count == 1, reps.count == 1 {
            return "\(sets.count)×\(sets[0].reps) @ \(weights.first!) \(unit)"
        }
        return sets.map { "\(Int(display($0.weightKg).rounded()))×\($0.reps)" }.joined(separator: ", ") + " \(unit)"
    }
}
