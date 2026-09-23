//
//  plant_alertApp.swift
//  plant-alert
//

import SwiftUI
import SwiftData
import UserNotifications
import UIKit

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

    #if DEBUG
    /// Seeds one plant with a photo so the UI tests can exercise the photo
    /// viewer without driving the system photo picker.
    ///
    /// DEBUG-only and opt-in by launch argument, so it can never run for a real
    /// user on a release build.
    /// Called after launch, not from `init`: rendering an image during `init`
    /// initialises UIKit before the window adopts the accent colour from the
    /// asset catalog, which tints the whole app the system blue.
    static func seedUITestDataIfRequested(in context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedPhoto") else { return }

        for plant in (try? context.fetch(FetchDescriptor<Plant>())) ?? [] {
            context.delete(plant)
        }

        let size = CGSize(width: 800, height: 600)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.systemBrown.setFill()
            ctx.fill(CGRect(x: 0, y: 400, width: 800, height: 200))
        }

        let plant = Plant(name: "Photo Plant", room: "Studio", lastWateredAt: Date())
        plant.imageData = image.jpegData(compressionQuality: 0.8)
        plant.imagePath = "uitest/seeded.jpg"
        context.insert(plant)
        try? context.save()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(syncEngine)
        }
        .modelContainer(modelContainer)
    }
}
