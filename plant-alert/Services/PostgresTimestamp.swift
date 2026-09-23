//
//  PostgresTimestamp.swift
//  plant-alert
//

import Foundation

/// Timestamps are carried as strings rather than decoded via a Codable date
/// strategy: Postgres emits microsecond precision, which `ISO8601DateFormatter`
/// refuses, so every conversion goes through the lenient helpers below.
enum PostgresTimestamp {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        fractional.string(from: date)
    }

    static func date(from raw: String) -> Date? {
        let normalized = normalizingFraction(raw)
        return fractional.date(from: normalized) ?? plain.date(from: normalized)
    }

    /// Rewrites the fractional-seconds run to exactly three digits, which is the
    /// only width `ISO8601DateFormatter` accepts.
    private static func normalizingFraction(_ raw: String) -> String {
        guard let dot = raw.firstIndex(of: ".") else { return raw }
        let afterDot = raw.index(after: dot)
        let digits = raw[afterDot...].prefix { $0.isNumber }
        guard !digits.isEmpty else { return raw }
        let padded = digits.count >= 3
            ? String(digits.prefix(3))
            : digits + String(repeating: "0", count: 3 - digits.count)
        let tail = raw[raw.index(afterDot, offsetBy: digits.count)...]
        return raw[..<dot] + "." + padded + tail
    }
}
