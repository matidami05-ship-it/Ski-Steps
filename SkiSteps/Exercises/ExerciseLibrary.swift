import SwiftUI

enum BodyArea: String, CaseIterable, Identifiable, Codable {
    case upper, core, lower, cardio
    var id: Self { self }

    var title: String {
        switch self {
        case .upper: "Upper Body"
        case .core: "Core"
        case .lower: "Lower Body"
        case .cardio: "Cardio"
        }
    }

    var color: Color {
        switch self {
        case .upper: Theme.accent2
        case .core: Theme.gold
        case .lower: Theme.accent
        case .cardio: Theme.calorie
        }
    }
}

struct Exercise: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let area: BodyArea
    let muscles: String
    let steps: [String]
    let tip: String
    /// Effort level used to estimate calories (MET).
    let met: Double
    /// One side at a time — the player tells you to switch halfway.
    var sided: Bool = false
}

enum ExerciseLibrary {
    static let all: [Exercise] = [
        Exercise(id: "pushups", name: "Push Ups", icon: "figure.strengthtraining.functional", area: .upper,
                 muscles: "Chest, shoulders, triceps, core",
                 steps: ["Start in a high plank, hands just wider than your shoulders.",
                         "Lower your chest toward the floor, elbows at about 45°.",
                         "Push back up until your arms are straight."],
                 tip: "Too hard? Drop to your knees and keep a straight line from knees to head.", met: 8),
        Exercise(id: "punchpushups", name: "Punch Push Ups", icon: "figure.boxing", area: .upper,
                 muscles: "Chest, shoulders, core",
                 steps: ["Do one push up.",
                         "At the top, shift your weight and punch one arm straight forward.",
                         "Plant it, do another push up, then punch with the other arm."],
                 tip: "Widen your feet for balance during the punch.", met: 8),
        Exercise(id: "rotationpushups", name: "Rotation Push Ups", icon: "figure.cross.training", area: .upper,
                 muscles: "Chest, shoulders, obliques",
                 steps: ["Do one push up.",
                         "At the top, rotate into a side plank and reach one arm to the ceiling.",
                         "Return to plank and repeat, rotating to the other side."],
                 tip: "Move slowly through the rotation and keep your hips lifted.", met: 8),
        Exercise(id: "crunches", name: "Crunches", icon: "figure.core.training", area: .core,
                 muscles: "Abs",
                 steps: ["Lie on your back, knees bent, feet flat.",
                         "Hands lightly behind your head, lift your shoulders off the floor.",
                         "Lower slowly and repeat."],
                 tip: "Don't pull on your neck — lead with your chest.", met: 4),
        Exercise(id: "lunges", name: "Lunges", icon: "figure.step.training", area: .lower,
                 muscles: "Quads, glutes, hamstrings",
                 steps: ["Stand tall and step forward with one leg.",
                         "Lower until both knees are bent about 90°.",
                         "Push back to standing and switch legs."],
                 tip: "Keep your front knee over your ankle, not past your toes.", met: 5),
        Exercise(id: "sidelunges", name: "Side Lunges", icon: "figure.flexibility", area: .lower,
                 muscles: "Inner thighs, glutes, quads",
                 steps: ["Stand with feet together.",
                         "Take a big step to the side and sit your hips back, bending that knee.",
                         "Push back to center and switch sides."],
                 tip: "Keep the straight leg's foot flat on the floor.", met: 5),
        Exercise(id: "squats", name: "Squats", icon: "figure.cross.training", area: .lower,
                 muscles: "Quads, glutes, hamstrings",
                 steps: ["Stand with feet shoulder-width apart.",
                         "Sit your hips back and down until thighs are about parallel.",
                         "Drive through your heels to stand."],
                 tip: "Chest up, knees tracking over your toes.", met: 5.5),
        Exercise(id: "hiphinges", name: "Hip Hinges", icon: "figure.cooldown", area: .lower,
                 muscles: "Hamstrings, glutes, lower back",
                 steps: ["Stand tall, hands on hips, slight bend in the knees.",
                         "Push your hips back and tip your chest forward with a flat back.",
                         "Squeeze your glutes to return to standing."],
                 tip: "The movement comes from the hips, not the lower back.", met: 3.5),
        Exercise(id: "kneeraises", name: "Knee Raises", icon: "figure.highintensity.intervaltraining", area: .cardio,
                 muscles: "Hip flexors, core, legs",
                 steps: ["Stand tall.",
                         "Drive one knee up to hip height, then the other.",
                         "Keep a quick, steady rhythm."],
                 tip: "Pump your arms to go faster.", met: 7),
        Exercise(id: "mountainclimbers", name: "Mountain Climbers", icon: "figure.mixed.cardio", area: .cardio,
                 muscles: "Core, shoulders, hip flexors",
                 steps: ["Start in a high plank.",
                         "Drive one knee toward your chest, then switch quickly.",
                         "Keep your hips level as you alternate."],
                 tip: "Shoulders stay stacked over your wrists.", met: 8),
        Exercise(id: "birddogs", name: "Bird Dogs", icon: "figure.yoga", area: .core,
                 muscles: "Core, lower back, glutes",
                 steps: ["Start on hands and knees.",
                         "Extend one arm forward and the opposite leg back.",
                         "Hold for a breath, return, and switch sides."],
                 tip: "Keep your back flat like a table.", met: 3),
        Exercise(id: "donkeykicks", name: "Donkey Kicks", icon: "figure.barre", area: .lower,
                 muscles: "Glutes",
                 steps: ["Start on hands and knees.",
                         "Keeping the knee bent, lift one foot toward the ceiling.",
                         "Lower with control and repeat."],
                 tip: "Squeeze your glute at the top; don't arch your back.", met: 4, sided: true),
        Exercise(id: "supermen", name: "Supermen", icon: "figure.pilates", area: .core,
                 muscles: "Lower back, glutes, shoulders",
                 steps: ["Lie face down, arms stretched forward.",
                         "Lift your arms, chest and legs off the floor.",
                         "Hold briefly, then lower."],
                 tip: "Look at the floor to keep your neck neutral.", met: 3.5),
        Exercise(id: "leglifts", name: "Leg Lifts", icon: "figure.core.training", area: .core,
                 muscles: "Lower abs, hip flexors",
                 steps: ["Lie on your back, legs straight, hands under your hips.",
                         "Raise your legs to vertical.",
                         "Lower slowly without touching the floor."],
                 tip: "Press your lower back into the floor the whole time.", met: 4),
        Exercise(id: "kneepullins", name: "Knee Pull-Ins", icon: "figure.mind.and.body", area: .core,
                 muscles: "Abs, hip flexors",
                 steps: ["Sit and lean back on your hands, legs extended.",
                         "Pull your knees toward your chest.",
                         "Extend your legs back out without touching the floor."],
                 tip: "Lean back further to make it harder.", met: 4),
        Exercise(id: "kicks", name: "Kicks", icon: "figure.kickboxing", area: .cardio,
                 muscles: "Legs, glutes, core",
                 steps: ["Stand in a fighting stance, hands up.",
                         "Lift your knee and snap a front kick forward.",
                         "Recover and alternate legs."],
                 tip: "Control the kick — don't lock your knee.", met: 7),
        Exercise(id: "glutebridges", name: "Glute Bridges", icon: "figure.pilates", area: .lower,
                 muscles: "Glutes, hamstrings",
                 steps: ["Lie on your back, knees bent, feet flat.",
                         "Press through your heels and lift your hips.",
                         "Squeeze at the top, then lower."],
                 tip: "Keep your ribs down so the work stays in your glutes.", met: 3.5),
        Exercise(id: "jumpingjacks", name: "Jumping Jacks", icon: "figure.arms.open", area: .cardio,
                 muscles: "Full body",
                 steps: ["Stand with feet together, arms at your sides.",
                         "Jump your feet out while raising your arms overhead.",
                         "Jump back to start and repeat."],
                 tip: "Land softly on the balls of your feet.", met: 8),
        Exercise(id: "lowstancejacks", name: "Low Stance Jacks", icon: "figure.dance", area: .cardio,
                 muscles: "Legs, glutes",
                 steps: ["Sink into a half squat.",
                         "Stay low and jump your feet in and out.",
                         "Keep your chest up the whole time."],
                 tip: "The lower you stay, the harder it is.", met: 8),
        Exercise(id: "bicyclecrunches", name: "Bicycle Crunches", icon: "figure.core.training", area: .core,
                 muscles: "Abs, obliques",
                 steps: ["Lie on your back, hands behind your head, legs lifted.",
                         "Bring one knee in while twisting the opposite elbow toward it.",
                         "Switch sides in a pedaling motion."],
                 tip: "Slow and controlled beats fast and sloppy.", met: 5),
        Exercise(id: "sidehipraises", name: "Side Lying Hip Raises", icon: "figure.flexibility", area: .core,
                 muscles: "Obliques, hips",
                 steps: ["Lie on your side, propped on your forearm.",
                         "Lift your hips until your body forms a straight line.",
                         "Lower and repeat."],
                 tip: "Elbow directly under your shoulder.", met: 3.5, sided: true),
        Exercise(id: "jackknife", name: "Jack Knife Crunches", icon: "figure.gymnastics", area: .core,
                 muscles: "Abs",
                 steps: ["Lie flat, arms overhead, legs straight.",
                         "Lift arms and legs at the same time to meet over your hips.",
                         "Lower slowly to the start."],
                 tip: "Bend your knees a little if it's too hard.", met: 5),
        Exercise(id: "tricepdips", name: "Tricep Dips", icon: "figure.strengthtraining.traditional", area: .upper,
                 muscles: "Triceps, shoulders",
                 steps: ["Sit on the edge of a sturdy chair, hands beside your hips.",
                         "Slide forward and lower by bending your elbows.",
                         "Press back up to straight arms."],
                 tip: "Keep your back close to the chair.", met: 5),
        Exercise(id: "squatjumps", name: "Squat Jumps", icon: "figure.jumprope", area: .cardio,
                 muscles: "Legs, glutes",
                 steps: ["Lower into a squat.",
                         "Explode up into a jump.",
                         "Land softly and go straight into the next squat."],
                 tip: "Land with bent knees to protect your joints.", met: 9),
        Exercise(id: "burpees", name: "Burpees", icon: "figure.highintensity.intervaltraining", area: .cardio,
                 muscles: "Full body",
                 steps: ["Squat and place your hands on the floor.",
                         "Jump your feet back to a plank (add a push up if you like).",
                         "Jump your feet in and leap up."],
                 tip: "Step back instead of jumping for a lower-impact version.", met: 10),
        Exercise(id: "wallsit", name: "Wall Sit", icon: "figure.stand", area: .lower,
                 muscles: "Quads, glutes",
                 steps: ["Lean your back against a wall.",
                         "Slide down until your knees are bent 90°.",
                         "Hold the position."],
                 tip: "Keep your weight in your heels.", met: 4),
        Exercise(id: "plank", name: "Plank", icon: "figure.core.training", area: .core,
                 muscles: "Core, shoulders",
                 steps: ["Rest on your forearms and toes.",
                         "Make a straight line from head to heels.",
                         "Hold, breathing steadily."],
                 tip: "Squeeze your glutes so your hips don't sag.", met: 4),
        Exercise(id: "sideplank", name: "Side Plank", icon: "figure.taichi", area: .core,
                 muscles: "Obliques, shoulders",
                 steps: ["Lie on your side, forearm under your shoulder.",
                         "Lift your hips into a straight line.",
                         "Hold, then switch sides halfway."],
                 tip: "Drop the bottom knee to make it easier.", met: 4, sided: true),
        Exercise(id: "reverseplank", name: "Reverse Plank", icon: "figure.yoga", area: .upper,
                 muscles: "Glutes, hamstrings, shoulders",
                 steps: ["Sit with legs straight, hands behind your hips, fingers forward.",
                         "Lift your hips into a straight line, chest open.",
                         "Hold."],
                 tip: "Let your head follow your spine — don't drop it back.", met: 4),
        Exercise(id: "extendedplank", name: "Extended Plank", icon: "figure.pilates", area: .core,
                 muscles: "Core, shoulders",
                 steps: ["Start in a forearm plank.",
                         "Walk your hands or elbows a few inches forward.",
                         "Hold the longer lever without letting your hips sag."],
                 tip: "The further forward, the harder it gets.", met: 4.5),
    ]

    static let byID: [String: Exercise] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func exercise(_ id: String) -> Exercise? { byID[id] }
}

/// A circuit of exercises: work/rest intervals repeated for some rounds.
struct Routine: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var exerciseIDs: [String]
    var work: Int = 30
    var rest: Int = 10
    var rounds: Int = 1
    var builtIn = false

    var exercises: [Exercise] { exerciseIDs.compactMap(ExerciseLibrary.exercise) }

    /// Total length in seconds, including the 10 s get-ready.
    var duration: Int {
        let n = exercises.count * rounds
        guard n > 0 else { return 0 }
        return 10 + n * work + (n - 1) * rest
    }

    var mainArea: BodyArea {
        let counts = Dictionary(grouping: exercises, by: \.area).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? .cardio
    }

    static let builtIns: [Routine] = [
        Routine(name: "7-Minute Full Body",
                exerciseIDs: ["jumpingjacks", "wallsit", "pushups", "crunches", "squats", "tricepdips",
                              "plank", "kneeraises", "lunges", "rotationpushups", "sideplank"],
                work: 30, rest: 10, rounds: 1, builtIn: true),
        Routine(name: "Core Crusher",
                exerciseIDs: ["crunches", "bicyclecrunches", "leglifts", "plank", "jackknife",
                              "kneepullins", "sideplank", "supermen"],
                work: 40, rest: 15, rounds: 2, builtIn: true),
        Routine(name: "Lower Body Burn",
                exerciseIDs: ["squats", "lunges", "glutebridges", "sidelunges", "donkeykicks",
                              "squatjumps", "wallsit", "hiphinges"],
                work: 40, rest: 15, rounds: 2, builtIn: true),
        Routine(name: "Cardio Blast",
                exerciseIDs: ["jumpingjacks", "mountainclimbers", "burpees", "lowstancejacks",
                              "kicks", "squatjumps", "kneeraises"],
                work: 30, rest: 10, rounds: 3, builtIn: true),
        Routine(name: "Upper Body & Arms",
                exerciseIDs: ["pushups", "tricepdips", "punchpushups", "rotationpushups",
                              "reverseplank", "extendedplank", "birddogs"],
                work: 30, rest: 15, rounds: 2, builtIn: true),
    ]
}

/// Keeps your custom circuits and your edits to the built-in ones.
@MainActor
final class RoutineStore: ObservableObject {
    @Published private(set) var routines: [Routine] = []
    private let key = "routines.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Routine].self, from: data), !saved.isEmpty {
            // Keep built-ins up to date with new ones added in later versions.
            let savedIDs = Set(saved.filter(\.builtIn).map(\.name))
            routines = saved + Routine.builtIns.filter { !savedIDs.contains($0.name) }
        } else {
            routines = Routine.builtIns
        }
    }

    func save(_ routine: Routine) {
        if let i = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[i] = routine
        } else {
            routines.insert(routine, at: 0)
        }
        persist()
    }

    func delete(_ routine: Routine) {
        routines.removeAll { $0.id == routine.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension Fmt {
    /// 425 → "7 min", 90 → "1.5 min", 45 → "45 sec"
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        let m = Double(seconds) / 60
        return m < 10 && m.rounded() != m ? String(format: "%.1f min", m) : "\(Int(m.rounded())) min"
    }
}
