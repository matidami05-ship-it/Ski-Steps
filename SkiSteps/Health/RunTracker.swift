import Foundation
import CoreLocation
import AVFoundation
import UIKit

/// Records a run with GPS: distance, time, pace, route, and spoken splits.
@MainActor
final class RunTracker: NSObject, ObservableObject {
    enum State { case idle, running, paused }

    @Published var state: State = .idle
    @Published var meters: Double = 0
    @Published var elapsed: TimeInterval = 0
    @Published var route: [CLLocation] = []
    @Published var currentPaceSeconds: TimeInterval?   // per mile/km, last ~30 s
    @Published var gpsAccuracy: Double?
    @Published var locationDenied = false

    private let manager = CLLocationManager()
    private let speech = AVSpeechSynthesizer()
    private var startDate: Date?
    private var segmentStart: Date?
    private var accumulated: TimeInterval = 0
    private var pauses: [DateInterval] = []
    private var pauseStart: Date?
    private var lastLocation: CLLocation?
    private var timer: Timer?
    private var lastAnnounced = 0

    private var useMetric: Bool { UserDefaults.standard.bool(forKey: "useMetric") }
    private var unitMeters: Double { useMetric ? 1000 : 1609.344 }

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        speech.delegate = self
    }

    /// Start GPS early so the signal is ready when the run starts.
    func warmUp() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: locationDenied = true; return
        default: break
        }
        manager.startUpdatingLocation()
    }

    func start() {
        guard !locationDenied else { return }
        meters = 0; elapsed = 0; route = []; pauses = []; accumulated = 0
        lastLocation = nil; lastAnnounced = 0; currentPaceSeconds = nil
        let now = Date()
        startDate = now
        segmentStart = now
        state = .running

        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        UIApplication.shared.isIdleTimerDisabled = true
        say("Run started")
    }

    func pause() {
        guard state == .running, let seg = segmentStart else { return }
        let now = Date()
        accumulated += now.timeIntervalSince(seg)
        segmentStart = nil
        pauseStart = now
        lastLocation = nil
        state = .paused
        tick()
        say("Paused")
    }

    func resume() {
        guard state == .paused else { return }
        let now = Date()
        if let p = pauseStart { pauses.append(DateInterval(start: p, end: now)) }
        pauseStart = nil
        segmentStart = now
        state = .running
        say("Resumed")
    }

    /// Stops and saves to Apple Health. Returns false if there was nothing to save.
    func finish(saveTo health: HealthStore) async throws -> Bool {
        let end = Date()
        if state == .paused, let p = pauseStart { pauses.append(DateInterval(start: p, end: end)) }
        tick()
        let start = startDate
        let distance = meters
        let points = route
        let pauseList = pauses
        stop()
        guard let start, elapsed >= 30 || distance > 50 else { return false }
        try await health.saveRun(start: start, end: end, meters: distance, locations: points, pauses: pauseList)
        return true
    }

    func discard() { stop() }

    private func stop() {
        timer?.invalidate()
        timer = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        UIApplication.shared.isIdleTimerDisabled = false
        state = .idle
        segmentStart = nil
        pauseStart = nil
    }

    func coolDown() {
        if state == .idle { manager.stopUpdatingLocation() }
    }

    private func tick() {
        elapsed = accumulated + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func handle(_ locations: [CLLocation]) {
        for loc in locations {
            gpsAccuracy = loc.horizontalAccuracy
            guard state == .running,
                  loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 30,
                  abs(loc.timestamp.timeIntervalSinceNow) < 10 else { continue }
            if let last = lastLocation {
                let d = loc.distance(from: last)
                let dt = loc.timestamp.timeIntervalSince(last.timestamp)
                // Ignore GPS jumps faster than ~12 m/s.
                if dt > 0, d / dt < 12 { meters += d }
            }
            lastLocation = loc
            route.append(loc)
        }
        updateCurrentPace()
        announceSplits()
    }

    private func updateCurrentPace() {
        let cutoff = Date().addingTimeInterval(-30)
        let recent = route.filter { $0.timestamp >= cutoff }
        guard recent.count >= 3, let first = recent.first, let last = recent.last else {
            currentPaceSeconds = nil
            return
        }
        var d = 0.0
        for i in 1..<recent.count { d += recent[i].distance(from: recent[i - 1]) }
        let t = last.timestamp.timeIntervalSince(first.timestamp)
        guard d > 15, t > 5 else { currentPaceSeconds = nil; return }
        currentPaceSeconds = t / (d / unitMeters)
    }

    private func announceSplits() {
        let n = Int(meters / unitMeters)
        guard n > lastAnnounced else { return }
        lastAnnounced = n
        let unit = useMetric ? (n == 1 ? "kilometer" : "kilometers") : (n == 1 ? "mile" : "miles")
        let pace = Fmt.pace(seconds: elapsed, meters: meters, metric: useMetric)
        say("\(n) \(unit). Time \(spoken(elapsed)). Average pace \(spoken(pace)) per \(useMetric ? "kilometer" : "mile").")
    }

    private func spoken(_ seconds: TimeInterval) -> String {
        let s = Int(seconds), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        if sec > 0 || parts.isEmpty { parts.append("\(sec) second\(sec == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }

    private func spoken(_ pace: String) -> String {
        let parts = pace.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return pace }
        return "\(parts[0]) \(parts[1] == 0 ? "flat" : String(format: "%02d", parts[1]))"
    }

    private func say(_ text: String) {
        guard UserDefaults.standard.object(forKey: "runVoice") as? Bool ?? true else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        speech.speak(utterance)
    }

    // MARK: Live numbers

    var averagePaceText: String { Fmt.pace(seconds: elapsed, meters: meters, metric: useMetric) }
    var currentPaceText: String { currentPaceSeconds.map { Fmt.clock($0) } ?? "--:--" }
    var distanceText: String { Fmt.distance(meters, metric: useMetric) }
    var unitText: String { Fmt.distanceUnit(useMetric) }
}

extension RunTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.handle(locations) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationDenied = (status == .denied || status == .restricted)
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }
}

extension RunTracker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
