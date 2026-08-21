import Foundation
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

private enum ThoughtPresentationMode {
    case read
    case edit
}

struct ThoughtDestinationCommand: Identifiable {
    let projectID: UUID?
    let name: String
    let isCurrent: Bool

    var id: String { projectID?.uuidString ?? "inbox" }
}

struct ThoughtCommandActions {
    let isEditing: Bool
    let toggleEditing: () -> Void
}

struct ThoughtCommandActionsKey: FocusedValueKey {
    typealias Value = ThoughtCommandActions
}

extension FocusedValues {
    var thoughtCommandActions: ThoughtCommandActions? {
        get { self[ThoughtCommandActionsKey.self] }
        set { self[ThoughtCommandActionsKey.self] = newValue }
    }
}

struct ThoughtDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var destinationError: String?
    @FocusState private var editButtonFocused: Bool
    @AccessibilityFocusState private var destinationErrorFocused: Bool

    let thought: Thought
    let editNavigationGuard: ThoughtEditNavigationGuard
    let onMoveToTrash: (() -> Void)?
    @State private var mode = ThoughtPresentationMode.read

    var body: some View {
        VStack(spacing: 0) {
            compactMetadata

            if let destinationError {
                AccessibleErrorMessage(
                    message: destinationError,
                    accessibilityLabel: "Destination error: \(destinationError)",
                    identifier: "thought.destination.error"
                )
                    .padding(.horizontal)
                    .accessibilityFocused($destinationErrorFocused)
            }

            switch mode {
            case .read:
                ScrollView {
                    MarkdownReader(markdown: thought.markdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
            case .edit:
                ThoughtSourceEditor(thought: thought, editNavigationGuard: editNavigationGuard)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if thought.trashedAt == nil {
                    destinationMenu
                }
                editButton
                if let onMoveToTrash {
                    Button(role: .destructive, action: onMoveToTrash) {
                        Label("Move to Trash", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .controlSize(.regular)
                    .help("Move this Thought to Trash.")
                    .accessibilityLabel("Move to Trash")
                    .accessibilityValue("Selected Thought")
                    .accessibilityHint("Moves this Thought to Trash without confirmation. You can restore it later.")
                    .accessibilityIdentifier("trash.move")
                }
            }
        }
        .focusedSceneValue(\.thoughtCommandActions, focusedThoughtCommandActions)
    }

    private var compactMetadata: some View {
        HStack(spacing: 12) {
            Label(
                "Created \(thought.createdAt.formatted(date: .abbreviated, time: .shortened))",
                systemImage: "calendar"
            )
            .lineLimit(1)

            if thought.editedAt != thought.createdAt {
                Label(
                    "Edited \(thought.editedAt.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "pencil"
                )
                .lineLimit(1)
                .accessibilityIdentifier("thought.edited.at")
            }

            Spacer(minLength: 8)

            if thought.trashedAt != nil {
                Label("In Trash", systemImage: "trash")
                    .lineLimit(1)
                    .accessibilityHint("Use the available Trash actions to restore, export, or permanently delete this Thought.")
                    .accessibilityIdentifier("thought.trash.status")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var destinationMenu: some View {
        Menu {
            Button {
                moveThought(to: nil)
            } label: {
                if thought.project == nil {
                    Label("Inbox", systemImage: "checkmark")
                } else {
                    Text("Inbox")
                }
            }

            Divider()

            ForEach(projects) { project in
                Button {
                    moveThought(to: project.id)
                } label: {
                    if thought.project?.id == project.id {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        } label: {
            Label {
                Text(destinationName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: destinationSystemImage)
            }
            .frame(maxWidth: 180)
        }
        .controlSize(.regular)
        .help("Move this Thought. Current destination: \(destinationName).")
        .accessibilityLabel("Thought destination")
        .accessibilityValue(destinationName)
        .accessibilityHint("Choose Inbox or one Project. Changes save immediately.")
        .accessibilityIdentifier("thought.destination")
    }

    private var editButton: some View {
        Button(action: toggleEditing) {
            Label(
                mode == .read ? "Edit" : "Done",
                systemImage: mode == .read ? "pencil" : "checkmark"
            )
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.regular)
        .focused($editButtonFocused)
        .help(mode == .read ? "Edit the canonical Markdown source." : "Save and return to rendered Markdown.")
        .accessibilityLabel(mode == .read ? "Edit Thought" : "Done Editing")
        .accessibilityValue(mode == .read ? "Rendered Markdown" : "Editing canonical Markdown")
        .accessibilityHint(mode == .read ? "Shows the raw Markdown editor and focuses it." : "Saves pending changes and returns focus to this button.")
        .accessibilityIdentifier("thought.edit")
    }

    private var destinationName: String {
        thought.project?.name ?? String(localized: "Inbox")
    }

    private var destinationSystemImage: String {
        thought.project == nil ? "tray" : "folder"
    }

    private var focusedThoughtCommandActions: ThoughtCommandActions {
        ThoughtCommandActions(
            isEditing: mode == .edit,
            toggleEditing: toggleEditing
        )
    }

    private func toggleEditing() {
        switch mode {
        case .read:
            mode = .edit
        case .edit:
            guard editNavigationGuard.canLeaveEditor() else { return }
            mode = .read
            Task { @MainActor in
                editButtonFocused = true
            }
        }
    }

    private func moveThought(to requestedID: UUID?) {
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
                AccessibleErrorMessage(
                    message: saveError,
                    accessibilityLabel: "Edit error: \(saveError)",
                    identifier: "thought.edit.error"
                )
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
