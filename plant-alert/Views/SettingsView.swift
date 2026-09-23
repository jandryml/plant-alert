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
                    TextField("Household code", text: $settings.householdID, prompt: Text("e.g. our-flat"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

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
                    Text("Both phones need the same three values. The household code is what keeps your plants separate from anyone else's.")
                }
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

/// Copy-pasteable instructions for standing up the free Supabase backend.
struct SetupGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                step(1, "Create a free project at supabase.com. The free tier is enough for two people.")
                step(2, "Open the SQL Editor and run the script below. It creates the two tables the app syncs.")

                Text(SetupGuideView.schemaSQL)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))

                step(3, "Already had the tables from an earlier version? Run: alter table plants add column if not exists image_path text; — plus the storage bucket lines above.")
                step(4, "In Project Settings → API, copy the Project URL and the anon public key into this app's Settings.")
                step(5, "Pick any household code you both agree on and enter the same one on both phones.")
                step(6, "Tap Sync now on each phone. That's it.")

                Text("The anon key is safe to put in the app, but anyone who has it plus your household code could read your plants. Pick a household code that isn't guessable.")
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

    static let schemaSQL = """
    create table if not exists plants (
      id uuid primary key,
      household_id text not null,
      name text not null default '',
      species text not null default '',
      room text not null default '',
      notes text not null default '',
      symbol_name text not null default 'leaf.fill',
      color_name text not null default 'green',
      interval_days int not null default 7,
      amount_ml int not null default 250,
      last_watered_at timestamptz,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      is_removed boolean not null default false,
      image_path text
    );

    create table if not exists watering_events (
      id uuid primary key,
      household_id text not null,
      plant_id uuid not null,
      watered_at timestamptz not null default now(),
      amount_ml int not null default 0,
      person_name text not null default '',
      note text not null default '',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      is_removed boolean not null default false
    );

    create index if not exists plants_household_idx
      on plants (household_id);
    create index if not exists watering_events_household_idx
      on watering_events (household_id);

    alter table plants enable row level security;
    alter table watering_events enable row level security;

    create policy "anon full access" on plants
      for all to anon using (true) with check (true);
    create policy "anon full access" on watering_events
      for all to anon using (true) with check (true);

    -- Photos live in Storage, not in the table, so the rows stay small enough
    -- for the app to pull them all on every sync.
    insert into storage.buckets (id, name, public)
      values ('plant-photos', 'plant-photos', false)
      on conflict (id) do nothing;

    create policy "anon full access photos" on storage.objects
      for all to anon
      using (bucket_id = 'plant-photos')
      with check (bucket_id = 'plant-photos');
    """
}

#Preview {
    SettingsView()
        .environment(AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .environment(SyncEngine())
        .modelContainer(for: [Plant.self, WateringEvent.self], inMemory: true)
}
