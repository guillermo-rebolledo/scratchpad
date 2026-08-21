import SwiftData
import SwiftUI

@MainActor
@Observable
final class ThoughtEditNavigationGuard {
    var saveBeforeLeaving: (() -> Bool)?

    func canLeaveEditor() -> Bool {
        saveBeforeLeaving?() ?? true
    }
}

private enum ThoughtPresentationMode: CaseIterable, Identifiable {
    case read
    case edit

    var id: Self { self }

    var title: String {
        switch self {
        case .read: String(localized: "Read")
        case .edit: String(localized: "Edit")
        }
    }
}

struct ThoughtDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var destinationError: String?
    @AccessibilityFocusState private var destinationErrorFocused: Bool

    let thought: Thought
    let editNavigationGuard: ThoughtEditNavigationGuard
    @State private var mode = ThoughtPresentationMode.read

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created \(thought.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    if thought.editedAt != thought.createdAt {
                        Text("Edited \(thought.editedAt.formatted(date: .abbreviated, time: .shortened))")
                            .accessibilityIdentifier("thought.edited.at")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if thought.trashedAt == nil {
                        Picker("Destination", selection: destinationBinding) {
                            Text("Inbox").tag(UUID?.none)
                            ForEach(projects) { project in
                                Text(project.name).tag(Optional(project.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .help("Moves this Thought between Inbox and one Project.")
                        .accessibilityHint("Moves this Thought between Inbox and one Project. Changes save immediately.")
                        .accessibilityIdentifier("thought.destination")
                    } else {
                        Label("In Trash", systemImage: "trash")
                            .foregroundStyle(.secondary)
                            .accessibilityHint("Use Restore Selected or Delete Permanently below the Trash list.")
                            .accessibilityIdentifier("thought.trash.status")
                    }

                    Picker("Thought presentation", selection: guardedMode) {
                        ForEach(ThoughtPresentationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .help("Read renders Markdown. Edit shows the canonical source and auto-saves changes.")
                    .accessibilityHint("Read renders Markdown. Edit shows the canonical source and auto-saves changes.")
                    .accessibilityIdentifier("thought.mode")
                }
            }
            .padding()

            if let destinationError {
                Label(destinationError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .accessibilityLabel("Destination error: \(destinationError)")
                    .accessibilityIdentifier("thought.destination.error")
                    .accessibilityFocused($destinationErrorFocused)
            }

            Divider()

            switch mode {
            case .read:
                ScrollView {
                    MarkdownReader(markdown: thought.markdown)
                        .padding()
                }
            case .edit:
                ThoughtSourceEditor(thought: thought, editNavigationGuard: editNavigationGuard)
            }
        }
    }

    private var guardedMode: Binding<ThoughtPresentationMode> {
        Binding(
            get: { mode },
            set: { requestedMode in
                guard requestedMode == mode || editNavigationGuard.canLeaveEditor() else { return }
                mode = requestedMode
            }
        )
    }

    private var destinationBinding: Binding<UUID?> {
        Binding(
            get: { thought.project?.id },
            set: { requestedID in
                guard editNavigationGuard.canLeaveEditor() else { return }
                do {
                    let destination = requestedID.flatMap { id in projects.first { $0.id == id } }
                    try ThoughtRepository(context: modelContext).move(thought, to: destination)
                    destinationError = nil
                } catch {
                    if let projectError = error as? ProjectError {
                        destinationError = projectError.localizedDescription
                    } else {
                        destinationError = ProjectError.couldNotSave.localizedDescription
                    }
                    destinationErrorFocused = true
                }
            }
        )
    }
}

private struct ThoughtSourceEditor: View {
    @Environment(\.modelContext) private var modelContext
    @FocusState private var editorFocused: Bool
    @State private var markdown: String
    @State private var lastSavedMarkdown: String
    @State private var saveError: String?
    @State private var pendingSave: Task<Void, Never>?

    let thought: Thought
    let editNavigationGuard: ThoughtEditNavigationGuard

    init(thought: Thought, editNavigationGuard: ThoughtEditNavigationGuard) {
        self.thought = thought
        self.editNavigationGuard = editNavigationGuard
        _markdown = State(initialValue: thought.markdown)
        _lastSavedMarkdown = State(initialValue: thought.markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $markdown)
                .font(.body.monospaced())
                .focused($editorFocused)
                .accessibilityLabel("Thought Markdown source")
                .accessibilityValue(markdown)
                .accessibilityHint("Changes auto-save after a short pause and when focus or selection changes.")
                .accessibilityIdentifier("thought.editor")
                .onChange(of: markdown) { _, _ in scheduleSave() }
                .onChange(of: editorFocused) { _, focused in
                    if !focused { saveNow() }
                }

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Edit error: \(saveError)")
                    .accessibilityIdentifier("thought.edit.error")
            } else if markdown != lastSavedMarkdown {
                Text("Saving…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Saving changes")
                    .accessibilityIdentifier("thought.save.status")
            } else {
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Changes saved")
                    .accessibilityIdentifier("thought.save.status")
            }
        }
        .padding()
        .onAppear {
            editNavigationGuard.saveBeforeLeaving = saveNow
            editorFocused = true
        }
        .onDisappear {
            saveNow()
            editNavigationGuard.saveBeforeLeaving = nil
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    @discardableResult
    private func saveNow() -> Bool {
        pendingSave?.cancel()
        guard markdown != lastSavedMarkdown else {
            saveError = nil
            return true
        }

        do {
            let repository = ThoughtRepository(context: modelContext)
            try repository.update(thought, markdown: markdown)
            lastSavedMarkdown = markdown
            saveError = nil
            return true
        } catch {
            saveError = String(localized: "Thoughtbox could not save these changes. Restore non-empty content or retry before leaving Edit.")
            editorFocused = true
            return false
        }
    }
}
