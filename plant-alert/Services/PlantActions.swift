//
//  PlantActions.swift
//  plant-alert
//

import Foundation
import SwiftData

/// The handful of mutations that touch more than one model, kept in one place
/// so every entry point (list row, detail screen) behaves identically.
@MainActor
enum PlantActions {
    /// Marks a plant watered and records who did it.
    static func water(
        _ plant: Plant,
        context: ModelContext,
        settings: AppSettings = .shared,
        at date: Date = Date()
    ) {
        plant.markWatered(at: date)
        context.insert(
            WateringEvent(
                plantID: plant.id,
                wateredAt: date,
                amountMl: plant.amountMl,
                personName: settings.personName
            )
        )
        try? context.save()
    }

    /// Undoes an accidental tap by discarding the most recent watering.
    static func undoLastWatering(_ plant: Plant, context: ModelContext) {
        let plantID = plant.id
        let descriptor = FetchDescriptor<WateringEvent>(
            predicate: #Predicate { $0.plantID == plantID && !$0.isRemoved },
            sortBy: [SortDescriptor(\.wateredAt, order: .reverse)]
        )
        let events = (try? context.fetch(descriptor)) ?? []
        guard let latest = events.first else { return }

        latest.isRemoved = true
        latest.updatedAt = Date()
        latest.needsUpload = true

        // Fall back to the watering before it, so the schedule stays truthful.
        plant.lastWateredAt = events.dropFirst().first?.wateredAt
        plant.touch()
        try? context.save()
    }

    /// Soft delete, so the removal reaches the other phone instead of being
    /// undone by the next pull.
    static func remove(_ plant: Plant, context: ModelContext) {
        plant.isRemoved = true
        plant.touch()
        try? context.save()
    }
}
