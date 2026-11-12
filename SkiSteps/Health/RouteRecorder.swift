import Foundation
import CoreLocation
import CoreMotion

/// Records GPS routes in the background while you walk, run or cycle, so
/// auto-detected workouts can be saved with a route map.
///
/// Uses Apple's live location updates (iOS 17+) with a background activity
/// session: GPS pauses by itself while you're still and resumes as soon as
/// you move, and iOS relaunches the app in the background if it was closed.
/// Visit and significant-change monitoring are extra wake-up triggers.
/// Points faster than ~30 km/h (driving) aren't kept.
@MainActor
final class RouteRecorder: NSObject, ObservableObject {
    static let shared = RouteRecorder()

    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var recording = false
    @Published private(set) var lastPoint: Date?

    private let manager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private var lastMoving: Date?
    private var started = false
    private var session: CLBackgroundActivitySession?
    private var updatesTask: Task<Void, Never>?
    private var buffer: [String] = []
    private var lastFlush = Date()

    var enabled: Bool { UserDefaults.standard.object(forKey: "recordRoutes") as? Bool ?? true }
    var hasAlways: Bool { authorization == .authorizedAlways }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("route-log.csv")
    }

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
    }

    // MARK: Control

    /// Call at launch (including background relaunches). Does nothing until
    /// location permission is granted.
    func start() {
        authorization = manager.authorizationStatus
        guard enabled else { stop(); return }
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else { return }
        guard !started else { return }
        started = true
        pruneOldPoints()

        // Keeps the app able to receive location in the background, and lets
        // iOS relaunch it if it was terminated while the session was active.
        session = CLBackgroundActivitySession()
        startLiveUpdates()

        if authorization == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
            manager.startMonitoringVisits()
        }

        if CMMotionActivityManager.isActivityAvailable() {
            motion.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity else { return }
                Task { @MainActor in self?.handle(activity) }
            }
        }
    }

    private func startLiveUpdates() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                        guard let self else { return }
                        if update.isStationary {
                            self.recording = false
                            self.flush()
                            continue
                        }
                        if let loc = update.location {
                            self.store([loc])
                        }
                    }
                } catch {
                    // Stream ended (e.g. permission change); try again shortly.
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stop() {
        started = false
        recording = false
        updatesTask?.cancel()
        updatesTask = nil
        session?.invalidate()
        session = nil
        motion.stopActivityUpdates()
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        flush()
    }

    /// Asks for "Always" location so routes can be recorded with the app closed.
    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // MARK: Motion (for the status display)

    private func handle(_ a: CMMotionActivity) {
        let moving = (a.walking || a.running || a.cycling) && a.confidence != .low
        if moving { lastMoving = Date() }
    }

    // MARK: Storage

    private func store(_ locations: [CLLocation]) {
        for l in locations where l.horizontalAccuracy >= 0 && l.horizontalAccuracy <= 50 {
            // Skip driving speeds (> ~30 km/h); walks, runs and rides stay.
            if l.speed > 8.5 { continue }
            recording = true
            lastPoint = l.timestamp
            buffer.append(String(format: "%.1f,%.6f,%.6f,%.1f,%.1f,%.2f,%.1f",
                                 l.timestamp.timeIntervalSince1970, l.coordinate.latitude, l.coordinate.longitude,
                                 l.altitude, l.horizontalAccuracy, max(l.speed, -1), l.course))
        }
        if buffer.count >= 30 || Date().timeIntervalSince(lastFlush) > 60 { flush() }
    }

    /// Points saved in the last 24 hours and when the newest one was taken.
    func stats() -> (count: Int, newest: Date?) {
        let pts = points(from: Date().addingTimeInterval(-86400), to: Date())
        return (pts.count, pts.last?.timestamp)
    }

    private func flush() {
        lastFlush = Date()
        guard !buffer.isEmpty else { return }
        let text = buffer.joined(separator: "\n") + "\n"
        buffer.removeAll()
        let url = Self.fileURL
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Recorded GPS points between two moments, oldest first.
    func points(from start: Date, to end: Date) -> [CLLocation] {
        flush()
        guard let text = try? String(contentsOf: Self.fileURL, encoding: .utf8) else { return [] }
        let lo = start.timeIntervalSince1970, hi = end.timeIntervalSince1970
        var out: [CLLocation] = []
        for line in text.split(separator: "\n") {
            let f = line.split(separator: ",")
            guard f.count >= 7, let t = Double(f[0]), t >= lo, t <= hi,
                  let lat = Double(f[1]), let lon = Double(f[2]), let alt = Double(f[3]),
                  let acc = Double(f[4]), let speed = Double(f[5]), let course = Double(f[6]) else { continue }
            out.append(CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                  altitude: alt, horizontalAccuracy: acc, verticalAccuracy: -1,
                                  course: course, speed: speed, timestamp: Date(timeIntervalSince1970: t)))
        }
        return out.sorted { $0.timestamp < $1.timestamp }
    }

    /// Keeps 8 days of points (motion history only goes back 7).
    private func pruneOldPoints() {
        guard let text = try? String(contentsOf: Self.fileURL, encoding: .utf8) else { return }
        let cutoff = Date().addingTimeInterval(-8 * 86400).timeIntervalSince1970
        let kept = text.split(separator: "\n").filter { line in
            guard let t = line.split(separator: ",").first.flatMap({ Double($0) }) else { return false }
            return t >= cutoff
        }
        try? (kept.joined(separator: "\n") + (kept.isEmpty ? "" : "\n"))
            .write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }
}

extension RouteRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Significant-change wake-ups: make sure live updates are running.
        Task { @MainActor in self.start() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in self.start() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                if self.started, status == .authorizedAlways {
                    self.manager.startMonitoringSignificantLocationChanges()
                }
                self.start()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
