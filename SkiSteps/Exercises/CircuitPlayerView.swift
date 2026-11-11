import SwiftUI
import AVFoundation
import HealthKit

/// Runs a circuit: get ready → work → rest → work … with voice cues.
@MainActor
final class CircuitEngine: ObservableObject {
    enum Kind { case ready, work, rest }

    struct Phase {
        var kind: Kind
        var exercise: Exercise
        var duration: Double
        var round: Int
        var number: Int   // exercise number within the round (1-based)
    }

    let routine: Routine
    let phases: [Phase]
    @Published var index = 0
    @Published var remaining: Double = 0
    @Published var paused = false
    @Published var finished = false
    @Published var exercisesDone = 0

    private(set) var startDate = Date()
    private(set) var endDate: Date?
    private(set) var pauses: [DateInterval] = []
    private(set) var kcal: Double = 0
    private var pauseStart: Date?
    private var phaseEnd = Date()
    private var timer: Timer?
    private var lastSpokenSecond = -1
    private var switchAnnounced = false
    private let speech = AVSpeechSynthesizer()
    var bodyKg: Double = 75

    var voice: Bool { UserDefaults.standard.object(forKey: "circuitVoice") as? Bool ?? true }

    init(routine: Routine) {
        self.routine = routine
        var list: [Phase] = []
        let ex = routine.exercises
        if let first = ex.first {
            list.append(Phase(kind: .ready, exercise: first, duration: 10, round: 1, number: 1))
        }
        for round in 1...max(routine.rounds, 1) {
            for (i, e) in ex.enumerated() {
                list.append(Phase(kind: .work, exercise: e, duration: Double(routine.work), round: round, number: i + 1))
                let isLast = round == routine.rounds && i == ex.count - 1
                if !isLast, routine.rest > 0 {
                    let next = i + 1 < ex.count ? ex[i + 1] : ex[0]
                    list.append(Phase(kind: .rest, exercise: next, duration: Double(routine.rest),
                                      round: i + 1 < ex.count ? round : round + 1,
                                      number: i + 1 < ex.count ? i + 2 : 1))
                }
            }
        }
        phases = list
    }

    var phase: Phase { phases[min(index, phases.count - 1)] }
    var progress: Double { phase.duration > 0 ? 1 - remaining / phase.duration : 0 }

    var nextWork: Exercise? {
        phases.dropFirst(index + 1).first { $0.kind == .work }?.exercise
    }

    var elapsedActive: TimeInterval {
        let end = endDate ?? Date()
        let paused = pauses.reduce(0) { $0 + $1.duration } + (pauseStart.map { end.timeIntervalSince($0) } ?? 0)
        return end.timeIntervalSince(startDate) - paused
    }

    func start() {
        guard !phases.isEmpty else { finished = true; return }
        startDate = Date()
        begin(0)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func togglePause() {
        if paused {
            if let p = pauseStart { pauses.append(DateInterval(start: p, end: Date())) }
            pauseStart = nil
            phaseEnd = Date().addingTimeInterval(remaining)
            paused = false
            say("Resume")
        } else {
            pauseStart = Date()
            paused = true
            say("Paused")
        }
    }

    func skip() {
        addCalories(for: phase, seconds: phase.duration - remaining)
        if phase.kind == .work { exercisesDone += 1 }
        advance()
    }

    func back() {
        // Go to the start of the previous work phase (or restart this one).
        var target = index
        if phase.duration - remaining < 3 {
            target = (phases[..<index].lastIndex { $0.kind == .work }) ?? 0
        }
        if paused { togglePause() }
        begin(target)
    }

    func stop() {
        guard !finished else { return }
        if paused, let p = pauseStart { pauses.append(DateInterval(start: p, end: Date())) }
        pauseStart = nil
        addCalories(for: phase, seconds: phase.duration - remaining)
        finish(announce: false)
    }

    private func begin(_ i: Int) {
        index = i
        remaining = phases[i].duration
        phaseEnd = Date().addingTimeInterval(remaining)
        lastSpokenSecond = Int(remaining.rounded(.up))
        switchAnnounced = false
        let p = phases[i]
        switch p.kind {
        case .ready:
            say("Get ready. First up: \(p.exercise.name).")
        case .work:
            say(p.exercise.name)
            haptic(.success)
        case .rest:
            say("Rest. Next up: \(p.exercise.name).")
            haptic(.warning)
        }
    }

    private func tick() {
        guard !paused, !finished else { return }
        remaining = max(phaseEnd.timeIntervalSinceNow, 0)
        let sec = Int(remaining.rounded(.up))
        if sec != lastSpokenSecond {
            lastSpokenSecond = sec
            if sec <= 3, sec >= 1 { say("\(sec)", rate: 0.55) }
        }
        if phase.kind == .work, phase.exercise.sided, !switchAnnounced, remaining <= phase.duration / 2 {
            switchAnnounced = true
            say("Switch sides")
            haptic(.warning)
        }
        if remaining <= 0 {
            addCalories(for: phase, seconds: phase.duration)
            if phase.kind == .work { exercisesDone += 1 }
            advance()
        }
    }

    private func advance() {
        if index + 1 < phases.count {
            begin(index + 1)
        } else {
            finish(announce: true)
        }
    }

    private func finish(announce: Bool) {
        timer?.invalidate()
        timer = nil
        endDate = Date()
        finished = true
        UIApplication.shared.isIdleTimerDisabled = false
        if announce {
            say("Workout complete. Great job!")
            haptic(.success)
        }
    }

    private func addCalories(for p: Phase, seconds: Double) {
        guard seconds > 0 else { return }
        let met = p.kind == .work ? p.exercise.met : 2.5
        kcal += met * bodyKg * seconds / 3600
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    private func say(_ text: String, rate: Float = 0.5) {
        guard voice else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = rate
        speech.stopSpeaking(at: .immediate)
        speech.speak(u)
    }
}

struct CircuitPlayerView: View {
    let routine: Routine
    @EnvironmentObject private var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine: CircuitEngine
    @AppStorage("circuitVoice") private var voice = true
    @State private var confirmEnd = false
    @State private var saving = false
    @State private var saved = false
    @State private var errorText: String?
    @State private var showSteps = false

    init(routine: Routine) {
        self.routine = routine
        _engine = StateObject(wrappedValue: CircuitEngine(routine: routine))
    }

    private var color: Color {
        switch engine.phase.kind {
        case .ready: Theme.gold
        case .work: engine.phase.exercise.area.color
        case .rest: Theme.accent2
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [color.opacity(0.35), Theme.bgTop, Theme.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: engine.index)
            if engine.finished {
                summary
            } else {
                player
            }
        }
        .preferredColorScheme(.dark)
        .task {
            engine.bodyKg = await health.bodyMassKg()
            engine.start()
        }
        .onDisappear { if !engine.finished { engine.stop() } }
        .confirmationDialog("End workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End & Review") { engine.stop() }
            Button("Discard", role: .destructive) {
                engine.stop()
                dismiss()
            }
            Button("Keep Going", role: .cancel) {}
        }
    }

    // MARK: Player

    private var player: some View {
        VStack(spacing: 0) {
            HStack {
                Button { confirmEnd = true } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(routine.name).font(.headline)
                    Text("Round \(engine.phase.round) of \(routine.rounds) · \(engine.phase.number)/\(routine.exercises.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { voice.toggle() } label: {
                    Image(systemName: voice ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.subheadline)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Overall progress
            GeometryReader { geo in
                let total = max(engine.phases.count, 1)
                HStack(spacing: 2) {
                    ForEach(engine.phases.indices.filter { engine.phases[$0].kind == .work }, id: \.self) { i in
                        Capsule()
                            .fill(i < engine.index ? color : (i == engine.index ? color.opacity(0.6) : Color.white.opacity(0.15)))
                    }
                }
                .frame(width: geo.size.width)
                .id(total)
            }
            .frame(height: 4)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer(minLength: 12)

            Text(phaseLabel)
                .font(.headline.weight(.heavy))
                .tracking(2)
                .foregroundStyle(color)

            ZStack {
                ProgressRing(progress: engine.progress, lineWidth: 18, colors: [color.opacity(0.6), color])
                VStack(spacing: 6) {
                    Image(systemName: engine.phase.exercise.icon)
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(color)
                        .symbolEffect(.bounce, value: engine.index)
                    Text("\(Int(engine.remaining.rounded(.up)))")
                        .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: Int(engine.remaining.rounded(.up)))
                }
            }
            .frame(width: 270, height: 270)
            .padding(.vertical, 12)

            Text(engine.phase.exercise.name)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            if engine.phase.kind != .work {
                Text(engine.phase.kind == .ready ? "First exercise" : "Up next")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let next = engine.nextWork {
                Text("Next: \(next.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                withAnimation { showSteps.toggle() }
            } label: {
                Label(showSteps ? "Hide how-to" : "How to do it", systemImage: "info.circle")
                    .font(.footnote.weight(.semibold))
            }
            .padding(.top, 8)
            if showSteps {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(engine.phase.exercise.steps.enumerated()), id: \.offset) { i, step in
                        Text("\(i + 1). \(step)").font(.footnote)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .transition(.opacity)
            }

            Spacer(minLength: 12)

            HStack(spacing: 36) {
                control("backward.fill", 60) { engine.back() }
                control(engine.paused ? "play.fill" : "pause.fill", 84, filled: true) { engine.togglePause() }
                control("forward.fill", 60) { engine.skip() }
            }
            .padding(.bottom, 30)
        }
    }

    private var phaseLabel: String {
        if engine.paused { return "PAUSED" }
        switch engine.phase.kind {
        case .ready: return "GET READY"
        case .work: return "WORK"
        case .rest: return "REST"
        }
    }

    private func control(_ icon: String, _ size: CGFloat, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(filled ? .black : .white)
                .frame(width: size, height: size)
                .background(filled ? AnyShapeStyle(color) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: engine.paused)
    }

    // MARK: Summary

    private var summary: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: saved ? "checkmark.circle.fill" : "flame.fill")
                .font(.system(size: 72))
                .foregroundStyle(saved ? Theme.accent : Theme.calorie)
            Text(saved ? "Saved to Apple Health" : "Nice work!")
                .font(.title.weight(.bold))
            Text(routine.name).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                stat(Fmt.clock(engine.elapsedActive), "time")
                stat("\(engine.exercisesDone)", "exercises")
                stat(Fmt.steps(engine.kcal), "cal")
            }
            .padding(.vertical, 16)
            .card()
            .padding(.horizontal, 24)
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.yellow).multilineTextAlignment(.center).padding(.horizontal)
            }
            Spacer()
            if saved {
                bigButton("Done", Theme.accent) { dismiss() }
            } else {
                bigButton(saving ? "Saving…" : "Save to Health", Theme.accent) { save() }
                    .disabled(saving || engine.elapsedActive < 30)
                Button("Discard") { dismiss() }
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 30)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func bigButton(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 24)
    }

    private func save() {
        saving = true
        let activity: HKWorkoutActivityType = routine.mainArea == .cardio ? .highIntensityIntervalTraining
            : (routine.mainArea == .core ? .coreTraining : .functionalStrengthTraining)
        Task {
            do {
                try await health.saveWorkout(activity, start: engine.startDate, end: engine.endDate ?? Date(),
                                             kcal: engine.kcal, indoor: true, pauses: engine.pauses,
                                             metadata: ["SkiStepsRoutine": routine.name])
                withAnimation(.spring) { saved = true }
            } catch {
                errorText = "Couldn't save: \(error.localizedDescription)"
            }
            saving = false
        }
    }
}
