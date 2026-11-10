import Foundation

/// One check as the Healthchecks API reports it.
nonisolated struct Check: Decodable, Identifiable, Sendable {
    enum Status: String, Decodable, Sendable {
        case
        new, // Created, but no ping has arrived yet.
        started, // Sent a start ping and hasn't reported finishing yet.
        up, // Pinged on time.
        grace, // Its ping is overdue, but the grace time hasn't run out.
        down, // Missed its ping past the grace time, or reported a failure.
        paused // Not monitored until its next ping or a manual resume.
    }

    /// Read-only API keys report `uniqueKey` in its place.
    let uuid: String?
    let uniqueKey: String?
    let name: String
    let status: Status
    let lastPing: Date?
    let nextPing: Date?

    var id: String { uuid ?? uniqueKey ?? name }
    var detailsURL: URL? { uuid.map { URL(string: "https://healthchecks.io/checks/\($0)/details/")! } }
}

/// Reads one project's checks with that project's API key.
nonisolated struct HealthchecksAPI: Sendable {
    static let siteURL = URL(string: "https://healthchecks.io/")!

    private static let checksURL = URL(string: "https://healthchecks.io/api/v3/checks/")!

    private enum Failure: LocalizedError {
        case rejectedKey
        case status(Int)

        var errorDescription: String? {
            switch self {
            case .rejectedKey: "Healthchecks rejected the API key"
            case .status(let code): "Healthchecks answered HTTP \(code)"
            }
        }
    }

    private struct CheckList: Decodable {
        let checks: [Check]
    }

    private struct PingList: Decodable {
        let pings: [Ping]
    }

    private struct Ping: Decodable {
        let type: String
        let bodyUrl: URL?
    }

    let key: String

    func checks() async throws -> [Check] {
        try decode(CheckList.self, from: await get(Self.checksURL)).checks
    }

    /// Why a down check is down: its newest verdict ping, or nil under a read-only key, which can't read pings.
    func failureReason(of check: Check) async throws -> String? {
        guard let uuid = check.uuid else { return nil }
        let url = Self.checksURL.appending(path: "\(uuid)/pings/")
        let pings = try decode(PingList.self, from: await get(url)).pings
        guard let verdict = pings.first(where: { $0.type == "success" || $0.type == "fail" }), verdict.type == "fail" else {
            return "No ping arrived in time."
        }
        guard let bodyURL = verdict.bodyUrl else { return "Reported a failure without details." }
        return String(decoding: try await get(bodyURL), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 401: throw Failure.rejectedKey
        case let code: throw Failure.status(code)
        }
    }
}
