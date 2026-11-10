import AppKit
import ServiceManagement
import SwiftUI

/// The Settings window: which projects to watch, and launching at login.
struct SettingsView: View {
    let store: ChecksStore

    var body: some View {
        Form {
            ProjectsSection(store: store)
            LaunchAtLoginSection()
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}

private struct ProjectsSection: View {
    let store: ChecksStore

    @State private var isAdding = false
    @State private var saveError: String?

    var body: some View {
        Section("Projects") {
            if store.projects.isEmpty {
                Text("No projects yet. Add one to see its checks in the menu bar.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.projects) { project in
                ProjectRow(
                    project: project,
                    isFirst: project.id == store.projects.first?.id,
                    isLast: project.id == store.projects.last?.id
                ) { offset in
                    saving { try store.move(project, by: offset) }
                } remove: {
                    saving { try store.remove(project) }
                }
            }
            if let saveError {
                Text(saveError)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Add Project…") {
                    isAdding = true
                }
                .sheet(isPresented: $isAdding) {
                    AddProjectSheet(store: store)
                }
            }
        }
    }

    /// Runs a change to the saved projects, showing why it failed if it does.
    private func saving(_ change: () throws -> Void) {
        do {
            try change()
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let isFirst: Bool
    let isLast: Bool
    /// Moves the project one place up (-1) or down (+1).
    let move: (_ offset: Int) -> Void
    let remove: () -> Void

    @State private var isConfirmingRemoval = false

    var body: some View {
        LabeledContent(project.name) {
            HStack {
                Text("••••\(project.apiKey.suffix(4))")
                    .monospaced()
                    .foregroundStyle(.secondary)
                Button("Remove \(project.name)", systemImage: "minus.circle") {
                    isConfirmingRemoval = true
                }
                if !(isFirst && isLast) {
                    Button("Move \(project.name) Up", systemImage: "chevron.up") {
                        move(-1)
                    }
                    .disabled(isFirst)
                    Button("Move \(project.name) Down", systemImage: "chevron.down") {
                        move(1)
                    }
                    .disabled(isLast)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .confirmationDialog("Remove “\(project.name)”?", isPresented: $isConfirmingRemoval) {
            Button("Remove", role: .destructive, action: remove)
        } message: {
            Text("Its API key is deleted from this Mac.")
        }
    }
}

/// Asks for a project's name and key, and closes once Healthchecks accepts the key.
private struct AddProjectSheet: View {
    let store: ChecksStore

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var apiKey = ""
    @State private var isChecking = false
    @State private var addError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a Healthchecks Project")
                .font(.headline)
            Text("Paste the API key from the project’s Settings on healthchecks.io. A read-only key works too, but its checks can’t be opened from the panel or explain why they failed.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Name:", text: $name, prompt: Text("Production"))
                SecureField("API key:", text: $apiKey)
            }
            if let addError {
                Text(addError)
                    .foregroundStyle(.red)
            }
            HStack {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking the key…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(entry == nil || isChecking)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var entry: (name: String, apiKey: String)? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || apiKey.isEmpty ? nil : (name, apiKey)
    }

    private func add() {
        guard let entry, !isChecking else { return }
        isChecking = true
        addError = nil
        Task {
            do {
                try await store.add(name: entry.name, apiKey: entry.apiKey)
                dismiss()
            } catch {
                addError = error.localizedDescription
                isChecking = false
            }
        }
    }
}

private struct LaunchAtLoginSection: View {
    @State private var status = SMAppService.mainApp.status
    @State private var registrationError: (any Error)?

    var body: some View {
        Section {
            Toggle("Launch at login", isOn: Binding(get: { isRegistered }, set: setLaunchAtLogin))
            if status == .requiresApproval {
                LabeledContent {
                    Button("Open Login Items Settings") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } label: {
                    Text("HealthchecksX launches at login once you allow it in Login Items.")
                }
            }
            if let registrationError {
                Text("Couldn’t change launching at login. \(registrationError.localizedDescription)")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                status = SMAppService.mainApp.status
            }
        }
    }

    /// Registered, including while macOS waits for the user's approval.
    private var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    private func setLaunchAtLogin(_ isOn: Bool) {
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            registrationError = nil
        } catch {
            registrationError = error
        }
        status = SMAppService.mainApp.status
    }
}
