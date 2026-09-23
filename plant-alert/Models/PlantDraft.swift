//
//  PlantDraft.swift
//  plant-alert
//

import Foundation

/// Editable copy of a plant.
///
/// The editor works on this rather than the `@Model` directly: SwiftData
/// autosaves, so binding a form straight to a live model would make Cancel
/// meaningless.
struct PlantDraft {
    var name: String = ""
    var species: String = ""
    var room: String = ""
    var notes: String = ""
    var symbolName: String = PlantAppearance.defaultSymbol
    var colorName: String = PlantAppearance.defaultColor
    var intervalDays: Int = 7
    var amountMl: Int = 250
    var hasBeenWatered: Bool = false
    var lastWateredAt: Date = Date()

    init() {}

    init(plant: Plant) {
        name = plant.name
        species = plant.species
        room = plant.room
        notes = plant.notes
        symbolName = plant.symbolName
        colorName = plant.colorName
        intervalDays = plant.intervalDays
        amountMl = plant.amountMl
        hasBeenWatered = plant.lastWateredAt != nil
        lastWateredAt = plant.lastWateredAt ?? Date()
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmedName.isEmpty }

    /// Writes the draft onto a model and flags it for upload.
    func apply(to plant: Plant) {
        plant.name = trimmedName
        plant.species = species.trimmingCharacters(in: .whitespacesAndNewlines)
        plant.room = room.trimmingCharacters(in: .whitespacesAndNewlines)
        plant.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        plant.symbolName = symbolName
        plant.colorName = colorName
        plant.intervalDays = max(1, intervalDays)
        plant.amountMl = max(0, amountMl)
        plant.lastWateredAt = hasBeenWatered ? lastWateredAt : nil
        plant.touch()
    }
}
