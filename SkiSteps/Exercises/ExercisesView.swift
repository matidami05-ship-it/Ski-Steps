import SwiftUI

struct ExercisesView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case bodyweight = "Bodyweight", gym = "Gym Machines"
        var id: Self { self }
    }

    @StateObject private var store = RoutineStore()
    @AppStorage("exerciseMode") private var mode: Mode = .bodyweight
    @State private var area: BodyArea?
    @State private var shownExercise: Exercise?
    @State private var shownRoutine: Routine?
    @State private var editing: Routine?
    @State private var playing: Routine?
    @State private var shownMachine: GymMachine?
    @State private var cardioMachine: GymMachine?
    @State private var gymStart: [GymMachine]?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Type", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .bodyweight { bodyweight } else { gym }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if mode == .bodyweight {
                        editing = Routine(name: "", exerciseIDs: [])
                    } else {
                        gymStart = []
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                }
                .accessibilityLabel(mode == .bodyweight ? "New circuit" : "Start gym workout")
            }
        }
        .sheet(item: $shownExercise) { ex in
            ExerciseDetailView(exercise: ex) { routine in
                shownExercise = nil
                after { playing = routine }
            }
            .presentationDetents([.large])
        }
        .sheet(item: $shownRoutine) { r in
            RoutineDetailView(routine: r, store: store,
                              onStart: { r in shownRoutine = nil; after { playing = r } },
                              onEdit: { r in shownRoutine = nil; after { editing = r } })
                .presentationDetents([.large])
        }
        .sheet(item: $editing) { r in
            RoutineBuilderView(routine: r, store: store)
        }
        .sheet(item: $shownMachine) { m in
            MachineDetailView(machine: m) {
                shownMachine = nil
                after { if m.kind == .cardio { cardioMachine = m } else { gymStart = [m] } }
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $playing) { r in
            CircuitPlayerView(routine: r)
        }
        .fullScreenCover(item: $cardioMachine) { m in
            CardioMachineView(machine: m)
        }
        .fullScreenCover(isPresented: Binding(get: { gymStart != nil }, set: { if !$0 { gymStart = nil } })) {
            GymSessionView(startWith: gymStart ?? [])
        }
    }

    /// Opens the next screen once the closing sheet has finished animating away.
    private func after(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action)
    }

    // MARK: Bodyweight

    private var bodyweight: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Guided circuits").font(.title3.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.routines) { r in
                        Button { shownRoutine = r } label: { routineCard(r) }
                            .buttonStyle(.plain)
                    }
                    Button {
                        editing = Routine(name: "", exerciseIDs: [])
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                            Text("Build your own").font(.subheadline.weight(.semibold))
                        }
                        .frame(width: 150, height: 150)
                        .card()
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("All exercises").font(.title3.weight(.bold))
                Spacer()
                Text("\(filtered.count)").font(.subheadline).foregroundStyle(.secondary)
            }
            areaChips
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filtered) { ex in
                    Button { shownExercise = ex } label: {
                        ExerciseTile(name: ex.name, icon: ex.icon, color: ex.area.color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var filtered: [Exercise] {
        guard let area else { return ExerciseLibrary.all }
        return ExerciseLibrary.all.filter { $0.area == area }
    }

    private var areaChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: area == nil, color: .white) { area = nil }
                ForEach(BodyArea.allCases) { a in
                    chip(a.title, selected: area == a, color: a.color) { area = a }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? .black : .primary)
                .background(selected ? color : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func routineCard(_ r: Routine) -> some View {
        let c = r.mainArea.color
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: -8) {
                ForEach(Array(r.exercises.prefix(3).enumerated()), id: \.offset) { _, e in
                    Image(systemName: e.icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(c, in: Circle())
                        .overlay(Circle().stroke(Theme.bgTop, lineWidth: 2))
                }
            }
            Spacer(minLength: 0)
            Text(r.name).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
            Text("\(Fmt.duration(r.duration)) · \(r.exercises.count) exercises")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 170, height: 150, alignment: .leading)
        .background(
            LinearGradient(colors: [c.opacity(0.35), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke))
    }

    // MARK: Gym

    private var gym: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                gymStart = []
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 28, weight: .bold))
                        .frame(width: 60, height: 60)
                        .background(.white.opacity(0.2), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start Gym Workout").font(.title3.weight(.bold))
                        Text("Log sets, reps & weight with a rest timer").font(.subheadline).opacity(0.85)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.headline)
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(LinearGradient(colors: [Theme.accent2, Theme.accent.opacity(0.8)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("Cardio machines").font(.title3.weight(.bold))
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(GymLibrary.cardio) { m in
                    Button { cardioMachine = m } label: {
                        ExerciseTile(name: m.name, icon: m.icon, color: Theme.calorie, trailing: "play.fill")
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach([BodyArea.upper, .lower, .core]) { a in
                let items = GymLibrary.strength.filter { $0.area == a }
                Text("\(a.title) machines").font(.title3.weight(.bold))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { m in
                        Button { shownMachine = m } label: {
                            ExerciseTile(name: m.name, icon: m.icon, color: a.color,
                                         caption: GymMemory.summary(GymMemory.lastSets(m.id)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Tile

struct ExerciseTile: View {
    var name: String
    var icon: String
    var color: Color
    var caption: String = ""
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 52, height: 52)
                .background(color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                if !caption.isEmpty {
                    Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let trailing {
                Image(systemName: trailing).font(.caption).foregroundStyle(color)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .card()
    }
}

// MARK: - Exercise detail

struct ExerciseDetailView: View {
    let exercise: Exercise
    let onStart: (Routine) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var seconds = 45

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()
                        Image(systemName: exercise.icon)
                            .font(.system(size: 72, weight: .semibold))
                            .foregroundStyle(exercise.area.color)
                            .frame(width: 150, height: 150)
                            .background(exercise.area.color.opacity(0.15), in: Circle())
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.area.title.uppercased())
                            .font(.caption.weight(.bold)).foregroundStyle(exercise.area.color)
                        Text(exercise.name).font(.largeTitle.weight(.bold))
                        Text(exercise.muscles).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to do it").font(.headline)
                        ForEach(Array(exercise.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 26, height: 26)
                                    .background(exercise.area.color, in: Circle())
                                Text(step).font(.body)
                            }
                        }
                        if exercise.sided {
                            Label("Works one side at a time — you'll be told when to switch.", systemImage: "arrow.left.arrow.right")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    Label(exercise.tip, systemImage: "lightbulb.fill")
                        .font(.subheadline)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Stepper(value: $seconds, in: 15...300, step: 15) {
                        Text("Timer: \(Fmt.duration(seconds))").font(.headline)
                    }
                    .padding(16)
                    .card()
                    Button {
                        onStart(Routine(name: exercise.name, exerciseIDs: [exercise.id], work: seconds, rest: 0, rounds: 1))
                    } label: {
                        Label("Start \(exercise.name)", systemImage: "play.fill")
                            .font(.headline).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(exercise.area.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Machine detail

struct MachineDetailView: View {
    let machine: GymMachine
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: machine.icon)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(machine.area.color)
                            .frame(width: 72, height: 72)
                            .background(machine.area.color.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(machine.name).font(.title2.weight(.bold))
                            Text(machine.muscles).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    let last = GymMemory.lastSets(machine.id)
                    if !last.isEmpty {
                        Label("Last time: \(GymMemory.summary(last))", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(machine.setup.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1).").font(.subheadline.weight(.bold)).foregroundStyle(machine.area.color)
                                Text(step).font(.subheadline)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    Label(machine.tip, systemImage: "lightbulb.fill")
                        .font(.subheadline)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button(action: onStart) {
                        Label(machine.kind == .cardio ? "Start \(machine.name)" : "Start workout with \(machine.name)",
                              systemImage: "play.fill")
                            .font(.headline).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(machine.area.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Routine detail

struct RoutineDetailView: View {
    let routine: Routine
    @ObservedObject var store: RoutineStore
    let onStart: (Routine) -> Void
    let onEdit: (Routine) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var work: Int
    @State private var rest: Int
    @State private var rounds: Int

    init(routine: Routine, store: RoutineStore, onStart: @escaping (Routine) -> Void, onEdit: @escaping (Routine) -> Void) {
        self.routine = routine
        self.store = store
        self.onStart = onStart
        self.onEdit = onEdit
        _work = State(initialValue: routine.work)
        _rest = State(initialValue: routine.rest)
        _rounds = State(initialValue: routine.rounds)
    }

    private var current: Routine {
        var r = routine
        r.work = work; r.rest = rest; r.rounds = rounds
        return r
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(routine.name).font(.title2.weight(.bold))
                        Text("\(Fmt.duration(current.duration)) · \(routine.exercises.count) exercises × \(rounds) round\(rounds == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Timing") {
                    Stepper("Work: \(work) sec", value: $work, in: 10...180, step: 5)
                    Stepper("Rest: \(rest) sec", value: $rest, in: 0...120, step: 5)
                    Stepper("Rounds: \(rounds)", value: $rounds, in: 1...10)
                }
                Section("Exercises") {
                    ForEach(Array(routine.exercises.enumerated()), id: \.offset) { i, e in
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 18)
                            Image(systemName: e.icon).foregroundStyle(e.area.color).frame(width: 28)
                            Text(e.name)
                            Spacer()
                            Text(e.area.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !routine.builtIn {
                    Section {
                        Button("Edit Circuit") { onEdit(current) }
                        Button("Delete Circuit", role: .destructive) {
                            store.delete(routine)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    if current != routine { store.save(current) }
                    onStart(current)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.headline).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(routine.mainArea.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Builder

struct RoutineBuilderView: View {
    @State var routine: Routine
    @ObservedObject var store: RoutineStore
    @Environment(\.dismiss) private var dismiss
    @State private var area: BodyArea?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Circuit name", text: $routine.name)
                        .font(.headline)
                    Stepper("Work: \(routine.work) sec", value: $routine.work, in: 10...180, step: 5)
                    Stepper("Rest: \(routine.rest) sec", value: $routine.rest, in: 0...120, step: 5)
                    Stepper("Rounds: \(routine.rounds)", value: $routine.rounds, in: 1...10)
                } footer: {
                    Text(routine.exercises.isEmpty ? "Pick exercises below." : "Total \(Fmt.duration(routine.duration))")
                }

                if !routine.exerciseIDs.isEmpty {
                    Section("Your circuit — hold to reorder, swipe to remove") {
                        ForEach(routine.exerciseIDs, id: \.self) { id in
                            if let e = ExerciseLibrary.exercise(id) {
                                Label(e.name, systemImage: e.icon)
                            }
                        }
                        .onMove { routine.exerciseIDs.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { routine.exerciseIDs.remove(atOffsets: $0) }
                    }
                }

                Section("Add exercises") {
                    ForEach(ExerciseLibrary.all) { e in
                        let picked = routine.exerciseIDs.contains(e.id)
                        Button {
                            if picked {
                                routine.exerciseIDs.removeAll { $0 == e.id }
                            } else {
                                routine.exerciseIDs.append(e.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: e.icon).foregroundStyle(e.area.color).frame(width: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.name).foregroundStyle(.primary)
                                    Text(e.area.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(picked ? Theme.accent : .secondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(routine.name.isEmpty ? "New Circuit" : routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var r = routine
                        if r.name.trimmingCharacters(in: .whitespaces).isEmpty { r.name = "My Circuit" }
                        r.builtIn = false
                        store.save(r)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(routine.exerciseIDs.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
