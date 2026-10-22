import Foundation

/// Only structured GitHub quota evidence is rendered; remote error text is never echoed.
struct GitHubRateLimit: Error, LocalizedError, Codable {
    static let maximumErrorBodySize = 16_384
    private static let maximumTimestamp: TimeInterval = 253_402_300_799
    let statusCode: Int
    let retryAt: Date?

    static func parse(response: HTTPURLResponse, body: Data = Data(), now: Date = Date()) -> Self? {
        guard response.statusCode == 403 || response.statusCode == 429 else { return nil }
        func header(_ name: String) -> String? {
            response.value(forHTTPHeaderField: name)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func number(_ value: String?) -> TimeInterval? {
            guard let value, !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Double(value), number.isFinite, number <= maximumTimestamp else { return nil }
            return number
        }
        let exhausted = header("X-RateLimit-Remaining") == "0"
        var retryAfter: Date?
        if let seconds = number(header("Retry-After")) {
            let deadline = now.timeIntervalSince1970 + seconds
            if deadline <= maximumTimestamp { retryAfter = Date(timeIntervalSince1970: deadline) }
        } else if let value = header("Retry-After"), value.count <= 128 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            formatter.isLenient = false
            if let date = formatter.date(from: value), formatter.string(from: date) == value {
                retryAfter = date
            }
        }
        var rateLimitBody = false
        if body.count <= maximumErrorBodySize,
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let message = object["message"] as? String {
            rateLimitBody = message.lowercased().contains("rate limit")
        }
        guard response.statusCode == 429 || exhausted || retryAfter != nil || rateLimitBody else { return nil }
        let reset = exhausted ? number(header("X-RateLimit-Reset")).map { Date(timeIntervalSince1970: $0) } : nil
        // Respect both constraints if GitHub supplies them together. Never claim a past reset is usable.
        let deadline = [retryAfter, reset].compactMap { $0 }.filter {
            $0 > now && $0.timeIntervalSince1970 <= maximumTimestamp
        }.max()
        return Self(statusCode: response.statusCode, retryAt: deadline)
    }

    var isValid: Bool {
        (statusCode == 403 || statusCode == 429) && (retryAt.map {
            $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 > 0 &&
                $0.timeIntervalSince1970 <= Self.maximumTimestamp
        } ?? true)
    }

    var errorDescription: String? { guidance() }

    func guidance(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let reason = L10n.text("GitHub API rate limit reached (HTTP \(statusCode)).")
        if let retryAt, retryAt > now {
            let minutes = Int(ceil(retryAt.timeIntervalSince(now) / 60))
            let timestamp = Self.timestamp(retryAt, timeZone: timeZone, short: false)
            return reason + " " + L10n.text("Retry after \(timestamp) (about \(minutes) min). Then run `tawl update check`.")
        }
        if retryAt != nil {
            return reason + " " + L10n.text("The previous wait has ended. Run `tawl update check` to try again.")
        }
        return reason + " " + L10n.text("GitHub did not provide a usable retry time. Wait at least 1 minute, then run `tawl update check`.")
    }

    func notice(now: Date = Date()) -> String {
        if let retryAt, retryAt > now {
            return L10n.text("Update rate limit · retry \(Self.timestamp(retryAt, timeZone: .current, short: true)) · tawl update check")
        }
        if retryAt != nil {
            return L10n.text("Update rate limit · retry now · tawl update check")
        }
        return L10n.text("Update rate limit · wait at least 1 min · tawl update check")
    }

    private static func timestamp(_ date: Date, timeZone: TimeZone, short: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = short ? "HH:mm:ss XXX" : "yyyy-MM-dd HH:mm:ss XXX"
        return formatter.string(from: date)
    }
}
