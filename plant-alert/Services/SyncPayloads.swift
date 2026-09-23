//
//  SyncPayloads.swift
//  plant-alert
//

import Foundation

// MARK: - Wire format

/// Mirrors a row of the `plants` table.
struct PlantPayload: Codable {
    var id: String
    var household_id: String
    var name: String
    var species: String
    var room: String
    var notes: String
    var symbol_name: String
    var color_name: String
    var interval_days: Int
    var amount_ml: Int
    var last_watered_at: String?
    var created_at: String
    var updated_at: String
    var is_removed: Bool
}

/// Mirrors a row of the `watering_events` table.
struct WateringEventPayload: Codable {
    var id: String
    var household_id: String
    var plant_id: String
    var watered_at: String
    var amount_ml: Int
    var person_name: String
    var note: String
    var created_at: String
    var updated_at: String
    var is_removed: Bool
}

// MARK: - Model bridging

extension PlantPayload {
    init(plant: Plant, householdID: String) {
        id = plant.id.uuidString
        household_id = householdID
        name = plant.name
        species = plant.species
        room = plant.room
        notes = plant.notes
        symbol_name = plant.symbolName
        color_name = plant.colorName
        interval_days = plant.intervalDays
        amount_ml = plant.amountMl
        last_watered_at = plant.lastWateredAt.map(PostgresTimestamp.string(from:))
        created_at = PostgresTimestamp.string(from: plant.createdAt)
        updated_at = PostgresTimestamp.string(from: plant.updatedAt)
        is_removed = plant.isRemoved
    }

    var identifier: UUID? { UUID(uuidString: id) }
    var updatedAt: Date { PostgresTimestamp.date(from: updated_at) ?? .distantPast }
    var createdAt: Date { PostgresTimestamp.date(from: created_at) ?? Date() }
    var lastWateredAt: Date? { last_watered_at.flatMap(PostgresTimestamp.date(from:)) }

    /// Copies every server-owned field onto a local plant.
    func apply(to plant: Plant) {
        plant.name = name
        plant.species = species
        plant.room = room
        plant.notes = notes
        plant.symbolName = symbol_name
        plant.colorName = color_name
        plant.intervalDays = interval_days
        plant.amountMl = amount_ml
        plant.lastWateredAt = lastWateredAt
        plant.createdAt = createdAt
        plant.updatedAt = updatedAt
        plant.isRemoved = is_removed
        plant.needsUpload = false
    }
}

extension WateringEventPayload {
    init(event: WateringEvent, householdID: String) {
        id = event.id.uuidString
        household_id = householdID
        plant_id = event.plantID.uuidString
        watered_at = PostgresTimestamp.string(from: event.wateredAt)
        amount_ml = event.amountMl
        person_name = event.personName
        note = event.note
        created_at = PostgresTimestamp.string(from: event.createdAt)
        updated_at = PostgresTimestamp.string(from: event.updatedAt)
        is_removed = event.isRemoved
    }

    var identifier: UUID? { UUID(uuidString: id) }
    var plantIdentifier: UUID? { UUID(uuidString: plant_id) }
    var updatedAt: Date { PostgresTimestamp.date(from: updated_at) ?? .distantPast }

    func apply(to event: WateringEvent) {
        if let plantIdentifier { event.plantID = plantIdentifier }
        event.wateredAt = PostgresTimestamp.date(from: watered_at) ?? event.wateredAt
        event.amountMl = amount_ml
        event.personName = person_name
        event.note = note
        event.createdAt = PostgresTimestamp.date(from: created_at) ?? event.createdAt
        event.updatedAt = updatedAt
        event.isRemoved = is_removed
        event.needsUpload = false
    }
}
