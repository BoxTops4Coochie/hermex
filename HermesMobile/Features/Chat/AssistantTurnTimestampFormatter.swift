import Foundation

enum AssistantTurnTimestampFormatter {
    private static let sharedFormatter: DateFormatter = makeFormatter(
        locale: .autoupdatingCurrent,
        timeZone: .autoupdatingCurrent
    )

    static func shortTime(forUnixTimestamp timestamp: Double?) -> String? {
        format(timestamp, with: sharedFormatter)
    }

    /// Test seam: format against an explicit locale/time zone so 12h/24h
    /// assertions stay deterministic regardless of host device settings.
    static func shortTime(
        forUnixTimestamp timestamp: Double?,
        locale: Locale,
        timeZone: TimeZone
    ) -> String? {
        format(timestamp, with: makeFormatter(locale: locale, timeZone: timeZone))
    }

    private static func makeFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private static func format(_ timestamp: Double?, with formatter: DateFormatter) -> String? {
        guard let timestamp, timestamp.isFinite else { return nil }
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
