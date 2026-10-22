import Foundation

// MARK: - YouTubeDateFormatter

/// Absolute publish dates for YouTube videos. Dates are calendar days, not moments:
/// they are kept as noon UTC and formatted in UTC so the day never shifts with the
/// viewer's time zone.
enum YouTubeDateFormatter {
    private static let utc: TimeZone = .gmt

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        return calendar
    }

    private static let months = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    private static let watchPageDate = try? NSRegularExpression(
        pattern: #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.? (\d{1,2}), (\d{4})\b"#
    )

    // MARK: Parsing

    /// The day in `"2026-10-31"` or `"2026-10-31T09:00:00-07:00"`, ignoring any time part.
    static func date(fromISODay string: String) -> Date? {
        let parts = string.prefix(10).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        return self.date(year: year, month: month, day: day)
    }

    /// The date in the watch page's own text: `"Oct 31, 2026"`, `"Premiered Oct 31, 2026"`,
    /// `"Streamed live on Oct 31, 2026"`. `nil` for relative text like "3 days ago".
    static func date(fromWatchPageText text: String) -> Date? {
        guard let watchPageDate,
              let match = watchPageDate.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let monthRange = Range(match.range(at: 1), in: text),
              let dayRange = Range(match.range(at: 2), in: text),
              let yearRange = Range(match.range(at: 3), in: text),
              let month = months[text[monthRange].lowercased()],
              let day = Int(text[dayRange]),
              let year = Int(text[yearRange])
        else { return nil }
        return self.date(year: year, month: month, day: day)
    }

    /// The publish day from a `player` response's microformat.
    static func publishDate(fromPlayerResponse response: [String: Any]) -> Date? {
        let renderer = (response["microformat"] as? [String: Any])?["playerMicroformatRenderer"] as? [String: Any]
        let raw = (renderer?["publishDate"] as? String) ?? (renderer?["uploadDate"] as? String)
        return raw.flatMap { self.date(fromISODay: $0) }
    }

    private static func date(year: Int, month: Int, day: Int) -> Date? {
        guard (1 ... 12).contains(month), (1 ... 31).contains(day), (1990 ... 2200).contains(year) else { return nil }
        return self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    // MARK: Formatting

    /// "October 31st, 2026" in English; the locale's long date elsewhere.
    static func absoluteString(from date: Date, locale: Locale = .current) -> String {
        guard locale.language.languageCode?.identifier == "en" else {
            return date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: self.utc))
        }
        let components = self.calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        let monthName = DateFormatter().monthSymbols[month - 1]
        return "\(monthName) \(day)\(Self.ordinalSuffix(for: day)), \(year)"
    }

    static func ordinalSuffix(for day: Int) -> String {
        if (11 ... 13).contains(day % 100) {
            return "th"
        }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
