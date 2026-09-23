//
//  PlantDetailView.swift
//  plant-alert
//

import SwiftUI
import SwiftData

/// Everything about one plant, plus its watering history.
struct PlantDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(SyncEngine.self) private var syncEngine

    let plant: Plant

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var waterFeedback = 0

    private var tint: Color { PlantAppearance.color(named: plant.colorName) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                stats
                if !plant.notes.isEmpty { notes }
                history
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(plant.name.isEmpty ? "Plant" : plant.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    Button("Undo last watering", systemImage: "arrow.uturn.backward") { undoWatering() }
                        .disabled(plant.lastWateredAt == nil)
                    Button("Delete plant", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            PlantEditorView(mode: .edit(plant))
        }
        .confirmationDialog("Delete this plant?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("It will disappear on both phones.")
        }
        .sensoryFeedback(.success, trigger: waterFeedback)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            PlantAvatar(symbolName: plant.symbolName, colorName: plant.colorName, size: 88)

            VStack(spacing: 6) {
                Text(plant.name.isEmpty ? "Unnamed plant" : plant.name)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                StatusBadge(status: plant.status())
            }

            Button {
                water()
            } label: {
                Label("Water now", systemImage: "drop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(tint.gradient, in: .rect(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private var stats: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            StatTile(label: "Every", value: plant.intervalDays == 1 ? "1 day" : "\(plant.intervalDays) days", symbol: "calendar")
            StatTile(label: "Amount", value: "\(plant.amountMl) ml", symbol: "drop")
            StatTile(
                label: "Last watered",
                value: plant.lastWateredAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Never",
                symbol: "clock.arrow.circlepath"
            )
            StatTile(
                label: "Next watering",
                value: plant.nextWateringDate.formatted(date: .abbreviated, time: .omitted),
                symbol: "bell"
            )
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(plant.notes)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            WateringHistoryList(plantID: plant.id, tint: tint)
        }
    }

    // MARK: - Helpers

    private var subtitle: String {
        [plant.room, plant.species]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Actions

    private func water() {
        withAnimation(.snappy) {
            PlantActions.water(plant, context: modelContext, settings: settings)
        }
        waterFeedback += 1
        syncAndReschedule()
    }

    private func undoWatering() {
        withAnimation(.snappy) {
            PlantActions.undoLastWatering(plant, context: modelContext)
        }
        syncAndReschedule()
    }

    private func delete() {
        PlantActions.remove(plant, context: modelContext)
        dismiss()
        syncAndReschedule()
    }

    private func syncAndReschedule() {
        Task {
            await syncEngine.refreshReminders(context: modelContext)
            await syncEngine.sync(context: modelContext)
        }
    }
}

/// Small labelled value box used in the detail grid.
private struct StatTile: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

/// Watering history for one plant.
///
/// A `@Query` rather than a fetch in `body`, so new waterings and rows arriving
/// from a sync both appear without the view having to be told.
private struct WateringHistoryList: View {
    let tint: Color

    @Query private var events: [WateringEvent]

    init(plantID: UUID, tint: Color) {
        self.tint = tint
        _events = Query(
            filter: #Predicate<WateringEvent> { $0.plantID == plantID && !$0.isRemoved },
            sort: \WateringEvent.wateredAt,
            order: .reverse
        )
    }

    var body: some View {
        if events.isEmpty {
            Text("Not watered yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(events.prefix(50).enumerated()), id: \.element.id) { index, event in
                    HStack {
                        Image(systemName: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(tint)
                        Text(event.wateredAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                        Spacer()
                        Text(detail(for: event))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)

                    if index < min(events.count, 50) - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        }
    }

    private func detail(for event: WateringEvent) -> String {
        let amount = event.amountMl > 0 ? "\(event.amountMl) ml" : ""
        let person = event.personName.trimmingCharacters(in: .whitespaces)
        return [amount, person].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
