import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

/// AI analysis of your activity and sleep.
/// Uses Apple Intelligence on the iPhone when available (free, stays on the
/// phone); otherwise Claude with your own Anthropic API key.
@MainActor
final class AICoach: ObservableObject {
    static let shared = AICoach()

    enum Provider: String, CaseIterable, Identifiable {
        case auto, apple, claude
        var id: Self { self }
        var title: String {
            switch self {
            case .auto: "Automatic"
            case .apple: "Apple Intelligence"
            case .claude: "Claude"
            }
        }
    }

    struct Result: Codable {
        var text: String
        var date: Date
        var provider: String
    }

    @Published private(set) var results: [String: Result] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var hasClaudeKey = false

    private let resultsKey = "aiResults.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: resultsKey),
           let saved = try? JSONDecoder().decode([String: Result].self, from: data) {
            results = saved
        }
        hasClaudeKey = Keychain.get("claudeAPIKey")?.isEmpty == false
    }

    // MARK: Settings

    var preferred: Provider {
        Provider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "auto") ?? .auto
    }

    var claudeModel: String {
        UserDefaults.standard.string(forKey: "claudeModel") ?? "claude-sonnet-5-5"
    }

    func setClaudeKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { Keychain.delete("claudeAPIKey") } else { Keychain.set(trimmed, for: "claudeAPIKey") }
        hasClaudeKey = !trimmed.isEmpty
    }

    var appleStatus: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Ready on this iPhone"
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return "Not supported on this iPhone"
                case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in Settings"
                case .modelNotReady: return "Downloading — try again later"
                @unknown default: return "Not available"
                }
            }
        }
        #endif
        return "Needs iOS 26 or later"
    }

    var appleAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Which engine will actually be used.
    var active: Provider? {
        switch preferred {
        case .apple: return appleAvailable ? .apple : nil
        case .claude: return hasClaudeKey ? .claude : nil
        case .auto: return appleAvailable ? .apple : (hasClaudeKey ? .claude : nil)
        }
    }

    // MARK: Analysis

    func analyze(_ kind: String, prompt: String) async {
        guard !loading.contains(kind) else { return }
        guard let provider = active else {
            errors[kind] = "Set up AI first: Settings › AI Coach."
            return
        }
        loading.insert(kind)
        errors[kind] = nil
        defer { loading.remove(kind) }
        do {
            let text: String
            switch provider {
            case .apple:
                text = try await askApple(prompt)
            default:
                text = try await askClaude(prompt)
            }
            results[kind] = Result(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                   date: Date(), provider: provider == .apple ? "Apple Intelligence" : "Claude")
            if let data = try? JSONEncoder().encode(results) {
                UserDefaults.standard.set(data, forKey: resultsKey)
            }
        } catch {
            errors[kind] = error.localizedDescription
        }
    }

    static let instructions = """
    You are a friendly, encouraging fitness and sleep coach inside the Ski Steps app. \
    You get a summary of the user's recent data from Apple Health. Reply in plain markdown:
    - Start with one bold headline sentence.
    - Then 3–5 short bullet points with specific insights that quote the user's actual numbers \
    (trends, best/worst days, patterns between sleep and activity).
    - Then a line "**This week, try:**" followed by 2–3 concrete, achievable suggestions as bullets.
    Keep it under 220 words. Don't invent data that isn't in the summary. This is general wellness \
    guidance, not medical advice: never diagnose. If something looks concerning (for example \
    regularly sleeping under 5 hours, or resting heart rate rising sharply), gently suggest \
    talking to a doctor.
    """

    private func askApple(_ prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif
        throw CoachError.message("Apple Intelligence isn't available on this iPhone.")
    }

    private func askClaude(_ prompt: String) async throws -> String {
        guard let key = Keychain.get("claudeAPIKey"), !key.isEmpty else {
            throw CoachError.message("Add your Claude API key in Settings › AI Coach.")
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": claudeModel,
            "max_tokens": 1000,
            "system": Self.instructions,
            "messages": [["role": "user", "content": prompt]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            if status == 401 { throw CoachError.message("Claude rejected the API key. Check it in Settings › AI Coach.") }
            throw CoachError.message("Claude: \(msg)")
        }
        let parts = (json?["content"] as? [[String: Any]]) ?? []
        let text = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        guard !text.isEmpty else { throw CoachError.message("Claude returned an empty answer.") }
        return text
    }

    enum CoachError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let m): m }
        }
    }
}

// MARK: - Data summaries for the prompts

extension HealthStore {
    private var aiUseMetric: Bool { UserDefaults.standard.bool(forKey: "useMetric") }
    private var aiSleepGoal: Double {
        let g = UserDefaults.standard.double(forKey: "sleepGoal")
        return g > 0 ? g : 8
    }

    func sleepSummary(nights count: Int = 14) -> String {
        let recent = nights.suffix(count)
        guard !recent.isEmpty else { return "No sleep data in Apple Health for the last \(count) nights." }
        var lines = ["Sleep goal: \(aiSleepGoal) h. Last \(recent.count) nights (wake date: asleep, in bed, bedtime→wake, stages):"]
        for n in recent {
            var line = "\(n.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())): "
                + "asleep \(SleepFmt.hours(n.asleep)), in bed \(SleepFmt.hours(n.inBed)), "
                + "\(n.bedtime.formatted(date: .omitted, time: .shortened))→\(n.wake.formatted(date: .omitted, time: .shortened))"
            if n.hasStages {
                line += ", deep \(SleepFmt.hours(n.total(.deep))), REM \(SleepFmt.hours(n.total(.rem))), core \(SleepFmt.hours(n.total(.core))), awake \(SleepFmt.hours(n.total(.awake)))"
            }
            line += ", score \(n.score(goalHours: aiSleepGoal, usualBedtime: nights.usualBedtime(before: n)))"
            lines.append(line)
        }
        let avg = recent.map(\.asleep).reduce(0, +) / Double(recent.count)
        lines.append("Average asleep: \(SleepFmt.hours(avg)). Source: \(recent.last!.source).")
        return lines.joined(separator: "\n")
    }

    func activitySummary(days: Int = 14) -> String {
        var lines: [String] = []
        let goals = Metric.allCases.map { m in
            "\(m.title) \(m.text(m.display(m.goal(), useMetric: aiUseMetric))) \(m.unit(useMetric: aiUseMetric))"
        }
        lines.append("Daily goals: " + goals.joined(separator: ", ") + ".")
        lines.append("Last \(days) days (steps, distance, active cal, exercise min):")
        let steps = (history[.steps] ?? []).suffix(days)
        for p in steps {
            let d = p.date
            func v(_ m: Metric) -> Double {
                (history[m] ?? []).first { Calendar.current.isDate($0.date, inSameDayAs: d) }?.value ?? 0
            }
            lines.append("\(d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())): "
                + "\(Int(p.value)) steps, \(Fmt.distance(v(.distance), metric: aiUseMetric)) \(Fmt.distanceUnit(aiUseMetric)), "
                + "\(Int(v(.calories))) cal, \(Int(v(.active))) min")
        }
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let recent = workouts.filter { $0.start >= since }
        if recent.isEmpty {
            lines.append("No workouts in this period.")
        } else {
            lines.append("Workouts:")
            for w in recent.prefix(20) {
                var l = "\(w.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) \(w.name): \(Fmt.clock(w.duration))"
                if let d = w.distanceText(metric: aiUseMetric) { l += ", \(d)" }
                if w.energy > 0 { l += ", \(Int(w.energy)) cal" }
                if w.averageHeartRate > 0 { l += ", avg HR \(Int(w.averageHeartRate))" }
                lines.append(l)
            }
        }
        lines.append("Resting heart rate: \(Int(restingHR)) bpm. Training load: fitness \(Int(training.fitness)), fatigue \(Int(training.fatigue)), form \(Int(training.form)).")
        lines.append("Streak (steps goal): \(streak(.steps, goal: Metric.steps.goal())) days.")
        return lines.joined(separator: "\n")
    }

    func sleepPrompt() -> String {
        "Analyze my sleep. Look at duration vs. goal, consistency of bedtime/wake time, stages if available, and how activity may relate.\n\n"
            + sleepSummary() + "\n\nActivity for context:\n" + activitySummary(days: 7)
    }

    func overallPrompt() -> String {
        "Give me my weekly coaching summary covering activity, workouts, training load and sleep.\n\n"
            + activitySummary() + "\n\n" + sleepSummary(nights: 7)
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.skistudio.steps"

    static func set(_ value: String, for key: String) {
        delete(key)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(q as CFDictionary)
    }
}
