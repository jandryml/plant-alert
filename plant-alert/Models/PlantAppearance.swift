//
//  PlantAppearance.swift
//  plant-alert
//

import SwiftUI

/// The symbol + colour vocabulary a plant can be given.
///
/// Storing names rather than colours or image data keeps a plant a handful of
/// bytes, so syncing stays trivial and instant.
enum PlantAppearance {
    static let defaultSymbol = "leaf.fill"
    static let defaultColor = "green"

    /// SF Symbols offered in the editor, loosely plant-shaped.
    static let symbols: [String] = [
        "leaf.fill",
        "camera.macro",
        "tree.fill",
        "laurel.leading",
        "fan.fill",
        "carrot.fill",
        "sparkles",
        "drop.fill",
        "sun.max.fill",
        "moon.stars.fill",
        "flame.fill",
        "star.fill"
    ]

    /// Ordered so the picker shows a pleasant spectrum.
    static let palette: [(name: String, color: Color)] = [
        ("green", Color(red: 0.31, green: 0.64, blue: 0.42)),
        ("mint", Color(red: 0.31, green: 0.73, blue: 0.65)),
        ("teal", Color(red: 0.25, green: 0.60, blue: 0.70)),
        ("blue", Color(red: 0.31, green: 0.52, blue: 0.80)),
        ("purple", Color(red: 0.56, green: 0.46, blue: 0.80)),
        ("pink", Color(red: 0.85, green: 0.46, blue: 0.62)),
        ("red", Color(red: 0.84, green: 0.39, blue: 0.38)),
        ("orange", Color(red: 0.89, green: 0.56, blue: 0.29)),
        ("yellow", Color(red: 0.85, green: 0.70, blue: 0.27)),
        ("brown", Color(red: 0.62, green: 0.50, blue: 0.38))
    ]

    static func color(named name: String) -> Color {
        palette.first { $0.name == name }?.color ?? palette[0].color
    }

    /// Falls back to a known-good symbol so a value synced from a newer build
    /// can never render an empty box.
    static func symbol(named name: String) -> String {
        symbols.contains(name) ? name : defaultSymbol
    }
}
