//
//  WateringEvent.swift
//  plant-alert
//

import Foundation
import SwiftData

/// One watering, kept as history so both people can see who did what.
///
/// Deliberately not a SwiftData relationship: a plain `plantID` keeps the sync
/// payload flat and lets an event arrive before the plant it belongs to.
@Model
final class WateringEvent {
    var id: UUID = UUID()
    var plantID: UUID = UUID()
    var wateredAt: Date = Date()
    var amountMl: Int = 0
    /// Display name of whoever tapped Water, from Settings.
    var personName: String = ""
    var note: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var needsUpload: Bool = true
    var isRemoved: Bool = false

    init(
        id: UUID = UUID(),
        plantID: UUID,
        wateredAt: Date = Date(),
        amountMl: Int = 0,
        personName: String = "",
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        needsUpload: Bool = true,
        isRemoved: Bool = false
    ) {
        self.id = id
        self.plantID = plantID
        self.wateredAt = wateredAt
        self.amountMl = amountMl
        self.personName = personName
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.needsUpload = needsUpload
        self.isRemoved = isRemoved
    }
}
