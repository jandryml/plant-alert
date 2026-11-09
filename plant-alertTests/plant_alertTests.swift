//
//  plant_alertTests.swift
//  plant-alertTests
//

import Foundation
import UIKit
import SwiftData
import Testing
@testable import plant_alert

@Suite("Watering schedule")
struct WateringScheduleTests {

    private func date(_ daysFromNow: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
    }

    @Test("Status follows the interval", arguments: [
        (lastWatered: 0, expected: WateringStatus.upcoming(days: 5)),
        (lastWatered: -5, expected: .dueToday),
        (lastWatered: -12, expected: .overdue(days: 7))
    ])
    func statusFollowsInterval(lastWatered: Int, expected: WateringStatus) {
        let plant = Plant(intervalDays: 5, lastWateredAt: date(lastWatered))
        #expect(plant.status() == expected)
    }

    @Test("A never-watered plant is due immediately")
    func neverWateredIsDue() {
        let plant = Plant(lastWateredAt: nil, createdAt: date(0))
        #expect(plant.status().needsWater)
    }

    @Test("isDue(on:) looks ahead to future digest days")
    func futureDaysSeeUpcomingPlants() {
        let plant = Plant(intervalDays: 4, lastWateredAt: date(0))
        #expect(plant.isDue(on: date(3)) == false)
        // Due on day 4, so that morning's digest must include it.
        #expect(plant.isDue(on: date(4)))
    }
}

@Suite("Sync payloads")
struct SyncPayloadTests {

    @Test("Microsecond timestamps from Postgres parse")
    func parsesMicroseconds() throws {
        let parsed = try #require(PostgresTimestamp.date(from: "2026-09-23T18:04:05.123456+00:00"))
        let expected = try #require(PostgresTimestamp.date(from: "2026-09-23T18:04:05.123Z"))
        #expect(abs(parsed.timeIntervalSince(expected)) < 0.001)
    }

    @Test("A plant survives a round trip through the wire format")
    func plantRoundTrips() throws {
        let original = Plant(
            name: "Monstera",
            intervalDays: 9,
            amountMl: 400,
            lastWateredAt: Date(timeIntervalSince1970: 1_780_000_000),
            imagePath: "house/abc.jpg"
        )

        let payload = PlantPayload(plant: original, householdID: "our-flat")
        let decoded = try JSONDecoder().decode(PlantPayload.self, from: JSONEncoder().encode(payload))
        let copy = Plant(id: original.id)
        decoded.apply(to: copy)

        #expect(copy.name == original.name)
        #expect(copy.intervalDays == original.intervalDays)
        #expect(copy.amountMl == original.amountMl)
        #expect(copy.imagePath == original.imagePath)
        #expect(abs((copy.lastWateredAt ?? .distantPast).timeIntervalSince(original.lastWateredAt!)) < 0.001)
        // Applying a server row must not mark it for re-upload, or sync loops.
        #expect(copy.needsUpload == false)
    }

    @Test("Empty fields are sent as null, so every row in a batch has the same keys")
    func nilFieldsEncodeAsNull() throws {
        let payload = PlantPayload(plant: Plant(name: "Fern"), householdID: "house")
        let json = try #require(String(data: JSONEncoder().encode(payload), encoding: .utf8))
        #expect(json.contains("\"image_path\":null"))
        #expect(json.contains("\"last_watered_at\":null"))
    }

    @Test("A watering event survives a round trip")
    func eventRoundTrips() throws {
        let plantID = UUID()
        let original = WateringEvent(plantID: plantID, amountMl: 250, personName: "Honza")

        let payload = WateringEventPayload(event: original, householdID: "our-flat")
        let decoded = try JSONDecoder().decode(WateringEventPayload.self, from: JSONEncoder().encode(payload))
        let copy = WateringEvent(id: original.id, plantID: UUID())
        decoded.apply(to: copy)

        #expect(copy.plantID == plantID)
        #expect(copy.personName == "Honza")
        #expect(copy.needsUpload == false)
    }

    @Test("Sync stays off until the URL is valid and the code is long enough")
    func credentialsRequireEverything() throws {
        let settings = AppSettings(defaults: try #require(UserDefaults(suiteName: "tests-\(UUID().uuidString)")))
        settings.supabaseAnonKey = "anon-key"
        settings.supabaseURL = "  https://example.supabase.co  "
        settings.householdCode = "our-flat"
        #expect(settings.isSyncConfigured == false, "a short code is guessable")

        settings.householdCode = AppSettings.generateHouseholdCode()
        #expect(settings.isSyncConfigured)

        settings.supabaseURL = "not a url"
        #expect(settings.isSyncConfigured == false)
    }
}

@Suite("Plant photos")
struct PlantPhotoTests {

    @Test("A large photo is downscaled to the long-edge cap")
    func downscalesLargePhoto() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: format)
            .image { ctx in
                UIColor.systemGreen.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
            }
            .jpegData(compressionQuality: 1)!

        let image = try #require(PlantImage.prepared(from: original).flatMap(UIImage.init(data:)))

        #expect(max(image.size.width, image.size.height) <= PlantImage.maxDimension)
        #expect(abs(image.size.width / image.size.height - 1.5) < 0.01)
    }

    @Test("A changed remote path drops the local bytes so they get re-fetched")
    func newRemotePathClearsCachedBytes() {
        let local = Plant(name: "Fern", imagePath: "house/old.jpg", imageData: Data([0x01]))

        var payload = PlantPayload(plant: local, householdID: "house")
        payload.image_path = "house/new.jpg"
        payload.apply(to: local)

        #expect(local.imagePath == "house/new.jpg")
        #expect(local.imageData == nil)
    }

    @Test("Replacing a photo uploads it under a fresh path and orphans the old one")
    func replacingPhotoQueuesUploadAndCleanup() {
        let plant = Plant(name: "Fern", imagePath: "house/old.jpg", imageData: Data([0x09]))

        var draft = PlantDraft(plant: plant)
        draft.imageData = Data([0x0A])
        draft.photoChanged = true
        draft.apply(to: plant, householdID: "house")

        #expect(plant.photoNeedsUpload)
        #expect(plant.imagePath != "house/old.jpg")
        #expect(plant.orphanedImagePath == "house/old.jpg")
    }
}

@Suite("Plant actions")
@MainActor
struct PlantActionTests {

    private let container = try! ModelContainer(
        for: Plant.self, WateringEvent.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    private var context: ModelContext { container.mainContext }

    @Test("Removing the latest watering falls back to the one before; older ones leave the schedule alone")
    func removeWateringKeepsScheduleTruthful() {
        let plant = Plant(name: "Fern")
        context.insert(plant)
        let earlier = Date(timeIntervalSince1970: 1_780_000_000)
        let later = earlier.addingTimeInterval(86_400)
        PlantActions.water(plant, context: context, at: earlier)
        PlantActions.water(plant, context: context, at: later)

        let older = PlantActions.wateringEvents(of: plant, context: context).last!
        PlantActions.removeWatering(older, of: plant, context: context)
        #expect(plant.lastWateredAt == later)

        PlantActions.undoLastWatering(plant, context: context)
        #expect(plant.lastWateredAt == nil)
        #expect(PlantActions.wateringEvents(of: plant, context: context).isEmpty)
    }

    @Test("Deleting a plant queues its photo for removal from Storage")
    func removingPlantOrphansPhoto() {
        let plant = Plant(name: "Fern", imagePath: "house/fern.jpg", imageData: Data([0x01]))
        context.insert(plant)

        PlantActions.remove(plant, context: context)

        #expect(plant.isRemoved)
        #expect(plant.imagePath == nil)
        #expect(plant.orphanedImagePath == "house/fern.jpg")
    }
}
