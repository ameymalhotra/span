import Foundation
import Observation

/// Asks GitHub whether a newer release exists.
///
/// This is the only network request Span makes, it sends nothing but the
/// request itself, and it can be switched off in Settings — which is why the
/// app's copy says "the only network request" rather than "no network".
@MainActor
@Observable
final class UpdateChecker {

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed
    }

    private(set) var state: State = .idle

    /// Current bundle version, e.g. "1.0".
    let currentVersion: String = Bundle.main
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private let endpoint = URL(string: "https://api.github.com/repos/ameymalhotra/span/releases/latest")!
    private let lastCheckKey = "update.lastCheckedAt"

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "update.checkAutomatically") as? Bool ?? true
    }

    /// Checked at most once a day on launch; a manual check ignores that.
    func checkIfDue() async {
        guard isEnabled else { return }
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        if let last, Date.now.timeIntervalSince(last) < 24 * 3600 { return }
        await check()
    }

    func check() async {
        state = .checking
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String
            else {
                state = .failed
                return
            }
            UserDefaults.standard.set(Date.now, forKey: lastCheckKey)

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let page = (json["html_url"] as? String).flatMap(URL.init(string:))
                ?? URL(string: "https://github.com/ameymalhotra/span/releases/latest")!

            state = Self.isNewer(latest, than: currentVersion)
                ? .available(version: latest, url: page)
                : .upToDate
        } catch {
            // A failed check is not worth reporting as an error; the app works
            // perfectly well without ever reaching GitHub.
            state = .failed
        }
    }

    /// Numeric component comparison, so 1.10 is newer than 1.9 — which a string
    /// comparison would get backwards.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
