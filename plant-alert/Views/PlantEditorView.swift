//
//  PlantEditorView.swift
//  plant-alert
//

import SwiftUI
import SwiftData

/// Add or edit a plant.
struct PlantEditorView: View {
    enum Mode {
        case create
        case edit(Plant)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var syncEngine

    private let mode: Mode
    @State private var draft: PlantDraft

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _draft = State(initialValue: PlantDraft())
        case .edit(let plant):
            _draft = State(initialValue: PlantDraft(plant: plant))
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    TextField("Species", text: $draft.species, prompt: Text("Species (optional)"))
                        .textInputAutocapitalization(.words)
                    TextField("Room", text: $draft.room, prompt: Text("Room (optional)"))
                        .textInputAutocapitalization(.words)
                }

                Section("Look") {
                    symbolPicker
                    colorPicker
                }

                Section {
                    Stepper(value: $draft.intervalDays, in: 1...120) {
                        LabeledContent("Water every") {
                            Text(draft.intervalDays == 1 ? "day" : "\(draft.intervalDays) days")
                        }
                    }
                    Stepper(value: $draft.amountMl, in: 0...3000, step: 50) {
                        LabeledContent("Amount") {
                            Text("\(draft.amountMl) ml")
                        }
                    }
                } header: {
                    Text("Watering")
                } footer: {
                    Text("The daily reminder lists every plant that's due.")
                }

                Section {
                    Toggle("Already watered", isOn: $draft.hasBeenWatered.animation(.snappy))
                    if draft.hasBeenWatered {
                        DatePicker(
                            "Last watered",
                            selection: $draft.lastWateredAt,
                            in: ...Date(),
                            displayedComponents: [.date]
                        )
                    }
                } footer: {
                    Text(scheduleFooter)
                }

                Section("Notes") {
                    TextField("Light, soil, quirks…", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(isEditing ? "Edit Plant" : "New Plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.isValid)
                }
            }
        }
    }

    // MARK: - Pickers

    private var symbolPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
            ForEach(PlantAppearance.symbols, id: \.self) { symbol in
                let isSelected = symbol == draft.symbolName
                Button {
                    withAnimation(.snappy(duration: 0.15)) { draft.symbolName = symbol }
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 18))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isSelected ? PlantAppearance.color(named: draft.colorName) : .secondary)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? PlantAppearance.color(named: draft.colorName).opacity(0.15) : Color(.tertiarySystemFill).opacity(0.5))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var colorPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 12) {
            ForEach(PlantAppearance.palette, id: \.name) { entry in
                let isSelected = entry.name == draft.colorName
                Button {
                    withAnimation(.snappy(duration: 0.15)) { draft.colorName = entry.name }
                } label: {
                    Circle()
                        .fill(entry.color.gradient)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle()
                                .strokeBorder(.primary.opacity(isSelected ? 0.6 : 0), lineWidth: 2)
                                .padding(-3)
                        }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }

    private var scheduleFooter: String {
        guard draft.hasBeenWatered else {
            return "Leave this off and the plant shows up as due straight away."
        }
        let next = Calendar.current.date(
            byAdding: .day,
            value: max(1, draft.intervalDays),
            to: draft.lastWateredAt
        ) ?? draft.lastWateredAt
        return "Next watering \(next.formatted(date: .abbreviated, time: .omitted))."
    }

    // MARK: - Save

    private func save() {
        switch mode {
        case .create:
            let plant = Plant()
            draft.apply(to: plant)
            modelContext.insert(plant)
        case .edit(let plant):
            draft.apply(to: plant)
        }
        try? modelContext.save()
        dismiss()

        Task {
            await syncEngine.refreshReminders(context: modelContext)
            await syncEngine.sync(context: modelContext)
        }
    }
}

#Preview {
    PlantEditorView(mode: .create)
        .environment(SyncEngine())
        .modelContainer(for: [Plant.self, WateringEvent.self], inMemory: true)
}
