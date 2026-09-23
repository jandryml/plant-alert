//
//  Plant.swift
//  plant-alert
//

import Foundation
import SwiftData

/// A house plant and its watering schedule.
///
/// Every field that the server also stores is mirrored here so the app works
/// completely offline; `updatedAt` / `needsUpload` / `isRemoved` drive the
/// last-write-wins sync in `SyncEngine`.
@Model
final class Plant {
    /// Stable identity shared with the `plants` row on the server.
    var id: UUID = UUID()

    var name: String = ""
    var species: String = ""
    var room: String = ""
    var notes: String = ""

    /// SF Symbol shown in the plant's avatar.
    var symbolName: String = PlantAppearance.defaultSymbol
    /// Key into `PlantAppearance.palette`.
    var colorName: String = PlantAppearance.defaultColor

    /// Days between waterings.
    var intervalDays: Int = 7
    /// Millilitres of water per watering.
    var amountMl: Int = 250

    var lastWateredAt: Date?
    var createdAt: Date = Date()

    /// Last local or remote modification; the tie-breaker when both people edit.
    var updatedAt: Date = Date()
    /// Set when this device changed the plant and the server hasn't been told yet.
    var needsUpload: Bool = true
    /// Soft delete, so a deletion propagates instead of being resurrected by a pull.
    var isRemoved: Bool = false

    init(
        id: UUID = UUID(),
        name: String = "",
        species: String = "",
        room: String = "",
        notes: String = "",
        symbolName: String = PlantAppearance.defaultSymbol,
        colorName: String = PlantAppearance.defaultColor,
        intervalDays: Int = 7,
        amountMl: Int = 250,
        lastWateredAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        needsUpload: Bool = true,
        isRemoved: Bool = false
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.room = room
        self.notes = notes
        self.symbolName = symbolName
        self.colorName = colorName
        self.intervalDays = intervalDays
        self.amountMl = amountMl
        self.lastWateredAt = lastWateredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.needsUpload = needsUpload
        self.isRemoved = isRemoved
    }
}

// MARK: - Schedule

extension Plant {
    /// When this plant should next be watered.
    ///
    /// A plant that has never been watered is due immediately, which is what you
    /// want right after adding it.
    var nextWateringDate: Date {
        guard let lastWateredAt else { return createdAt }
        return Calendar.current.date(byAdding: .day, value: max(1, intervalDays), to: lastWateredAt) ?? lastWateredAt
    }

    /// Whole days until watering: negative when overdue, 0 when due today.
    func daysUntilWatering(now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: nextWateringDate)
        return calendar.dateComponents([.day], from: today, to: due).day ?? 0
    }

    func status(now: Date = Date()) -> WateringStatus {
        let days = daysUntilWatering(now: now)
        if days < 0 { return .overdue(days: -days) }
        if days == 0 { return .dueToday }
        return .upcoming(days: days)
    }

    /// True when the plant wants water on or before the end of `day`.
    func isDue(on day: Date) -> Bool {
        let calendar = Calendar.current
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else {
            return false
        }
        return nextWateringDate < endOfDay
    }

    /// Records a watering and marks the plant for upload.
    func markWatered(at date: Date = Date()) {
        lastWateredAt = date
        touch()
    }

    /// Bumps the sync bookkeeping after any local edit.
    func touch(at date: Date = Date()) {
        updatedAt = date
        needsUpload = true
    }
}

enum WateringStatus: Equatable {
    case overdue(days: Int)
    case dueToday
    case upcoming(days: Int)

    var needsWater: Bool {
        switch self {
        case .overdue, .dueToday: return true
        case .upcoming: return false
        }
    }

    /// Short phrase for the list row, e.g. "2 days overdue".
    var shortText: String {
        switch self {
        case .overdue(let days):
            return days == 1 ? "1 day overdue" : "\(days) days overdue"
        case .dueToday:
            return "Due today"
        case .upcoming(let days):
            return days == 1 ? "Tomorrow" : "In \(days) days"
        }
    }
}
