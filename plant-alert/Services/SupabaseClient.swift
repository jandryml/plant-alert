//
//  SupabaseClient.swift
//  plant-alert
//

import Foundation

struct SupabaseCredentials: Equatable {
    /// Project root, e.g. https://abcdefgh.supabase.co
    var baseURL: URL
    var anonKey: String
    /// Shared secret that admits a phone to the household.
    var householdCode: String
}

enum SupabaseError: LocalizedError {
    case badResponse
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "The server sent something unexpected."
        case .http(let status, let message):
            // 401/404 are overwhelmingly the two setup mistakes, so name them.
            switch status {
            case 401, 403:
                return "Rejected by Supabase (\(status)). Check the anon key, and that you ran the setup SQL."
            case 404:
                return "Not found (404). Did you run the setup SQL?"
            case 422 where message.contains("anonymous"):
                return "Anonymous sign-ins are off. Turn them on under Authentication in Supabase."
            default:
                return message.isEmpty ? "Request failed (\(status))." : "Request failed (\(status)): \(message)"
            }
        }
    }
}

/// Minimal PostgREST client, acting as one signed-in user.
///
/// Hand-rolled on `URLSession` on purpose: the whole surface the app needs is
/// one RPC, two selects and two upserts, which is far less code than wiring
/// the official SDK into the project as a package dependency.
struct SupabaseClient {
    let credentials: SupabaseCredentials
    /// The user's token from `SupabaseAuth`; the row policies key off it.
    private let accessToken: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(credentials: SupabaseCredentials, accessToken: String, session: URLSession = .shared) {
        self.credentials = credentials
        self.accessToken = accessToken
        self.session = session
    }

    // MARK: Household

    /// Joins (or creates) the household for the code and returns its id.
    /// Harmless to repeat.
    func joinHousehold() async throws -> String {
        var request = URLRequest(url: credentials.baseURL.appending(path: "rest/v1/rpc/join_household"))
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try encoder.encode(["code": credentials.householdCode])

        let data = try await perform(request)
        return try decoder.decode(String.self, from: data)
    }

    // MARK: Reads

    func fetchPlants(householdID: String) async throws -> [PlantPayload] {
        try await fetch(table: "plants", householdID: householdID)
    }

    func fetchEvents(householdID: String) async throws -> [WateringEventPayload] {
        try await fetch(table: "watering_events", householdID: householdID)
    }

    /// Pulls the household's whole table.
    ///
    /// No incremental cursor: the server prunes history after 90 days (see
    /// `schema.sql`), so the row count stays small, and a full pull sidesteps every clock-skew
    /// bug an `updated_at > cursor` query would introduce.
    ///
    /// Newest first, so if the table ever outgrows Supabase's default 1000-row
    /// cap it is the oldest history that gets cut off, not the latest changes.
    private func fetch<T: Decodable>(table: String, householdID: String) async throws -> [T] {
        var components = URLComponents(
            url: credentials.baseURL.appending(path: "rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "household_id", value: "eq.\(householdID)"),
            URLQueryItem(name: "order", value: "updated_at.desc"),
            URLQueryItem(name: "limit", value: "1000")
        ]
        guard let url = components?.url else { throw SupabaseError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        request.timeoutInterval = 20

        let data = try await perform(request)
        return try decoder.decode([T].self, from: data)
    }

    // MARK: Writes

    func upsertPlants(_ payloads: [PlantPayload]) async throws {
        try await upsert(table: "plants", payloads: payloads)
    }

    func upsertEvents(_ payloads: [WateringEventPayload]) async throws {
        try await upsert(table: "watering_events", payloads: payloads)
    }

    /// Inserts or overwrites rows, keyed on the table's primary key.
    private func upsert<T: Encodable>(table: String, payloads: [T]) async throws {
        guard !payloads.isEmpty else { return }

        var request = URLRequest(url: credentials.baseURL.appending(path: "rest/v1/\(table)"))
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.timeoutInterval = 20
        request.httpBody = try encoder.encode(payloads)

        _ = try await perform(request)
    }

    // MARK: Storage

    /// Bucket the setup SQL creates. Private: reads go through the authenticated
    /// object endpoint, and the policy only admits the household's own folder.
    static let photoBucket = "plant-photos"

    /// Uploads (or replaces) a photo.
    func uploadImage(_ data: Data, to path: String) async throws {
        var request = URLRequest(url: storageURL(for: path))
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        // A retry after a half-finished upload would otherwise fail as a duplicate.
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        // Photos are far larger than a JSON row; the default 20s is tight on
        // a slow connection.
        request.timeoutInterval = 60

        _ = try await perform(request)
    }

    func downloadImage(at path: String) async throws -> Data {
        var request = URLRequest(url: storageURL(for: path))
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        request.timeoutInterval = 60

        return try await perform(request)
    }

    func deleteImage(at path: String) async throws {
        var request = URLRequest(url: storageURL(for: path))
        request.httpMethod = "DELETE"
        applyHeaders(to: &request)

        _ = try await perform(request)
    }

    private func storageURL(for path: String) -> URL {
        credentials.baseURL.appending(path: "storage/v1/object/\(Self.photoBucket)/\(path)")
    }

    // MARK: Plumbing

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue(credentials.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        try await Self.send(request, session: session)
    }

    /// Sends a request and turns any non-2xx answer into a `SupabaseError`.
    static func send(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.http(status: http.statusCode, message: message)
        }
        return data
    }
}
