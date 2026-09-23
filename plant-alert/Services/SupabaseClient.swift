//
//  SupabaseClient.swift
//  plant-alert
//

import Foundation

struct SupabaseCredentials: Equatable {
    /// Project root, e.g. https://abcdefgh.supabase.co
    var baseURL: URL
    var anonKey: String
    var householdID: String
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
                return "Rejected by Supabase (\(status)). Check the anon key and the table policies."
            case 404:
                return "Table not found (404). Did you run the setup SQL?"
            default:
                return message.isEmpty ? "Request failed (\(status))." : "Request failed (\(status)): \(message)"
            }
        }
    }
}

/// Minimal PostgREST client.
///
/// Hand-rolled on `URLSession` on purpose: the whole surface the app needs is
/// two selects and two upserts, which is far less code than wiring the official
/// SDK into the project as a package dependency.
struct SupabaseClient {
    let credentials: SupabaseCredentials
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(credentials: SupabaseCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: Reads

    func fetchPlants() async throws -> [PlantPayload] {
        try await fetch(table: "plants")
    }

    func fetchEvents() async throws -> [WateringEventPayload] {
        try await fetch(table: "watering_events")
    }

    /// Pulls the household's whole table.
    ///
    /// No incremental cursor: for two people and a shelf of plants the row count
    /// is tiny, and a full pull sidesteps every clock-skew bug an
    /// `updated_at > cursor` query would introduce.
    private func fetch<T: Decodable>(table: String) async throws -> [T] {
        var components = URLComponents(
            url: credentials.baseURL.appending(path: "rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "household_id", value: "eq.\(credentials.householdID)"),
            URLQueryItem(name: "order", value: "updated_at.asc"),
            URLQueryItem(name: "limit", value: "2000")
        ]
        guard let url = components?.url else { throw SupabaseError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)

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
        request.httpBody = try encoder.encode(payloads)

        _ = try await perform(request)
    }

    // MARK: Plumbing

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue(credentials.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(credentials.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.http(status: http.statusCode, message: message)
        }
        return data
    }
}
