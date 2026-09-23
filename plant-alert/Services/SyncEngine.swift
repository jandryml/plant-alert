//
//  SyncEngine.swift
//  plant-alert
//

import Foundation
import Observation
import SwiftData

/// Two-way sync between the local SwiftData store and Supabase.
///
/// The local store is always the thing the UI reads, so the app stays fully
/// usable with no network and no Supabase project at all. Conflicts resolve
/// last-write-wins on `updatedAt`, which is the right trade for two people who
/// rarely edit the same plant in the same minute.
@MainActor
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case idle
        case notConfigured
        case syncing
        case succeeded(Date)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
        status = settings.isSyncConfigured ? .idle : .notConfigured
    }

    var isSyncing: Bool { status == .syncing }

    /// Pushes local edits, pulls everything back, then refreshes reminders.
    ///
    /// Never throws: sync failures are a status the Settings screen shows, not
    /// something the UI should have to handle mid-gesture.
    func sync(context: ModelContext) async {
        guard let credentials = settings.credentials else {
            status = .notConfigured
            return
        }
        guard !isSyncing else { return }

        status = .syncing
        let client = SupabaseClient(credentials: credentials)

        do {
            try await push(client: client, householdID: credentials.householdID, context: context)
            try await pull(client: client, context: context)
            try context.save()

            let now = Date()
            settings.lastSyncAt = now
            status = .succeeded(now)

            await refreshReminders(context: context)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Reschedules the digest from whatever is currently in the local store.
    func refreshReminders(context: ModelContext) async {
        let plants = (try? context.fetch(FetchDescriptor<Plant>())) ?? []
        await NotificationManager.shared.reschedule(plants: plants, settings: settings)
    }

    // MARK: - Upload

    private func push(client: SupabaseClient, householdID: String, context: ModelContext) async throws {
        let plantsToSend = try context.fetch(
            FetchDescriptor<Plant>(predicate: #Predicate { $0.needsUpload })
        )
        if !plantsToSend.isEmpty {
            try await client.upsertPlants(plantsToSend.map { PlantPayload(plant: $0, householdID: householdID) })
            for plant in plantsToSend { plant.needsUpload = false }
        }

        let eventsToSend = try context.fetch(
            FetchDescriptor<WateringEvent>(predicate: #Predicate { $0.needsUpload })
        )
        if !eventsToSend.isEmpty {
            try await client.upsertEvents(eventsToSend.map { WateringEventPayload(event: $0, householdID: householdID) })
            for event in eventsToSend { event.needsUpload = false }
        }
    }

    // MARK: - Download

    private func pull(client: SupabaseClient, context: ModelContext) async throws {
        let remotePlants = try await client.fetchPlants()
        let remoteEvents = try await client.fetchEvents()

        var plantsByID: [UUID: Plant] = [:]
        for plant in try context.fetch(FetchDescriptor<Plant>()) {
            plantsByID[plant.id] = plant
        }
        for payload in remotePlants {
            guard let id = payload.identifier else { continue }
            if let local = plantsByID[id] {
                // Anything we just pushed comes back with an identical stamp, so
                // `>` leaves our own writes alone.
                if payload.updatedAt > local.updatedAt {
                    payload.apply(to: local)
                }
            } else {
                let plant = Plant(id: id)
                payload.apply(to: plant)
                context.insert(plant)
                plantsByID[id] = plant
            }
        }

        var eventsByID: [UUID: WateringEvent] = [:]
        for event in try context.fetch(FetchDescriptor<WateringEvent>()) {
            eventsByID[event.id] = event
        }
        for payload in remoteEvents {
            guard let id = payload.identifier, let plantID = payload.plantIdentifier else { continue }
            if let local = eventsByID[id] {
                if payload.updatedAt > local.updatedAt {
                    payload.apply(to: local)
                }
            } else {
                let event = WateringEvent(id: id, plantID: plantID)
                payload.apply(to: event)
                context.insert(event)
                eventsByID[id] = event
            }
        }
    }
}

extension SyncEngine.Status {
    var isError: Bool {
        if case .failed = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .idle: return "Ready"
        case .notConfigured: return "Not set up"
        case .syncing: return "Syncing…"
        case .succeeded(let date): return "Synced \(date.formatted(date: .omitted, time: .shortened))"
        case .failed(let reason): return reason
        }
    }
}
