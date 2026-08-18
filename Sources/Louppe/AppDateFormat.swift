import Foundation

/// Single source of truth for how dates and times are displayed anywhere in
/// the app: the info panel, selection summaries, filter day lists, and group
/// headers.
///
/// Formatting follows the Mac's settings (System Settings > General >
/// Language & Region / Date & Time), including the user's custom "Date
/// format" picker. That picker stores a per-style override
/// (`AppleICUDateFormatStrings`) which only style-based formatters honor —
/// `setLocalizedDateFormatFromTemplate` silently ignores it and falls back
/// to the region default — so the formatters below must be configured via
/// `dateStyle`/`timeStyle`, never via templates or explicit patterns. If an
/// in-app date format setting ever lands, only this file needs to change:
/// no call site should ever build its own display DateFormatter.
enum AppDateFormat {
    /// e.g. "2026.07.11"
    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// e.g. "2026.07.11, 2:32 PM" (12/24-hour clock per system setting)
    static func dayAndTime(_ date: Date) -> String {
        dayAndTimeFormatter.string(from: date)
    }

    /// e.g. "2023.03.28 – 2026.07.11". Composed from two `day` strings so
    /// both ends always render the full, identical pattern.
    static func dayRange(from start: Date, to end: Date) -> String {
        "\(day(start)) – \(day(end))"
    }

    /// Folder date labels for Source Organization. The full-date value uses
    /// `day(_:)` directly. These shorter granularities derive their order,
    /// field widths, and separator from that style formatter's effective
    /// pattern instead of imposing an app-specific yyyy-MM convention.
    static func yearAndMonth(_ date: Date) -> String {
        yearAndMonthFormatter.string(from: date)
    }

    static func year(_ date: Date) -> String {
        yearFormatter.string(from: date)
    }

    /// Built once per launch; a mid-session change to the Mac's region
    /// settings needs a relaunch. Deliberately NOT the POSIX locale used for
    /// EXIF parsing: display formatting should follow the user's system,
    /// fixed-format parsing must not. The short styles are what the System
    /// Settings pickers customize.
    private static func makeFormatter(
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter
    }

    private static let dayFormatter = makeFormatter(dateStyle: .short, timeStyle: .none)
    private static let dayAndTimeFormatter = makeFormatter(dateStyle: .short, timeStyle: .short)

    private static let yearAndMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = dayFormatter.calendar
        formatter.timeZone = dayFormatter.timeZone
        formatter.dateFormat = yearAndMonthPattern(
            from: dayFormatter.dateFormat
                ?? DateFormatter.dateFormat(
                    fromTemplate: "yMd",
                    options: 0,
                    locale: .current
                )
                ?? "y-MM-dd"
        )
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = dayFormatter.calendar
        formatter.timeZone = dayFormatter.timeZone
        formatter.dateFormat = yearField(
            in: dayFormatter.dateFormat ?? "y"
        ) ?? "y"
        return formatter
    }()

    /// Only style-based DateFormatters honor macOS's custom Date format
    /// picker. Read that resolved pattern, then keep its year/month spelling
    /// and punctuation for the shorter folder label.
    private static func yearAndMonthPattern(from pattern: String) -> String {
        let fields = dateFields(in: pattern)
        guard let year = fields.first(where: { "yYuUr".contains($0.symbol) }),
              let month = fields.first(where: { "ML".contains($0.symbol) }) else {
            return "y-MM"
        }
        let ordered = [year, month].sorted {
            $0.range.lowerBound < $1.range.lowerBound
        }
        let separator = preferredDateSeparator(
            in: pattern,
            fields: fields,
            between: ordered[0],
            and: ordered[1]
        )
        return String(pattern[ordered[0].range])
            + separator
            + String(pattern[ordered[1].range])
    }

    private static func yearField(in pattern: String) -> String? {
        dateFields(in: pattern)
            .first(where: { "yYuUr".contains($0.symbol) })
            .map { String(pattern[$0.range]) }
    }

    private struct PatternField {
        let symbol: Character
        let range: Range<String.Index>
    }

    private static func dateFields(in pattern: String) -> [PatternField] {
        var result: [PatternField] = []
        var index = pattern.startIndex
        var quoted = false
        while index < pattern.endIndex {
            let character = pattern[index]
            if character == "'" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "'" {
                    index = pattern.index(after: next)
                    continue
                }
                quoted.toggle()
                index = next
                continue
            }
            guard !quoted, character.isLetter else {
                index = pattern.index(after: index)
                continue
            }
            let start = index
            index = pattern.index(after: index)
            while index < pattern.endIndex, pattern[index] == character {
                index = pattern.index(after: index)
            }
            result.append(PatternField(
                symbol: character,
                range: start..<index
            ))
        }
        return result
    }

    private static func preferredDateSeparator(
        in pattern: String,
        fields: [PatternField],
        between first: PatternField,
        and second: PatternField
    ) -> String {
        let ordered = fields.sorted {
            $0.range.lowerBound < $1.range.lowerBound
        }
        guard let firstIndex = ordered.firstIndex(where: {
                  $0.range == first.range
              }),
              let secondIndex = ordered.firstIndex(where: {
                  $0.range == second.range
              }) else { return "." }
        let lower = min(firstIndex, secondIndex)
        let upper = max(firstIndex, secondIndex)
        for index in lower..<upper {
            let left = ordered[index]
            let right = ordered[index + 1]
            let literal = String(
                pattern[left.range.upperBound..<right.range.lowerBound]
            )
            if !literal.isEmpty { return literal }
        }
        return "."
    }
}
