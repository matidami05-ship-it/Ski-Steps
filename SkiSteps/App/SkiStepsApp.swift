import SwiftUI
import UserNotifications

@main
struct SkiStepsApp: App {
    @StateObject private var health = HealthStore()
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate = ForegroundNotifications()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        WatchLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(health)
                .environmentObject(health.detector)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await health.refresh() } }
                }
        }
    }
}

/// Show the goal banner even while the app is open.
final class ForegroundNotifications: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

struct RootView: View {
    @EnvironmentObject private var health: HealthStore

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch health.access {
            case .unknown:
                ProgressView()
            case .needsRequest:
                OnboardingView()
            case .unavailable:
                UnavailableView()
            case .ready:
                MainTabs()
            }
        }
        .task { await health.start() }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "figure.walk") }
            WorkoutsView()
                .tabItem { Label("Workouts", systemImage: "figure.run") }
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
            HistoryView()
                .tabItem { Label("History", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var health: HealthStore
    @State private var working = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                ProgressRing(progress: 0.72, lineWidth: 18)
                    .frame(width: 170, height: 170)
                Image(systemName: "figure.walk")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(spacing: 10) {
                Text("Ski Steps")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("Steps, distance, calories, active time and workouts from Apple Health — with goals, streaks, run tracking and history.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Spacer()
            VStack(spacing: 12) {
                Button {
                    working = true
                    Task { await health.requestAccess(); working = false }
                } label: {
                    HStack {
                        if working { ProgressView().tint(.black) }
                        Image(systemName: "heart.fill")
                        Text("Connect Apple Health")
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Text("Ski Steps only saves runs you record or confirm. Nothing leaves your phone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
    }
}

struct UnavailableView: View {
    var body: some View {
        ContentUnavailableView("Apple Health isn't available",
                               systemImage: "heart.slash",
                               description: Text("Health data isn't available on this device."))
    }
}
