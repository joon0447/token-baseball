import Foundation

public enum TokenDisplay {
    public static func short(_ tokens: Int64) -> String {
        let count = max(0, tokens)
        let units: [(Int64, String)] = [(1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")]
        guard let (divisor, suffix) = units.first(where: { count >= $0.0 }) else { return String(count) }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.roundingMode = .down
        let amount = NSDecimalNumber(decimal: Decimal(count) / Decimal(divisor))
        return (formatter.string(from: amount) ?? String(count / divisor)) + suffix
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        var dayCalendar = Calendar(identifier: .gregorian)
        dayCalendar.timeZone = calendar.timeZone
        let parts = dayCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
