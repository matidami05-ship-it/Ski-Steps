import SwiftUI
import HealthKit
import CoreMotion

/// One line of the Apple Health connection check.
struct CheckItem: Identifiable {
    enum Status { case ok, warning, fail, info }
    let id = UUID()
    var status: Status
    var title: String
    var detail: String
}

extension HealthStore {
    /// Works out why Health data might not be coming through.
    func runHealthCheck() async -> [CheckItem] {
        var items: [CheckItem] = []

        guard HKHealthStore.isHealthDataAvailable() else {
            return [CheckItem(status: .fail, title: "Apple Health isn't available",
                              detail: "This device doesn't support Apple Health.")]
        }
        items.append(CheckItem(status: .ok, title: "Apple Health is available", detail: "This iPhone supports Health data."))

        // 1. Can the app ask for access at all? This fails when the app was
        //    signed without the HealthKit capability.
        do {
            try await store.requestAuthorization(toShare: healthShareTypes, read: healthReadTypes)
            items.append(CheckItem(status: .ok, title: "HealthKit permission works",
                                   detail: "The app is signed correctly and can ask for Health access."))
        } catch {
            let ns = error as NSError
            let entitlement = ns.localizedDescription.localizedCaseInsensitiveContains("entitlement")
            items.append(CheckItem(
                status: .fail,
                title: entitlement ? "App was signed without HealthKit" : "Health access request failed",
                detail: entitlement
                    ? "iOS says: \(ns.localizedDescription) Re-install with Sideloadly signed in with your paid Apple Developer account, so the HealthKit capability is added to the app."
                    : "iOS says: \(ns.localizedDescription) (code \(ns.code))"))
            return items + [lastErrorItem].compactMap { $0 }
        }

        // 2. Write permission (visible to apps, unlike read permission).
        switch store.authorizationStatus(for: .workoutType()) {
        case .sharingAuthorized:
            items.append(CheckItem(status: .ok, title: "Can save workouts", detail: "Recorded and detected runs will save to Health."))
        case .sharingDenied:
            items.append(CheckItem(status: .warning, title: "Saving workouts is off",
                                   detail: "Turn on Workouts under Health › Sharing › Apps › Ski Steps to save runs."))
        default:
            items.append(CheckItem(status: .warning, title: "Health access not set up yet",
                                   detail: "Tap Reconnect Apple Health below and turn on all categories."))
        }

        // 3. Read permission: iOS hides it, so compare Health with the
        //    iPhone's own step counter.
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let healthSamples = await sampleCount(.stepCount, since: weekAgo)
        let today = Calendar.current.startOfDay(for: .now)
        let phoneSteps = await pedometerSteps(from: today, to: .now)
        let healthToday = steps

        if healthSamples.error != nil {
            items.append(CheckItem(status: .fail, title: "Reading steps failed",
                                   detail: "iOS says: \(healthSamples.error!)"))
        } else if healthSamples.count == 0 {
            if let phoneSteps, phoneSteps > 0 {
                items.append(CheckItem(status: .fail, title: "Steps permission is off",
                                       detail: "Your iPhone counted \(Fmt.steps(phoneSteps)) steps today, but Ski Steps can't read any. Open Health › your profile picture › Apps › Ski Steps and turn on all categories (Turn On All)."))
            } else {
                items.append(CheckItem(status: .warning, title: "No steps found in Health",
                                       detail: "Ski Steps can't see any steps from the last 7 days. Make sure Steps is turned on for Ski Steps in Health › Apps › Ski Steps."))
            }
        } else {
            items.append(CheckItem(status: .ok, title: "Reading steps works",
                                   detail: "Found \(healthSamples.count)\(healthSamples.count >= 500 ? "+" : "") step records in the last 7 days."))
        }

        if let phoneSteps {
            let diff = abs(phoneSteps - healthToday)
            let close = diff < max(500, phoneSteps * 0.15)
            items.append(CheckItem(status: close ? .info : .warning,
                                   title: "Today: Health \(Fmt.steps(healthToday)) · iPhone \(Fmt.steps(phoneSteps))",
                                   detail: close
                                       ? "Health merges your iPhone and Apple Watch, so small differences are normal."
                                       : "These don't match. Pull down to refresh; if it stays different, Health may still be syncing from your watch."))
        }

        // 4. Apple Watch data.
        let watch = stepsByDevice.first { $0.isWatch }
        items.append(CheckItem(status: watch == nil ? .info : .ok,
                               title: watch == nil ? "No Apple Watch steps today" : "Apple Watch data is coming in",
                               detail: watch == nil
                                   ? "If you wear an Apple Watch, it may still be syncing. Open the Health app on your iPhone to nudge it."
                                   : "\(Fmt.steps(watch!.value)) steps from \(watch!.name) today."))

        // 5. Other categories.
        for (id, name) in [(HKQuantityTypeIdentifier.activeEnergyBurned, "Active Energy"),
                           (.appleExerciseTime, "Exercise Minutes"),
                           (.heartRate, "Heart Rate")] {
            let n = await sampleCount(id, since: weekAgo)
            items.append(CheckItem(status: n.count > 0 ? .ok : .warning,
                                   title: n.count > 0 ? "\(name): reading works" : "\(name): nothing found",
                                   detail: n.count > 0 ? "Data from the last 7 days is visible."
                                       : "Turn on \(name) for Ski Steps in Health › Apps › Ski Steps. (Needs an Apple Watch for most of this data.)"))
        }

        if let item = lastErrorItem { items.append(item) }
        if let last = lastUpdated {
            items.append(CheckItem(status: .info, title: "Last updated \(last.formatted(date: .omitted, time: .standard))",
                                   detail: "The app refreshes when opened, when you pull down, and in the background when Health gets new data."))
        }
        return items
    }

    private var lastErrorItem: CheckItem? {
        guard let lastError else { return nil }
        return CheckItem(status: .warning, title: "Last Health error", detail: lastError)
    }

    private func sampleCount(_ id: HKQuantityTypeIdentifier, since start: Date) async -> (count: Int, error: String?) {
        let store = self.store
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKQuantityType(id),
                                  predicate: HKQuery.predicateForSamples(withStart: start, end: nil),
                                  limit: 500, sortDescriptors: nil) { _, samples, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    cont.resume(returning: (0, error.localizedDescription))
                } else {
                    cont.resume(returning: (samples?.count ?? 0, nil))
                }
            }
            store.execute(q)
        }
    }

    private func pedometerSteps(from start: Date, to end: Date) async -> Double? {
        guard CMPedometer.isStepCountingAvailable(),
              CMPedometer.authorizationStatus() != .denied,
              CMPedometer.authorizationStatus() != .restricted else { return nil }
        let pedometer = CMPedometer()
        return await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                cont.resume(returning: data?.numberOfSteps.doubleValue)
            }
        }
    }
}

struct HealthCheckView: View {
    @EnvironmentObject private var health: HealthStore
    @Environment(\.openURL) private var openURL
    @State private var items: [CheckItem] = []
    @State private var running = false
    @State private var copied = false

    var body: some View {
        List {
            Section {
                if running && items.isEmpty {
                    HStack { ProgressView(); Text("Checking…").foregroundStyle(.secondary) }
                }
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        icon(item.status)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("iOS doesn't tell apps which categories you've turned off for reading, so Ski Steps compares Health with your iPhone's own step counter to spot it.")
            }

            Section {
                Button {
                    Task { await run() }
                } label: {
                    Label("Run check again", systemImage: "arrow.clockwise")
                }
                .disabled(running)
                Button {
                    Task {
                        await health.requestAccess()
                        await run()
                    }
                } label: {
                    Label("Reconnect Apple Health", systemImage: "heart.fill")
                }
                Button {
                    if let url = URL(string: "x-apple-health://") { openURL(url) }
                } label: {
                    Label("Open the Health app", systemImage: "arrow.up.forward.app")
                }
                Button {
                    UIPasteboard.general.string = report
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy results", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } footer: {
                Text("To turn categories on: Health app › your profile picture (top right) › Apps › Ski Steps › Turn On All.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Health Connection")
        .task { await run() }
    }

    private var report: String {
        "Ski Steps Health check\n" + items.map { "[\($0.status)] \($0.title) — \($0.detail)" }.joined(separator: "\n")
    }

    private func run() async {
        running = true
        copied = false
        await health.refresh()
        items = await health.runHealthCheck()
        running = false
    }

    @ViewBuilder
    private func icon(_ s: CheckItem.Status) -> some View {
        switch s {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .fail: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .info: Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent2)
        }
    }
}
