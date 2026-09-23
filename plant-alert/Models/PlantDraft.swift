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

    /// Downscaled JPEG bytes, already through `PlantImage.prepared`.
    var imageData: Data?
    /// The path the bytes came from, so an untouched photo isn't re-uploaded.
    var imagePath: String?
    /// True once the photo is picked or cleared in this editing session.
    var photoChanged: Bool = false

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
        imageData = plant.imageData
        imagePath = plant.imagePath
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmedName.isEmpty }

    /// Writes the draft onto a model and flags it for upload.
    func apply(to plant: Plant, householdID: String) {
        plant.name = trimmedName
        plant.species = species.trimmingCharacters(in: .whitespacesAndNewlines)
        plant.room = room.trimmingCharacters(in: .whitespacesAndNewlines)
        plant.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        plant.symbolName = symbolName
        plant.colorName = colorName
        plant.intervalDays = max(1, intervalDays)
        plant.amountMl = max(0, amountMl)
        plant.lastWateredAt = hasBeenWatered ? lastWateredAt : nil
        applyPhoto(to: plant, householdID: householdID)
        plant.touch()
    }

    /// Writes a picked or cleared photo onto the model.
    ///
    /// A fresh storage path per photo is what lets the other phone tell a
    /// replacement from the picture it already has; the path being replaced is
    /// remembered so the sync can delete the object it leaves behind.
    private func applyPhoto(to plant: Plant, householdID: String) {
        guard photoChanged else { return }

        let previousPath = plant.imagePath
        if let imageData {
            plant.imageData = imageData
            plant.imagePath = PlantImage.storagePath(plantID: plant.id, householdID: householdID)
            plant.photoNeedsUpload = true
        } else {
            plant.imageData = nil
            plant.imagePath = nil
            plant.photoNeedsUpload = false
        }

        if let previousPath, previousPath != plant.imagePath {
            plant.orphanedImagePath = previousPath
        }
    }
}
