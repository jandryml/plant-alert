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
    /// Storage object path, or nil for a plant with no photo.
    var image_path: String?
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
        image_path = plant.imagePath
    }

    /// Spelled out so a nil goes over the wire as `null` rather than a missing
    /// key. PostgREST rejects a bulk upsert whose rows have different keys
    /// (PGRST102), and a missing key would also leave a cleared photo or
    /// watering date untouched on the server.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(household_id, forKey: .household_id)
        try container.encode(name, forKey: .name)
        try container.encode(species, forKey: .species)
        try container.encode(room, forKey: .room)
        try container.encode(notes, forKey: .notes)
        try container.encode(symbol_name, forKey: .symbol_name)
        try container.encode(color_name, forKey: .color_name)
        try container.encode(interval_days, forKey: .interval_days)
        try container.encode(amount_ml, forKey: .amount_ml)
        try container.encode(last_watered_at, forKey: .last_watered_at)
        try container.encode(created_at, forKey: .created_at)
        try container.encode(updated_at, forKey: .updated_at)
        try container.encode(is_removed, forKey: .is_removed)
        try container.encode(image_path, forKey: .image_path)
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
        // Dropping the bytes when the path changes is what makes the sync
        // notice a replaced photo: the download is driven by `imageData == nil`.
        if plant.imagePath != image_path {
            plant.imagePath = image_path
            plant.imageData = nil
        }
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
