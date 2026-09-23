//
//  plant_alertTests.swift
//  plant-alertTests
//

import Foundation
import UIKit
import Testing
@testable import plant_alert

@Suite("Watering schedule")
struct WateringScheduleTests {

    private func date(_ daysFromNow: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
    }

    @Test("A plant watered today is due after its interval")
    func nextWateringFollowsInterval() {
        let plant = Plant(intervalDays: 5, lastWateredAt: date(0))
        #expect(plant.daysUntilWatering() == 5)
        #expect(plant.status() == .upcoming(days: 5))
    }

    @Test("A never-watered plant is due immediately")
    func neverWateredIsDue() {
        let plant = Plant(lastWateredAt: nil, createdAt: date(0))
        #expect(plant.status().needsWater)
    }

    @Test("Overdue days are counted from the due date")
    func overdueCountsDays() {
        let plant = Plant(intervalDays: 3, lastWateredAt: date(-10))
        #expect(plant.status() == .overdue(days: 7))
        #expect(plant.status().needsWater)
    }

    @Test("Due today reads as due, not overdue")
    func dueTodayIsDue() {
        let plant = Plant(intervalDays: 7, lastWateredAt: date(-7))
        #expect(plant.status() == .dueToday)
        #expect(plant.status().needsWater)
    }

    @Test("isDue(on:) looks ahead to future digest days")
    func futureDaysSeeUpcomingPlants() {
        let plant = Plant(intervalDays: 4, lastWateredAt: date(0))
        #expect(plant.isDue(on: date(0)) == false)
        #expect(plant.isDue(on: date(3)) == false)
        // Due on day 4, so that morning's digest must include it.
        #expect(plant.isDue(on: date(4)))
        #expect(plant.isDue(on: date(9)))
    }

    @Test("Watering pushes the next date out and flags an upload")
    func wateringReschedules() {
        let plant = Plant(intervalDays: 7, lastWateredAt: date(-30), needsUpload: false)
        #expect(plant.status().needsWater)

        plant.markWatered()

        #expect(plant.status() == .upcoming(days: 7))
        #expect(plant.needsUpload)
    }

    @Test("An interval of zero can't collapse the schedule")
    func zeroIntervalIsClamped() {
        let plant = Plant(intervalDays: 0, lastWateredAt: date(0))
        #expect(plant.daysUntilWatering() == 1)
    }
}

@Suite("Postgres timestamps")
struct PostgresTimestampTests {

    @Test("Microsecond precision from Postgres parses")
    func parsesMicroseconds() throws {
        let parsed = try #require(PostgresTimestamp.date(from: "2026-09-23T18:04:05.123456+00:00"))
        let expected = try #require(PostgresTimestamp.date(from: "2026-09-23T18:04:05.123Z"))
        #expect(abs(parsed.timeIntervalSince(expected)) < 0.001)
    }

    @Test("Timestamps without a fractional part parse")
    func parsesWholeSeconds() {
        #expect(PostgresTimestamp.date(from: "2026-09-23T18:04:05+00:00") != nil)
        #expect(PostgresTimestamp.date(from: "2026-09-23T18:04:05Z") != nil)
    }

    @Test("Short fractions are padded rather than rejected")
    func parsesShortFraction() throws {
        let parsed = try #require(PostgresTimestamp.date(from: "2026-09-23T18:04:05.1Z"))
        let whole = try #require(PostgresTimestamp.date(from: "2026-09-23T18:04:05Z"))
        #expect(abs(parsed.timeIntervalSince(whole) - 0.1) < 0.001)
    }

    @Test("Round-tripping a date preserves it")
    func roundTrips() throws {
        let original = Date(timeIntervalSince1970: 1_790_000_000.25)
        let parsed = try #require(PostgresTimestamp.date(from: PostgresTimestamp.string(from: original)))
        #expect(abs(parsed.timeIntervalSince(original)) < 0.001)
    }

    @Test("Nonsense is rejected instead of silently becoming a date")
    func rejectsGarbage() {
        #expect(PostgresTimestamp.date(from: "") == nil)
        #expect(PostgresTimestamp.date(from: "not a date") == nil)
    }
}

@Suite("Sync payloads")
struct SyncPayloadTests {

    @Test("A plant survives a round trip through the wire format")
    func plantRoundTrips() throws {
        let original = Plant(
            name: "Monstera",
            species: "Monstera deliciosa",
            room: "Living room",
            notes: "Bright, indirect light",
            symbolName: "camera.macro",
            colorName: "mint",
            intervalDays: 9,
            amountMl: 400,
            lastWateredAt: Date(timeIntervalSince1970: 1_780_000_000)
        )

        let payload = PlantPayload(plant: original, householdID: "our-flat")
        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PlantPayload.self, from: encoded)

        let copy = Plant(id: original.id)
        decoded.apply(to: copy)

        #expect(copy.name == original.name)
        #expect(copy.species == original.species)
        #expect(copy.room == original.room)
        #expect(copy.notes == original.notes)
        #expect(copy.symbolName == original.symbolName)
        #expect(copy.colorName == original.colorName)
        #expect(copy.intervalDays == original.intervalDays)
        #expect(copy.amountMl == original.amountMl)
        #expect(abs((copy.lastWateredAt ?? .distantPast).timeIntervalSince(original.lastWateredAt!)) < 0.001)
        // Applying a server row must not mark it for re-upload, or sync loops.
        #expect(copy.needsUpload == false)
    }

    @Test("A soft delete travels to the other phone")
    func removalRoundTrips() {
        let plant = Plant(name: "Gone", isRemoved: true)
        let payload = PlantPayload(plant: plant, householdID: "our-flat")
        #expect(payload.is_removed)
    }

    @Test("A watering event survives a round trip")
    func eventRoundTrips() throws {
        let plantID = UUID()
        let original = WateringEvent(
            plantID: plantID,
            wateredAt: Date(timeIntervalSince1970: 1_780_000_500),
            amountMl: 250,
            personName: "Honza"
        )

        let payload = WateringEventPayload(event: original, householdID: "our-flat")
        let decoded = try JSONDecoder().decode(
            WateringEventPayload.self,
            from: JSONEncoder().encode(payload)
        )

        let copy = WateringEvent(id: original.id, plantID: UUID())
        decoded.apply(to: copy)

        #expect(copy.plantID == plantID)
        #expect(copy.amountMl == 250)
        #expect(copy.personName == "Honza")
        #expect(abs(copy.wateredAt.timeIntervalSince(original.wateredAt)) < 0.001)
        #expect(copy.needsUpload == false)
    }
}

@Suite("Settings")
struct AppSettingsTests {

    private func makeSettings() throws -> AppSettings {
        let suite = "tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return AppSettings(defaults: defaults)
    }

    @Test("Sync stays off until every field is filled in")
    func credentialsRequireEverything() throws {
        let settings = try makeSettings()
        #expect(settings.isSyncConfigured == false)

        settings.supabaseURL = "https://example.supabase.co"
        #expect(settings.isSyncConfigured == false)

        settings.supabaseAnonKey = "anon-key"
        #expect(settings.isSyncConfigured == false)

        settings.householdID = "our-flat"
        #expect(settings.isSyncConfigured)
    }

    @Test("A malformed project URL doesn't count as configured")
    func rejectsBadURL() throws {
        let settings = try makeSettings()
        settings.supabaseAnonKey = "anon-key"
        settings.householdID = "our-flat"

        settings.supabaseURL = "not a url"
        #expect(settings.isSyncConfigured == false)

        settings.supabaseURL = "  https://example.supabase.co  "
        #expect(settings.isSyncConfigured)
    }

    @Test("The default digest time is 9am, not midnight")
    func defaultDigestTime() throws {
        let settings = try makeSettings()
        #expect(settings.digestHour == 9)
        #expect(settings.digestMinute == 0)
        #expect(settings.remindersEnabled)
    }
}


@Suite("Plant photos")
struct PlantPhotoTests {

    /// A real JPEG of a given pixel size, so downscaling is exercised for real.
    private func makeJPEG(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemBrown.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        }
        return image.jpegData(compressionQuality: 1)!
    }

    @Test("A large photo is downscaled to the long-edge cap")
    func downscalesLargePhoto() throws {
        let original = makeJPEG(width: 3000, height: 2000)
        let prepared = try #require(PlantImage.prepared(from: original))
        let image = try #require(UIImage(data: prepared))

        #expect(max(image.size.width, image.size.height) <= PlantImage.maxDimension)
        // Aspect ratio must survive.
        #expect(abs(image.size.width / image.size.height - 1.5) < 0.01)
        #expect(prepared.count < original.count)
    }

    @Test("A small photo isn't upscaled")
    func leavesSmallPhotoAlone() throws {
        let original = makeJPEG(width: 300, height: 200)
        let prepared = try #require(PlantImage.prepared(from: original))
        let image = try #require(UIImage(data: prepared))

        #expect(image.size.width == 300)
        #expect(image.size.height == 200)
    }

    @Test("Data that isn't an image is rejected")
    func rejectsNonImage() {
        #expect(PlantImage.prepared(from: Data("not an image".utf8)) == nil)
    }

    @Test("Each photo gets its own storage path")
    func storagePathsAreUnique() {
        let id = UUID()
        let first = PlantImage.storagePath(plantID: id, householdID: "our flat")
        let second = PlantImage.storagePath(plantID: id, householdID: "our flat")

        #expect(first != second, "a replacement must not reuse the old path")
        // The household segment has to be URL-path safe.
        #expect(!first.contains(" "))
        #expect(first.hasSuffix(".jpg"))
        #expect(first.contains(id.uuidString))
    }

    @Test("The image path travels in the payload")
    func pathRoundTrips() throws {
        let plant = Plant(name: "Fern", imagePath: "house/abc.jpg")
        let payload = PlantPayload(plant: plant, householdID: "house")
        let decoded = try JSONDecoder().decode(PlantPayload.self, from: JSONEncoder().encode(payload))

        #expect(decoded.image_path == "house/abc.jpg")
    }

    @Test("A changed remote path drops the local bytes so they get re-fetched")
    func newRemotePathClearsCachedBytes() throws {
        let local = Plant(name: "Fern", imagePath: "house/old.jpg", imageData: Data([0x01, 0x02]))

        var payload = PlantPayload(plant: local, householdID: "house")
        payload.image_path = "house/new.jpg"
        payload.updated_at = PostgresTimestamp.string(from: Date())
        payload.apply(to: local)

        #expect(local.imagePath == "house/new.jpg")
        #expect(local.imageData == nil, "stale bytes must be dropped so the sync downloads the new photo")
    }

    @Test("An unchanged path keeps the photo rather than re-downloading it")
    func samePathKeepsCachedBytes() throws {
        let local = Plant(name: "Fern", imagePath: "house/same.jpg", imageData: Data([0x01, 0x02]))

        let payload = PlantPayload(plant: local, householdID: "house")
        payload.apply(to: local)

        #expect(local.imagePath == "house/same.jpg")
        #expect(local.imageData != nil)
    }

    @Test("Picking a photo flags an upload and orphans the old object")
    func pickingPhotoQueuesUploadAndCleanup() {
        let plant = Plant(name: "Fern", imagePath: "house/old.jpg", imageData: Data([0x09]))

        var draft = PlantDraft(plant: plant)
        draft.imageData = Data([0x0A, 0x0B])
        draft.photoChanged = true
        draft.apply(to: plant, householdID: "house")

        #expect(plant.photoNeedsUpload)
        #expect(plant.imagePath != "house/old.jpg", "a replacement needs a fresh path")
        #expect(plant.orphanedImagePath == "house/old.jpg", "the old object should be queued for deletion")
    }

    @Test("Removing a photo clears it and queues the old object for deletion")
    func removingPhotoClearsEverything() {
        let plant = Plant(name: "Fern", imagePath: "house/old.jpg", imageData: Data([0x09]))

        var draft = PlantDraft(plant: plant)
        draft.imageData = nil
        draft.photoChanged = true
        draft.apply(to: plant, householdID: "house")

        #expect(plant.imagePath == nil)
        #expect(plant.imageData == nil)
        #expect(plant.photoNeedsUpload == false)
        #expect(plant.orphanedImagePath == "house/old.jpg")
    }

    @Test("Editing other fields leaves an untouched photo alone")
    func untouchedPhotoSurvivesAnEdit() {
        let plant = Plant(name: "Fern", imagePath: "house/keep.jpg", imageData: Data([0x09]))

        var draft = PlantDraft(plant: plant)
        draft.name = "Fern renamed"
        draft.apply(to: plant, householdID: "house")

        #expect(plant.name == "Fern renamed")
        #expect(plant.imagePath == "house/keep.jpg")
        #expect(plant.imageData != nil)
        #expect(plant.photoNeedsUpload == false, "an untouched photo must not be re-uploaded")
        #expect(plant.orphanedImagePath == nil)
    }
}
