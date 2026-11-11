import SwiftUI
import MapKit

struct RunTrackerView: View {
    @EnvironmentObject private var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker = RunTracker()
    @AppStorage("runVoice") private var voice = true
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var confirmEnd = false
    @State private var saving = false
    @State private var saved = false
    @State private var errorText: String?
    @State private var countdown: Int?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                map
                    .frame(maxHeight: .infinity)
                metrics
                controls
            }
            if let countdown {
                Color.black.opacity(0.75).ignoresSafeArea()
                Text(countdown > 0 ? "\(countdown)" : "GO")
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText(countsDown: true))
            }
            if saved {
                Color.black.opacity(0.8).ignoresSafeArea()
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(Theme.accent)
                    Text("Run saved to Apple Health").font(.title3.weight(.bold))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { tracker.warmUp() }
        .onDisappear { tracker.coolDown() }
        .sensoryFeedback(.impact(weight: .heavy), trigger: tracker.state)
        .confirmationDialog("End this run?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Save Run") { save() }
            Button("Discard Run", role: .destructive) {
                tracker.discard()
                dismiss()
            }
            Button("Keep Going", role: .cancel) {}
        }
        .alert("Couldn't save the run", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: Map

    private var map: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                UserAnnotation()
                if tracker.route.count > 1 {
                    MapPolyline(coordinates: tracker.route.map(\.coordinate))
                        .stroke(Theme.run, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls { MapUserLocationButton() }

            HStack {
                if tracker.state == .idle {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                Spacer()
                gpsBadge
                Button {
                    voice.toggle()
                } label: {
                    Image(systemName: voice ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.subheadline)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var gpsBadge: some View {
        let acc = tracker.gpsAccuracy
        let (label, color): (String, Color) = {
            guard let acc, acc >= 0 else { return ("Finding GPS", .yellow) }
            if acc <= 15 { return ("GPS strong", Theme.accent) }
            if acc <= 40 { return ("GPS fair", .yellow) }
            return ("GPS weak", Theme.calorie)
        }()
        return Label(label, systemImage: "location.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: Metrics

    private var metrics: some View {
        VStack(spacing: 16) {
            if tracker.locationDenied {
                Text("Location is off for Ski Steps. Turn it on in Settings › Privacy › Location Services to record runs.")
                    .font(.footnote)
                    .foregroundStyle(.yellow)
                    .multilineTextAlignment(.center)
            }
            Text(Fmt.clock(tracker.elapsed))
                .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(tracker.state == .paused ? Theme.gold : .white)
            HStack(spacing: 0) {
                bigStat(tracker.distanceText, tracker.unitText, Theme.accent2)
                bigStat(tracker.averagePaceText, "avg pace", Theme.run)
                bigStat(tracker.currentPaceText, "current", Theme.accent)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 16)
    }

    private func bigStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 28) {
            switch tracker.state {
            case .idle:
                circleButton("Start", icon: "play.fill", color: Theme.accent, size: 96) { startCountdown() }
                    .disabled(tracker.locationDenied || countdown != nil)
            case .running:
                circleButton("Pause", icon: "pause.fill", color: Theme.gold, size: 96) { tracker.pause() }
            case .paused:
                circleButton("End", icon: "stop.fill", color: Theme.calorie, size: 80) { confirmEnd = true }
                circleButton("Resume", icon: "play.fill", color: Theme.accent, size: 96) { tracker.resume() }
            }
        }
        .padding(.vertical, 28)
        .overlay {
            if saving { ProgressView().scaleEffect(1.4) }
        }
    }

    private func circleButton(_ title: String, icon: String, color: Color, size: CGFloat,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: size, height: size)
                    .background(color, in: Circle())
                    .shadow(color: color.opacity(0.5), radius: 14)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func startCountdown() {
        Task { @MainActor in
            for n in stride(from: 3, through: 0, by: -1) {
                withAnimation { countdown = n }
                try? await Task.sleep(for: .seconds(n == 0 ? 0.5 : 1))
            }
            countdown = nil
            camera = .userLocation(followsHeading: false, fallback: .automatic)
            tracker.start()
        }
    }

    private func save() {
        saving = true
        Task { @MainActor in
            do {
                let didSave = try await tracker.finish(saveTo: health)
                saving = false
                if didSave {
                    withAnimation(.spring) { saved = true }
                    try? await Task.sleep(for: .seconds(1.3))
                }
                dismiss()
            } catch {
                saving = false
                errorText = "Ski Steps needs permission to save workouts. Open Health › Sharing › Apps › Ski Steps and turn on Workouts."
            }
        }
    }
}
