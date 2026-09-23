//
//  ContentView.swift
//  plant-alert
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(SyncEngine.self) private var syncEngine

    /// Soft-deleted plants are filtered out here rather than everywhere downstream.
    @Query(filter: #Predicate<Plant> { !$0.isRemoved })
    private var plants: [Plant]

    @State private var selectedPlant: Plant?
    @State private var isCreatingPlant = false
    @State private var isShowingSettings = false
    @State private var waterFeedback = 0

    var body: some View {
        NavigationStack {
            Group {
                if plants.isEmpty {
                    emptyState
                } else {
                    plantList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plants")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: startNewPlant) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add plant")
                }
            }
            .navigationDestination(item: $selectedPlant) { plant in
                PlantDetailView(plant: plant)
            }
            .sheet(isPresented: $isCreatingPlant) {
                PlantEditorView(mode: .create)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .refreshable {
                await syncEngine.sync(context: modelContext)
            }
        }
        .sensoryFeedback(.success, trigger: waterFeedback)
        .task {
            #if DEBUG
            plant_alertApp.seedUITestDataIfRequested(in: modelContext)
            #endif
            // Reminders are the whole point of the app, so ask up front.
            if await NotificationManager.shared.authorizationStatus() == .notDetermined {
                _ = await NotificationManager.shared.requestAuthorization()
            }
            // Keep reminders honest even if the app was killed for a fortnight.
            await syncEngine.refreshReminders(context: modelContext)
            await syncEngine.sync(context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await NotificationManager.shared.clearBadge()
                await syncEngine.sync(context: modelContext)
            }
        }
    }

    // MARK: - List

    private var plantList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !thirsty.isEmpty {
                    section(title: "Needs water", plants: thirsty)
                }
                if !upcoming.isEmpty {
                    section(title: "Coming up", plants: upcoming)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func section(title: String, plants: [Plant]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(plants.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .padding(.leading, 4)

            ForEach(plants) { plant in
                PlantCard(
                    plant: plant,
                    onOpen: { selectedPlant = plant },
                    onWater: { water(plant) }
                )
                .contextMenu {
                    Button("Open", systemImage: "arrow.up.forward.square") { selectedPlant = plant }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(plant)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No plants yet", systemImage: "leaf")
        } description: {
            Text("Add your first plant and we'll remind you when it needs water.")
        } actions: {
            Button("Add a plant", action: startNewPlant)
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Ordering

    /// Overdue and due-today, most urgent first.
    private var thirsty: [Plant] {
        plants
            .filter { $0.status().needsWater }
            .sorted { $0.nextWateringDate < $1.nextWateringDate }
    }

    private var upcoming: [Plant] {
        plants
            .filter { !$0.status().needsWater }
            .sorted { $0.nextWateringDate < $1.nextWateringDate }
    }

    // MARK: - Actions

    private func startNewPlant() {
        isCreatingPlant = true
    }

    private func water(_ plant: Plant) {
        withAnimation(.snappy) {
            PlantActions.water(plant, context: modelContext, settings: settings)
        }
        waterFeedback += 1
        Task {
            await syncEngine.refreshReminders(context: modelContext)
            await syncEngine.sync(context: modelContext)
        }
    }

    private func delete(_ plant: Plant) {
        withAnimation(.snappy) {
            PlantActions.remove(plant, context: modelContext)
        }
        Task {
            await syncEngine.refreshReminders(context: modelContext)
            await syncEngine.sync(context: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .environment(SyncEngine())
        .modelContainer(for: [Plant.self, WateringEvent.self], inMemory: true)
}
