//
//  plant_alertApp.swift
//  plant-alert
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct plant_alertApp: App {
    @State private var settings = AppSettings.shared
    @State private var syncEngine = SyncEngine()

    private let modelContainer: ModelContainer

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared

        let schema = Schema([Plant.self, WateringEvent.self])
        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
            )
        } catch {
            // An unreadable store shouldn't be a crash loop: fall back to memory
            // so the app still opens and can re-sync from Supabase.
            assertionFailure("Falling back to an in-memory store: \(error)")
            modelContainer = try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(syncEngine)
        }
        .modelContainer(modelContainer)
    }
}
