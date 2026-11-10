import AppKit
import SwiftUI

/// The panel behind the menu bar icon: overall state, each project's checks, and the app's few actions.
struct PanelView: View {
    let store: ChecksStore

    @Environment(\.openURL) private var openURL
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            if let updatedAt = store.updatedAt {
                Text("updated \(updatedAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var title: String {
        switch store.health {
        case .down(let count): "\(count) down"
        case .late: "Running late"
        case .ok: "All healthy"
        case .unknown: "Status unknown"
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.readings.isEmpty {
            Text("Add a project’s API key in Settings to see its checks.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.readings) { reading in
                        ProjectSection(reading: reading) { check in
                            openURL(check.detailsURL ?? HealthchecksAPI.siteURL)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh", systemImage: "arrow.clockwise", action: store.refresh)
                .labelStyle(.iconOnly)
            Button("Open Healthchecks", systemImage: "arrow.up.right.square") {
                openURL(HealthchecksAPI.siteURL)
            }
            Spacer()
            Button("Settings…", systemImage: "gearshape") {
                openSettings()
                dismiss()
            }
            .labelStyle(.iconOnly)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .controlSize(.small)
        .padding(10)
    }
}

/// A project's name over its checks; while it can't be read, a warning and its last known checks, dimmed.
private struct ProjectSection: View {
    let reading: ProjectReading
    let openDetails: (Check) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(reading.project.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(reading.project.name)
                    if reading.readProblem != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if let readProblem = reading.readProblem {
                    Text(readProblemNote(readProblem))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .help(readProblem)
                }
            }
            .padding(.horizontal, 8)
            if reading.checks.isEmpty && reading.readProblem == nil {
                Text(reading.readAt == nil ? "Reading the checks…" : "No checks yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            ForEach(reading.checks) { check in
                CheckRow(check: check, failureReason: reading.failureReasons[check.id]) {
                    openDetails(check)
                }
            }
            .opacity(reading.readProblem == nil ? 1 : 0.5)
        }
    }

    private func readProblemNote(_ readProblem: String) -> String {
        guard let readAt = reading.readAt else { return readProblem }
        return "\(readProblem) · last read \(RelativeDateTimeFormatter.abbreviated.localizedString(for: readAt, relativeTo: .now))"
    }
}

private struct CheckRow: View {
    let check: Check
    let failureReason: String?
    let openDetails: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: openDetails) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.name)
                        .lineLimit(1)
                    Text(timing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let failureReason {
                        Text(failureReason)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isHovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tooltip)
    }

    /// The full name and failure reason the row may cut short, with a huge reason capped so the tooltip fits on screen.
    private var tooltip: String {
        guard let failureReason else { return check.name }
        let shownReason = failureReason.count > 1000 ? String(failureReason.prefix(1000)) + "…" : failureReason
        return "\(check.name)\n\(shownReason)"
    }

    private var dotColor: Color {
        switch check.status {
        case .down: .red
        case .grace: .orange
        case .up: .green
        case .started: .blue
        case .new, .paused: .gray
        }
    }

    private var timing: String {
        switch check.status {
        case .new: return "No pings yet"
        case .paused: return "Paused"
        default:
            let lastPing = check.lastPing.map { "pinged \(relative($0))" }
            let nextPing = check.nextPing.map { "\($0 > .now ? "next" : "due") \(relative($0))" }
            return [lastPing, nextPing].compactMap(\.self).joined(separator: " · ")
        }
    }

    private func relative(_ date: Date) -> String {
        RelativeDateTimeFormatter.abbreviated.localizedString(for: date, relativeTo: .now)
    }
}

private extension RelativeDateTimeFormatter {
    static let abbreviated: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
