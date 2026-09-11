import Foundation

public enum TokenFormatter {
    public static func compact(_ value: Int64) -> String {
        let amount = Double(value)
        let magnitude = abs(amount)
        if magnitude >= 1_000_000_000 { return formatted(amount / 1_000_000_000, suffix: "B") }
        if magnitude >= 1_000_000 { return formatted(amount / 1_000_000, suffix: "M") }
        if magnitude >= 1_000 { return formatted(amount / 1_000, suffix: "K") }
        return String(value)
    }

    private static func formatted(_ value: Double, suffix: String) -> String {
        let magnitude = abs(value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = magnitude >= 100 ? 0 : (magnitude >= 10 ? 1 : 2)
        let number = formatter.string(from: NSNumber(value: value)) ?? String(value)
        return "\(number)\(suffix)"
    }
}
