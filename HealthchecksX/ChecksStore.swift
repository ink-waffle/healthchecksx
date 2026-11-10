import AppKit
import Foundation
import Observation

/// One project as its reads left it: the checks last read, and why reading it fails, while it does.
struct ProjectReading: Identifiable {
    let project: Project
    /// Most urgent first.
    var checks: [Check] = []
    /// Why each down check is down, by check id.
    var failureReasons: [String: String] = [:]
    /// When the checks were last read successfully.
    var readAt: Date?
    /// Why the latest read failed, while it does.
    var readProblem: String?

    var id: Project.ID { project.id }
}

/// The watched projects and their checks as last read: read every minute, when the Mac wakes and when the panel opens.
@MainActor @Observable
final class ChecksStore {
    enum Health: Equatable {
        case
        down(count: Int), // How many checks are down, across all projects.
        late, // Nothing is down, but some check is in its grace time.
        ok, // Every project was read just now, with nothing down or late.
        unknown // Can't vouch for everything: no projects yet, or one can't be read.
    }

    private nonisolated struct DuplicateKey: LocalizedError {
        var errorDescription: String? { "That API key is already added." }
    }

    private static let pollInterval = Duration.seconds(60)
    private static let staleAfter: TimeInterval = 180

    /// One per project, in the order they were added.
    private(set) var readings = Project.saved().map { ProjectReading(project: $0) }
    /// When the most recently read project was read.
    private(set) var updatedAt: Date?
    private(set) var health = Health.unknown

    @ObservationIgnored private var observers: [Task<Void, Never>] = []
    @ObservationIgnored private var readTask: Task<Void, Never>?

    var projects: [Project] { readings.map(\.project) }

    func start() {
        guard observers.isEmpty else { return }
        observers = [
            Task {
                while !Task.isCancelled {
                    refresh()
                    try? await Task.sleep(for: Self.pollInterval)
                }
            },
            refreshes(on: NSWorkspace.didWakeNotification, from: NSWorkspace.shared.notificationCenter),
            // The panel has no open event of its own, but it becomes key when it opens.
            refreshes(on: NSWindow.didBecomeKeyNotification, from: .default),
        ]
    }

    func refresh() {
        guard readTask == nil else { return }
        restartReading()
    }

    /// Adds a project once Healthchecks has accepted its key.
    func add(name: String, apiKey: String) async throws {
        guard !projects.contains(where: { $0.apiKey == apiKey }) else { throw DuplicateKey() }
        _ = try await HealthchecksAPI(key: apiKey).checks()
        try save(projects + [Project(name: name, apiKey: apiKey)])
        restartReading()
    }

    func remove(_ project: Project) throws {
        try save(projects.filter { $0.id != project.id })
    }

    /// Swaps the project with the one above (-1) or below (+1); the panel lists projects in this order.
    func move(_ project: Project, by offset: Int) throws {
        var reorderedProjects = projects
        guard let index = reorderedProjects.firstIndex(where: { $0.id == project.id }),
              reorderedProjects.indices.contains(index + offset) else { return }
        reorderedProjects.swapAt(index, index + offset)
        try save(reorderedProjects)
    }

    private func save(_ updatedProjects: [Project]) throws {
        try Project.save(updatedProjects)
        readings = updatedProjects.map { project in readings.first { $0.id == project.id } ?? ProjectReading(project: project) }
        health = assess()
    }

    private func restartReading() {
        readTask?.cancel()
        readTask = Task {
            await read()
            if !Task.isCancelled { readTask = nil }
        }
    }

    private func refreshes(on name: Notification.Name, from center: NotificationCenter) -> Task<Void, Never> {
        Task {
            for await _ in center.notifications(named: name) {
                refresh()
            }
        }
    }

    private func read() async {
        var latestReadings: [ProjectReading] = []
        for var reading in readings {
            do {
                (reading.checks, reading.failureReasons) = try await fetch(reading)
                reading.readAt = .now
                reading.readProblem = nil
            } catch {
                reading.readProblem = error.localizedDescription
            }
            latestReadings.append(reading)
        }
        guard !Task.isCancelled else { return }
        // Projects may have been removed or reordered while reading, so the results only update the ones still listed.
        readings = readings.map { reading in latestReadings.first { $0.id == reading.id } ?? reading }
        updatedAt = readings.compactMap(\.readAt).max()
        health = assess()
    }

    /// The project's checks, most urgent first, and why each down one is down.
    private func fetch(_ reading: ProjectReading) async throws -> ([Check], [String: String]) {
        let api = HealthchecksAPI(key: reading.project.apiKey)
        let checks = try await api.checks().sorted { ($0.status.severity, $0.name) < ($1.status.severity, $1.name) }
        var failureReasons: [String: String] = [:]
        for check in checks where check.status == .down {
            failureReasons[check.id] = (try? await api.failureReason(of: check)) ?? reading.failureReasons[check.id]
        }
        return (checks, failureReasons)
    }

    /// A project that can't be read never hides trouble in the others, but it does rule out "all healthy".
    private func assess() -> Health {
        let fresh = readings.filter { $0.readAt.map { Date.now.timeIntervalSince($0) < Self.staleAfter } ?? false }
        let checks = fresh.flatMap(\.checks)
        let down = checks.count { $0.status == .down }
        if down > 0 { return .down(count: down) }
        if checks.contains(where: { $0.status == .grace }) { return .late }
        let allReadable = !readings.isEmpty && fresh.count == readings.count && readings.allSatisfy { $0.readProblem == nil }
        return allReadable ? .ok : .unknown
    }
}

extension Check.Status {
    /// Lower sorts first: what needs attention leads the list.
    nonisolated var severity: Int {
        switch self {
        case .down: 0
        case .grace: 1
        case .started: 2
        case .up: 3
        case .new: 4
        case .paused: 5
        }
    }
}
