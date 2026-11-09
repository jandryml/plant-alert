//
//  SettingsView.swift
//  plant-alert
//

import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(SyncEngine.self) private var syncEngine

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isConfirmingWipe = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $settings.personName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("You")
                } footer: {
                    Text("Shown in each plant's history so you can tell who watered what.")
                }

                Section {
                    Toggle("Daily reminder", isOn: $settings.remindersEnabled)
                    DatePicker("Time", selection: digestTime, displayedComponents: .hourAndMinute)
                        .disabled(!settings.remindersEnabled)
                    permissionRow
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("One notification each day listing every plant that needs water.")
                }

                Section {
                    LabeledContent("Status") {
                        Text(syncEngine.status.message)
                            .foregroundStyle(syncEngine.status.isError ? .red : .secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Project URL", text: $settings.supabaseURL, prompt: Text("https://xxxx.supabase.co"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Anon key", text: $settings.supabaseAnonKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        TextField("Household code", text: $settings.householdCode, prompt: Text("Household code"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if settings.householdCode.isEmpty {
                            Button("Generate") {
                                settings.householdCode = AppSettings.generateHouseholdCode()
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    Button {
                        Task { await syncEngine.sync(context: modelContext) }
                    } label: {
                        HStack {
                            Text("Sync now")
                            if syncEngine.isSyncing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!settings.isSyncConfigured || syncEngine.isSyncing)

                    NavigationLink("How to set up Supabase") {
                        SetupGuideView()
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("Both phones need the same three values. Generate the household code on one phone and type it on the other; it is the password to your plants, so it needs at least \(AppSettings.minimumCodeLength) characters.")
                }

                Section {
                    Button("Force full sync") {
                        Task { await syncEngine.forceSync(context: modelContext) }
                    }
                    .disabled(!settings.isSyncConfigured || syncEngine.isSyncing)

                    Button("Delete all local data", role: .destructive) {
                        isConfirmingWipe = true
                    }
                    // Deleting rows a running sync is still writing to would
                    // leave it saving objects that no longer exist.
                    .disabled(syncEngine.isSyncing)
                } header: {
                    Text("Troubleshooting")
                } footer: {
                    Text("Force full sync rejoins the household and re-uploads every plant, watering and photo on this phone. Deleting local data clears this phone only; anything already synced comes back on the next sync.")
                }
            }
            .confirmationDialog("Delete all plants on this phone?", isPresented: $isConfirmingWipe, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { wipeLocalData() }
            } message: {
                Text("Changes that haven't synced yet are lost. Your settings stay.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refreshAuthorization() }
            .onChange(of: settings.remindersEnabled) { _, _ in rescheduleReminders() }
            .onChange(of: settings.digestHour) { _, _ in rescheduleReminders() }
            .onChange(of: settings.digestMinute) { _, _ in rescheduleReminders() }
        }
    }

    // MARK: - Notifications

    @ViewBuilder
    private var permissionRow: some View {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            Button("Send a test notification") {
                Task { await NotificationManager.shared.sendTestNotification() }
            }
        case .denied:
            LabeledContent("Permission") {
                // Only Settings.app can undo a denial, so point there.
                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            }
        default:
            Button("Allow notifications") {
                Task {
                    _ = await NotificationManager.shared.requestAuthorization()
                    await refreshAuthorization()
                    rescheduleReminders()
                }
            }
        }
    }

    private func refreshAuthorization() async {
        authorizationStatus = await NotificationManager.shared.authorizationStatus()
    }

    private func wipeLocalData() {
        PlantActions.wipeLocalData(context: modelContext)
        // With no plants left this clears the pending digests.
        rescheduleReminders()
    }

    private func rescheduleReminders() {
        Task { await syncEngine.refreshReminders(context: modelContext) }
    }

    /// Bridges the stored hour/minute pair to the `DatePicker`'s `Date`.
    private var digestTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: settings.digestHour,
                minute: settings.digestMinute,
                second: 0,
                of: Date()
            ) ?? Date()
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            settings.digestHour = parts.hour ?? 9
            settings.digestMinute = parts.minute ?? 0
        }
    }
}

/// How to stand up the free Supabase backend.
///
/// The SQL itself lives in `supabase/schema.sql` in the repository rather than
/// here, so there is one copy to keep up to date.
struct SetupGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                step(1, "Create a free project at supabase.com. The free tier is enough for two people.")
                step(2, "In Authentication → Sign In / Providers, turn on \"Allow anonymous sign-ins\". Each phone signs in as its own user, without an email.")
                step(3, "Open the SQL Editor and run supabase/schema.sql from the app's repository.")
                step(4, "In Project Settings → API, copy the Project URL and the anon public key into this app's Settings.")
                step(5, "On one phone, tap Generate next to Household code. Type the same code on the other phone.")
                step(6, "Tap Sync now on each phone. That's it.")

                Text("The anon key alone can't read anything. Only phones that joined with your household code can see your plants and photos, so keep the code to yourselves.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Supabase Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .environment(SyncEngine())
        .modelContainer(for: [Plant.self, WateringEvent.self], inMemory: true)
}
