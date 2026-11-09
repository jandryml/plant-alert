//
//  AppSettings.swift
//  plant-alert
//

import Foundation
import Observation

/// User-owned configuration: where to sync, who you are, when to be nagged.
///
/// Kept in `UserDefaults` rather than baked into the binary so the Supabase
/// project can be pointed somewhere else without a rebuild.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let supabaseURL = "supabaseURL"
        static let supabaseAnonKey = "supabaseAnonKey"
        static let householdCode = "householdCode"
        /// The first version stored the code under this key.
        static let legacyHouseholdCode = "householdID"
        static let householdID = "joinedHouseholdID"
        static let memberUserID = "memberUserID"
        static let personName = "personName"
        static let digestHour = "digestHour"
        static let digestMinute = "digestMinute"
        static let remindersEnabled = "remindersEnabled"
        static let lastSyncAt = "lastSyncAt"
    }

    private let defaults: UserDefaults

    var supabaseURL: String { didSet { defaults.set(supabaseURL, forKey: Key.supabaseURL) } }
    var supabaseAnonKey: String { didSet { defaults.set(supabaseAnonKey, forKey: Key.supabaseAnonKey) } }

    /// Shared secret that admits a phone to the household. Both phones must match.
    var householdCode: String {
        didSet {
            defaults.set(householdCode, forKey: Key.householdCode)
            // A new code may mean a new household, so join again on next sync.
            memberUserID = ""
        }
    }

    /// Server id of the household this phone last joined, or empty before the
    /// first join. Also the Storage folder for the household's photos.
    var householdID: String { didSet { defaults.set(householdID, forKey: Key.householdID) } }

    /// The Supabase user that joined `householdID`. A different signed-in user
    /// (a lost session) has to join again.
    var memberUserID: String { didSet { defaults.set(memberUserID, forKey: Key.memberUserID) } }

    /// Shown in the watering history so you can tell who watered what.
    var personName: String { didSet { defaults.set(personName, forKey: Key.personName) } }

    var digestHour: Int { didSet { defaults.set(digestHour, forKey: Key.digestHour) } }
    var digestMinute: Int { didSet { defaults.set(digestMinute, forKey: Key.digestMinute) } }
    var remindersEnabled: Bool { didSet { defaults.set(remindersEnabled, forKey: Key.remindersEnabled) } }

    var lastSyncAt: Date? {
        didSet { defaults.set(lastSyncAt?.timeIntervalSince1970 ?? 0, forKey: Key.lastSyncAt) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        supabaseURL = defaults.string(forKey: Key.supabaseURL) ?? ""
        supabaseAnonKey = defaults.string(forKey: Key.supabaseAnonKey) ?? ""
        householdCode = defaults.string(forKey: Key.householdCode)
            ?? defaults.string(forKey: Key.legacyHouseholdCode)
            ?? ""
        householdID = defaults.string(forKey: Key.householdID) ?? ""
        memberUserID = defaults.string(forKey: Key.memberUserID) ?? ""
        personName = defaults.string(forKey: Key.personName) ?? ""
        // 9:00 is the default nag time; 0 would be indistinguishable from "unset".
        let hour = defaults.object(forKey: Key.digestHour) as? Int
        digestHour = hour ?? 9
        digestMinute = defaults.object(forKey: Key.digestMinute) as? Int ?? 0
        remindersEnabled = defaults.object(forKey: Key.remindersEnabled) as? Bool ?? true
        let stamp = defaults.double(forKey: Key.lastSyncAt)
        lastSyncAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// The time of day the digest fires, as calendar components.
    var digestTime: DateComponents {
        DateComponents(hour: digestHour, minute: digestMinute)
    }

    /// Everything the sync engine needs, or `nil` while setup is incomplete.
    var credentials: SupabaseCredentials? {
        let trimmedURL = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = householdCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, trimmedCode.count >= Self.minimumCodeLength,
              let url = URL(string: trimmedURL), url.scheme != nil, url.host != nil else {
            return nil
        }
        return SupabaseCredentials(baseURL: url, anonKey: trimmedKey, householdCode: trimmedCode)
    }

    var isSyncConfigured: Bool { credentials != nil }

    /// Matches the check in `join_household`: anyone who guesses the code can
    /// join, so it must not be guessable.
    static let minimumCodeLength = 12

    /// A fresh random code, e.g. `k7qm-x2hd-9fwz-p4tc`: about 80 bits, and no
    /// look-alike characters to mistype on the other phone.
    static func generateHouseholdCode() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        let groups = (0..<4).map { _ in
            String((0..<4).map { _ in alphabet.randomElement()! })
        }
        return groups.joined(separator: "-")
    }
}
