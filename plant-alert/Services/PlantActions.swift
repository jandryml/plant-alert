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
        logWatering(of: plant, at: date, context: context, settings: settings)
        try? context.save()
    }

    /// Adds a history entry without touching the schedule.
    ///
    /// The editor sets the date itself but still logs it here, so every
    /// watering, tapped or typed in, is something undo can reach.
    static func logWatering(
        of plant: Plant,
        at date: Date,
        context: ModelContext,
        settings: AppSettings = .shared
    ) {
        context.insert(
            WateringEvent(
                plantID: plant.id,
                wateredAt: date,
                amountMl: plant.amountMl,
                personName: settings.personName
            )
        )
    }

    /// Undoes an accidental tap by discarding the most recent watering.
    static func undoLastWatering(_ plant: Plant, context: ModelContext) {
        guard let latest = wateringEvents(of: plant, context: context).first else { return }
        removeWatering(latest, of: plant, context: context)
    }

    /// Discards one watering, the latest or any older one from the history.
    ///
    /// The schedule only moves when the latest one goes; it then falls back to
    /// the watering before it, so it stays truthful.
    static func removeWatering(_ event: WateringEvent, of plant: Plant, context: ModelContext) {
        let events = wateringEvents(of: plant, context: context)
        let wasLatest = events.first?.id == event.id

        event.isRemoved = true
        event.updatedAt = Date()
        event.needsUpload = true

        if wasLatest {
            plant.lastWateredAt = events.dropFirst().first?.wateredAt
            plant.touch()
        }
        try? context.save()
    }

    /// A plant's waterings, newest first.
    static func wateringEvents(of plant: Plant, context: ModelContext) -> [WateringEvent] {
        let plantID = plant.id
        let descriptor = FetchDescriptor<WateringEvent>(
            predicate: #Predicate { $0.plantID == plantID && !$0.isRemoved },
            sortBy: [SortDescriptor(\.wateredAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Soft delete, so the removal reaches the other phone instead of being
    /// undone by the next pull.
    ///
    /// Nothing shows a deleted plant's photo again, so it is queued for
    /// deletion from Storage like a replaced one. Clearing the path also tells
    /// the other phone to drop its copy.
    static func remove(_ plant: Plant, context: ModelContext) {
        plant.isRemoved = true
        if let path = plant.imagePath {
            plant.orphanedImagePath = path
        }
        plant.imagePath = nil
        plant.imageData = nil
        plant.photoNeedsUpload = false
        plant.touch()
        try? context.save()
    }
}
