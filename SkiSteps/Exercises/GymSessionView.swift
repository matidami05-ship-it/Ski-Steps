import SwiftUI
import HealthKit
import AVFoundation
import AudioToolbox

// MARK: - Strength (sets × reps × weight)

struct MachineEntry: Identifiable {
    var id = UUID()
    var machine: GymMachine
    var sets: [LoggedSet]
}

struct GymSessionView: View {
    @EnvironmentObject private var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [MachineEntry]
    @State private var start = Date()
    @State private var showPicker = false
    @State private var restEnd: Date?
    @State private var restLength: Double = 90
    @State private var confirmEnd = false
    @State private var saving = false
    @State private var saved = false
    @State private var errorText: String?
    @State private var bodyKg: Double = 75
    @FocusState private var focused: UUID?

    init(startWith machines: [GymMachine] = []) {
        _entries = State(initialValue: machines.map(GymSessionView.entry(for:)))
    }

    static func entry(for m: GymMachine) -> MachineEntry {
        let last = GymMemory.lastSets(m.id)
        let sets = last.isEmpty
            ? Array(repeating: LoggedSet(weightKg: GymMemory.toKg(GymMemory.useKg ? 20 : 50), reps: 10), count: 3)
                .map { LoggedSet(weightKg: $0.weightKg, reps: $0.reps) }
            : last
        return MachineEntry(machine: m, sets: sets)
    }

    private var doneSets: Int { entries.flatMap(\.sets).filter(\.done).count }
    private var volumeKg: Double {
        entries.flatMap(\.sets).filter(\.done).reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.background.ignoresSafeArea()
                if saved {
                    savedView
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            header
                            ForEach($entries) { $entry in
                                machineCard($entry)
                            }
                            Button {
                                showPicker = true
                            } label: {
                                Label("Add Machine", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                        .foregroundStyle(Theme.accent.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                            if let errorText {
                                Text(errorText).font(.footnote).foregroundStyle(.yellow)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, restEnd == nil ? 30 : 110)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    if restEnd != nil { restBanner }
                }
            }
            .navigationTitle("Gym Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !saved {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if doneSets == 0 { dismiss() } else { confirmEnd = true }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Finish") { finish() }
                            .fontWeight(.bold)
                            .disabled(doneSets == 0 || saving)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focused = nil }
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                MachinePicker(kind: .strength) { m in
                    entries.append(GymSessionView.entry(for: m))
                    showPicker = false
                }
                .presentationDetents([.large])
            }
            .confirmationDialog("Discard this workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Going", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .task {
            bodyKg = await health.bodyMassKg()
            UIApplication.shared.isIdleTimerDisabled = true
            if entries.isEmpty { showPicker = true }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Header

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 0) {
                headerStat(Fmt.clock(ctx.date.timeIntervalSince(start)), "time", Theme.active)
                headerStat("\(doneSets)", "sets", Theme.accent)
                headerStat("\(Fmt.steps(GymMemory.display(volumeKg)))", "\(GymMemory.unit) lifted", Theme.accent2)
            }
            .padding(.vertical, 14)
            .card()
        }
    }

    private func headerStat(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(c)
            Text(l).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Machine card

    private func machineCard(_ entry: Binding<MachineEntry>) -> some View {
        let m = entry.wrappedValue.machine
        let last = GymMemory.lastSets(m.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: m.icon)
                    .font(.title3)
                    .foregroundStyle(m.area.color)
                    .frame(width: 40, height: 40)
                    .background(m.area.color.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(.headline)
                    Text(last.isEmpty ? m.muscles : "Last time: \(GymMemory.summary(last))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        entries.removeAll { $0.id == entry.wrappedValue.id }
                    } label: { Label("Remove", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("SET").frame(width: 34, alignment: .leading)
                Text(GymMemory.unit.uppercased()).frame(maxWidth: .infinity)
                Text("REPS").frame(maxWidth: .infinity)
                Text("").frame(width: 44)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)

            ForEach(Array(entry.wrappedValue.sets.enumerated()), id: \.element.id) { i, s in
                setRow(entry, number: i + 1, id: s.id)
            }

            HStack {
                Button {
                    let lastSet = entry.wrappedValue.sets.last ?? LoggedSet(weightKg: GymMemory.toKg(50), reps: 10)
                    entry.wrappedValue.sets.append(LoggedSet(weightKg: lastSet.weightKg, reps: lastSet.reps))
                } label: {
                    Label("Add Set", systemImage: "plus").font(.subheadline.weight(.semibold))
                }
                Spacer()
                if entry.wrappedValue.sets.count > 1 {
                    Button {
                        entry.wrappedValue.sets.removeLast()
                    } label: {
                        Label("Remove Set", systemImage: "minus").font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .card()
    }

    private func setRow(_ entry: Binding<MachineEntry>, number: Int, id: UUID) -> some View {
        // Look the set up by id each time so removing a set can't index out of range.
        let set = Binding<LoggedSet>(
            get: { entry.wrappedValue.sets.first { $0.id == id } ?? LoggedSet(weightKg: 0, reps: 0) },
            set: { new in
                if let i = entry.wrappedValue.sets.firstIndex(where: { $0.id == id }) {
                    entry.wrappedValue.sets[i] = new
                }
            }
        )
        let done = set.wrappedValue.done
        let weightBinding = Binding<Double>(
            get: { (GymMemory.display(set.wrappedValue.weightKg) * 2).rounded() / 2 },
            set: { set.wrappedValue.weightKg = GymMemory.toKg($0) }
        )
        return HStack {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .frame(width: 34, alignment: .leading)
                .foregroundStyle(done ? Theme.accent : .primary)
            TextField("0", value: weightBinding, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .focused($focused, equals: set.wrappedValue.id)
                .multilineTextAlignment(.center)
                .font(.headline.monospacedDigit())
                .padding(.vertical, 8)
                .background(Color.white.opacity(done ? 0.04 : 0.08), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity)
            TextField("0", value: set.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.headline.monospacedDigit())
                .padding(.vertical, 8)
                .background(Color.white.opacity(done ? 0.04 : 0.08), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity)
            Button {
                focused = nil
                set.wrappedValue.done.toggle()
                if set.wrappedValue.done { startRest() }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Theme.accent : .secondary)
                    .frame(width: 44)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: done)
        }
    }

    // MARK: Rest timer

    private func startRest() {
        restEnd = Date().addingTimeInterval(restLength)
    }

    private var restBanner: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let left = max((restEnd ?? ctx.date).timeIntervalSince(ctx.date), 0)
            HStack(spacing: 14) {
                ZStack {
                    ProgressRing(progress: 1 - left / max(restLength, 1), lineWidth: 5)
                    Image(systemName: "timer").font(.caption.weight(.bold))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(left > 0 ? "Rest" : "Rest over — next set!")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(left > 0 ? .secondary : Theme.accent)
                    Text(Fmt.clock(left))
                        .font(.title2.weight(.bold).monospacedDigit())
                }
                Spacer()
                Button("−15") { adjustRest(-15) }.buttonStyle(.bordered)
                Button("+15") { adjustRest(15) }.buttonStyle(.bordered)
                Button {
                    restEnd = nil
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.bordered)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .onChange(of: left <= 0) { _, over in
                if over {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    AudioServicesPlaySystemSound(1057)
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func adjustRest(_ delta: Double) {
        restLength = max(15, restLength + delta)
        if let end = restEnd { restEnd = end.addingTimeInterval(delta) }
    }

    // MARK: Finish

    private func finish() {
        saving = true
        let end = Date()
        let minutes = end.timeIntervalSince(start) / 60
        let used = entries.filter { $0.sets.contains(where: \.done) }
        // Weighted average effort of the machines used.
        let met = used.isEmpty ? 5 : used.map(\.machine.met).reduce(0, +) / Double(used.count)
        let kcal = met * bodyKg * minutes / 60
        let log = used.map { "\($0.machine.name): \(GymMemory.summary($0.sets.filter(\.done)))" }
            .joined(separator: "\n")
        let title = used.count == 1 ? "Gym · \(used[0].machine.name)" : "Gym Workout"
        Task {
            do {
                try await health.saveWorkout(.traditionalStrengthTraining, start: start, end: end,
                                             kcal: kcal, indoor: true,
                                             metadata: ["SkiStepsRoutine": title, "SkiStepsGymLog": log])
                for e in used { GymMemory.save(e.sets.filter(\.done), for: e.machine.id) }
                withAnimation(.spring) { saved = true }
                restEnd = nil
            } catch {
                errorText = "Couldn't save: \(error.localizedDescription)"
            }
            saving = false
        }
    }

    private var savedView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(Theme.accent)
            Text("Saved to Apple Health").font(.title2.weight(.bold))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entries.filter { $0.sets.contains(where: \.done) }) { e in
                    HStack {
                        Text(e.machine.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(GymMemory.summary(e.sets.filter(\.done)))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .card()
            .padding(.horizontal, 20)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done").font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Machine picker

struct MachinePicker: View {
    let kind: GymMachine.Kind
    let onPick: (GymMachine) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var machines: [GymMachine] {
        let list = kind == .strength ? GymLibrary.strength : GymLibrary.cardio
        guard !search.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.muscles.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(BodyArea.allCases) { area in
                    let items = machines.filter { $0.area == area }
                    if !items.isEmpty {
                        Section(area.title) {
                            ForEach(items) { m in
                                Button {
                                    onPick(m)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: m.icon)
                                            .foregroundStyle(m.area.color)
                                            .frame(width: 34, height: 34)
                                            .background(m.area.color.opacity(0.15), in: Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.name).font(.body.weight(.semibold))
                                            let last = GymMemory.lastSets(m.id)
                                            Text(last.isEmpty ? m.muscles : "Last: \(GymMemory.summary(last))")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search machines or muscles")
            .navigationTitle("Add Machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Cardio machines (timed)

struct CardioMachineView: View {
    let machine: GymMachine
    @EnvironmentObject private var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetric") private var metric = false
    @State private var start = Date()
    @State private var pauseStart: Date?
    @State private var pauses: [DateInterval] = []
    @State private var ended: Date?
    @State private var bodyKg: Double = 75
    @State private var distanceText = ""
    @State private var caloriesText = ""
    @State private var saving = false
    @State private var saved = false
    @State private var errorText: String?
    @State private var confirmDiscard = false

    private func active(at date: Date) -> TimeInterval {
        let end = ended ?? date
        let paused = pauses.reduce(0) { $0 + $1.duration } + (pauseStart.map { end.timeIntervalSince($0) } ?? 0)
        return max(end.timeIntervalSince(start) - paused, 0)
    }

    private func estimatedKcal(at date: Date) -> Double { machine.met * bodyKg * active(at: date) / 3600 }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.calorie.opacity(0.3), Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if ended == nil {
                running
            } else {
                finishForm
            }
        }
        .preferredColorScheme(.dark)
        .task {
            bodyKg = await health.bodyMassKg()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var running: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Text(machine.name).font(.headline)
                Spacer()
            }
            .padding(.top, 16)
            Spacer()
            Image(systemName: machine.icon)
                .font(.system(size: 80, weight: .semibold))
                .foregroundStyle(Theme.calorie)
                .symbolEffect(.pulse, isActive: pauseStart == nil)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(spacing: 8) {
                    Text(Fmt.clock(active(at: ctx.date)))
                        .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(pauseStart == nil ? .white : Theme.gold)
                    Text("≈ \(Fmt.steps(estimatedKcal(at: ctx.date))) cal")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.calorie)
                }
            }
            Text(machine.tip).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            HStack(spacing: 36) {
                circle(pauseStart == nil ? "pause.fill" : "play.fill", Theme.gold, 84) {
                    if let p = pauseStart {
                        pauses.append(DateInterval(start: p, end: Date()))
                        pauseStart = nil
                    } else {
                        pauseStart = Date()
                    }
                }
                circle("stop.fill", Theme.calorie, 70) {
                    if let p = pauseStart {
                        pauses.append(DateInterval(start: p, end: Date()))
                        pauseStart = nil
                    }
                    ended = Date()
                }
            }
            .padding(.bottom, 30)
        }
    }

    private func circle(_ icon: String, _ color: Color, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: size, height: size)
                .background(color, in: Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: pauseStart)
    }

    private var finishForm: some View {
        let endDate = ended ?? Date()
        return VStack(spacing: 18) {
            Spacer()
            Image(systemName: saved ? "checkmark.circle.fill" : machine.icon)
                .font(.system(size: 64)).foregroundStyle(saved ? Theme.accent : Theme.calorie)
            Text(saved ? "Saved to Apple Health" : machine.name).font(.title2.weight(.bold))
            Text(Fmt.clock(active(at: endDate))).font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
            if !saved {
                VStack(spacing: 12) {
                    if machine.distanceType != nil {
                        field("Distance from the machine (\(Fmt.distanceUnit(metric)))", $distanceText, "optional")
                    }
                    field("Calories from the machine", $caloriesText, "≈ \(Fmt.steps(estimatedKcal(at: endDate)))")
                }
                .padding(16)
                .card()
                .padding(.horizontal, 20)
            }
            if let errorText { Text(errorText).font(.footnote).foregroundStyle(.yellow) }
            Spacer()
            if saved {
                wide("Done", Theme.accent) { dismiss() }
            } else {
                wide(saving ? "Saving…" : "Save to Health", Theme.accent) { save(end: endDate) }
                    .disabled(saving)
                Button("Discard") { confirmDiscard = true }.foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 24)
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
        }
    }

    private func field(_ title: String, _ text: Binding<String>, _ placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold).monospacedDigit())
                .padding(10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func wide(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 24)
    }

    private func save(end: Date) {
        saving = true
        let number: (String) -> Double? = { Double($0.replacingOccurrences(of: ",", with: ".")) }
        let meters = (number(distanceText) ?? 0) * (metric ? 1000 : 1609.344)
        let kcal = number(caloriesText) ?? estimatedKcal(at: end)
        Task {
            do {
                try await health.saveWorkout(machine.activity, start: start, end: end,
                                             meters: meters, distanceType: machine.distanceType ?? .distanceWalkingRunning,
                                             kcal: kcal, indoor: true, pauses: pauses,
                                             metadata: ["SkiStepsRoutine": machine.name])
                withAnimation(.spring) { saved = true }
            } catch {
                errorText = "Couldn't save: \(error.localizedDescription)"
            }
            saving = false
        }
    }
}
