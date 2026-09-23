//
//  PlantEditorView.swift
//  plant-alert
//

import SwiftUI
import SwiftData
import PhotosUI

/// Add or edit a plant.
struct PlantEditorView: View {
    enum Mode {
        case create
        case edit(Plant)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(AppSettings.self) private var settings

    private let mode: Mode
    @State private var draft: PlantDraft
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false

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

                Section {
                    photoRow
                } header: {
                    Text("Photo")
                } footer: {
                    Text("Optional. Shown instead of the symbol, and shared with the other phone.")
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

    // MARK: - Photo

    @ViewBuilder
    private var photoRow: some View {
        HStack(spacing: 14) {
            PlantAvatar(
                symbolName: draft.symbolName,
                colorName: draft.colorName,
                imageData: draft.imageData,
                // Not the storage path: within the editor the bytes change
                // while the path does not, and a stale cache entry would pin
                // the old picture on screen.
                imageKey: nil,
                size: 64
            )

            VStack(alignment: .leading, spacing: 6) {
                PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                    Text(draft.imageData == nil ? "Choose photo" : "Replace photo")
                }
                if draft.imageData != nil {
                    Button("Remove photo", role: .destructive) {
                        withAnimation(.snappy) {
                            draft.imageData = nil
                            draft.photoChanged = true
                            pickedPhoto = nil
                        }
                    }
                    .font(.subheadline)
                }
            }

            Spacer(minLength: 0)

            if isLoadingPhoto { ProgressView() }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            loadPhoto(from: item)
        }
    }

    /// Pulls the picked image out of the photo library and downscales it before
    /// it ever reaches the model.
    private func loadPhoto(from item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            let raw = try? await item.loadTransferable(type: Data.self)
            let prepared = raw.flatMap(PlantImage.prepared(from:))
            await MainActor.run {
                if let prepared {
                    draft.imageData = prepared
                    draft.photoChanged = true
                }
                isLoadingPhoto = false
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
            draft.apply(to: plant, householdID: settings.householdID)
            modelContext.insert(plant)
        case .edit(let plant):
            draft.apply(to: plant, householdID: settings.householdID)
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
        .environment(AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .modelContainer(for: [Plant.self, WateringEvent.self], inMemory: true)
}
