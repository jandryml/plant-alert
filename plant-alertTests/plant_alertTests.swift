//
//  plant_alertTests.swift
//  plant-alertTests
//

import Foundation
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
