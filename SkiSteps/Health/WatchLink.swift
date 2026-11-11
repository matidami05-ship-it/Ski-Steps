import Foundation
import WatchConnectivity

/// Sends goals and units to the Apple Watch app.
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    var isPaired: Bool { WCSession.isSupported() && WCSession.default.isPaired }
    var isAppInstalled: Bool { WCSession.isSupported() && WCSession.default.isWatchAppInstalled }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendSettings() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        var context: [String: Any] = ["useMetric": UserDefaults.standard.bool(forKey: "useMetric")]
        for m in Metric.allCases { context[m.goalKey] = m.goal() }
        try? WCSession.default.updateApplicationContext(context)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.sendSettings() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
