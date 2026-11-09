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

    /// Local watering history and deleted plants older than this are removed,
    /// matching the server's nightly job in `schema.sql`.
    static let retentionDays = 90

    private(set) var status: Status = .idle
    private let settings: AppSettings
    /// Set when a sync is asked for while one is running, so the change that
    /// prompted it goes out straight after instead of waiting for a later one.
    private var isResyncRequested = false
    private var lastPrunedAt: Date?

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
        guard !isSyncing else {
            isResyncRequested = true
            return
        }

        status = .syncing

        do {
            let session = try await SupabaseAuth.session(for: credentials)
            let client = SupabaseClient(credentials: credentials, accessToken: session.accessToken)
            let householdID = try await household(client: client, session: session, context: context)

            try await push(client: client, householdID: householdID, context: context)
            try await pull(client: client, householdID: householdID, context: context)
            pruneLocalHistoryIfDue(context: context)
            // Photos move after the rows, so a row always exists before the
            // object it points at is fetched.
            await syncPhotos(client: client, context: context)
            try context.save()

            let now = Date()
            settings.lastSyncAt = now
            status = .succeeded(now)

            await refreshReminders(context: context)
        } catch {
            status = .failed(error.localizedDescription)
        }

        if isResyncRequested {
            isResyncRequested = false
            await sync(context: context)
        }
    }

    /// Reschedules the digest from whatever is currently in the local store.
    func refreshReminders(context: ModelContext) async {
        let plants = (try? context.fetch(FetchDescriptor<Plant>())) ?? []
        await NotificationManager.shared.reschedule(plants: plants, settings: settings)
    }

    // MARK: - Household

    /// The household this phone's user belongs to, joining it first if needed.
    ///
    /// Joining happens once per user and code; a new code, or a new user after
    /// a lost session, joins again with the stored code.
    private func household(client: SupabaseClient, session: SupabaseSession, context: ModelContext) async throws -> String {
        if settings.memberUserID == session.userID, !settings.householdID.isEmpty {
            return settings.householdID
        }

        let householdID = try await client.joinHousehold()
        if householdID != settings.householdID {
            try rehome(to: householdID, context: context)
        }
        settings.householdID = householdID
        settings.memberUserID = session.userID
        return householdID
    }

    /// Prepares everything on this phone for a household the server may have
    /// none of it in: the first join, or a switch to a new code.
    ///
    /// Every row is queued for upload, and photos move into the new household's
    /// Storage folder, the only one its members can reach. The filename is
    /// kept, so both phones moving the same photo agree on where it goes.
    private func rehome(to householdID: String, context: ModelContext) throws {
        for plant in try context.fetch(FetchDescriptor<Plant>()) {
            plant.needsUpload = true
            guard let path = plant.imagePath else { continue }
            let moved = PlantImage.path(path, inHousehold: householdID)
            guard moved != path else { continue }
            if plant.imageData != nil {
                plant.imagePath = moved
                plant.photoNeedsUpload = true
            } else {
                // Never downloaded, and the old folder is out of reach now.
                plant.imagePath = nil
            }
        }
        for event in try context.fetch(FetchDescriptor<WateringEvent>()) {
            event.needsUpload = true
        }
    }

    // MARK: - Upload

    private func push(client: SupabaseClient, householdID: String, context: ModelContext) async throws {
        let plantsToSend = try context.fetch(
            FetchDescriptor<Plant>(predicate: #Predicate { $0.needsUpload })
        )
        if !plantsToSend.isEmpty {
            // An edit made while the request is in flight bumps `updatedAt`;
            // only rows still matching what was sent are done.
            let sentStamps = plantsToSend.map(\.updatedAt)
            try await client.upsertPlants(plantsToSend.map { PlantPayload(plant: $0, householdID: householdID) })
            for (plant, stamp) in zip(plantsToSend, sentStamps) where plant.updatedAt == stamp {
                plant.needsUpload = false
            }
        }

        let eventsToSend = try context.fetch(
            FetchDescriptor<WateringEvent>(predicate: #Predicate { $0.needsUpload })
        )
        if !eventsToSend.isEmpty {
            let sentStamps = eventsToSend.map(\.updatedAt)
            try await client.upsertEvents(eventsToSend.map { WateringEventPayload(event: $0, householdID: householdID) })
            for (event, stamp) in zip(eventsToSend, sentStamps) where event.updatedAt == stamp {
                event.needsUpload = false
            }
        }
    }

    // MARK: - Retention

    /// Drops local rows older than `retentionDays`, at most once a day.
    ///
    /// The server prunes itself; this keeps the phone's copy in step. A row
    /// pruned here before the server's nightly run may come back on a pull,
    /// and simply goes again the next day.
    private func pruneLocalHistoryIfDue(context: ModelContext) {
        let now = Date()
        if let lastPrunedAt, now.timeIntervalSince(lastPrunedAt) < 24 * 60 * 60 { return }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: now) else { return }

        let oldEvents = (try? context.fetch(
            FetchDescriptor<WateringEvent>(predicate: #Predicate { $0.wateredAt < cutoff })
        )) ?? []
        let oldTombstones = (try? context.fetch(
            FetchDescriptor<Plant>(predicate: #Predicate { $0.isRemoved && $0.updatedAt < cutoff })
        )) ?? []
        for event in oldEvents { context.delete(event) }
        for plant in oldTombstones { context.delete(plant) }

        lastPrunedAt = now
    }

    // MARK: - Photos

    /// Moves photo bytes in both directions.
    ///
    /// Deliberately non-throwing: a photo that won't upload or download is a
    /// missing picture, not a reason to fail the whole sync and leave the
    /// watering data stale. Failed work keeps its flag and retries next time.
    private func syncPhotos(client: SupabaseClient, context: ModelContext) async {
        let plants = (try? context.fetch(FetchDescriptor<Plant>())) ?? []

        for plant in plants {
            // Clean up the object a replaced photo left behind. An object that
            // is already gone 404s; either way there's no point retrying it.
            if let orphan = plant.orphanedImagePath {
                try? await client.deleteImage(at: orphan)
                plant.orphanedImagePath = nil
            }

            if plant.photoNeedsUpload, let data = plant.imageData, let path = plant.imagePath {
                do {
                    try await client.uploadImage(data, to: path)
                    plant.photoNeedsUpload = false
                } catch {
                    continue
                }
            }

            // `apply(to:)` clears the bytes whenever the remote path differs,
            // so a nil here means "this phone hasn't got this photo yet".
            if let path = plant.imagePath, plant.imageData == nil, !plant.photoNeedsUpload {
                if let data = try? await client.downloadImage(at: path) {
                    plant.imageData = data
                }
            }
        }
    }

    // MARK: - Download

    private func pull(client: SupabaseClient, householdID: String, context: ModelContext) async throws {
        let remotePlants = try await client.fetchPlants(householdID: householdID)
        let remoteEvents = try await client.fetchEvents(householdID: householdID)

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
