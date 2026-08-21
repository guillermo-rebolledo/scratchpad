import SwiftData
import SwiftUI

struct CaptureView: View {
    @Environment(DraftStore.self) private var draft
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @FocusState private var editorFocused: Bool
    @State private var errorMessage: String?
    @State private var confirmsClear = false
    @AccessibilityFocusState private var destinationNoticeFocused: Bool

    let onSaved: () -> Void

    var body: some View {
        @Bindable var draft = draft

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New Thought")
                    .font(.headline)
                Spacer()
                Button("Clear Draft", role: .destructive, action: requestClear)
                    .disabled(draft.markdown.isEmpty)
                    .help("Permanently removes the current Draft after confirmation.")
                    .accessibilityHint("Permanently removes the current Draft after confirmation.")
            }

            TextEditor(text: $draft.markdown)
                .font(.body.monospaced())
                .focused($editorFocused)
                .frame(minHeight: 190)
                .padding(4)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Draft Markdown")
                .accessibilityValue(draft.markdown.isEmpty ? String(localized: "Empty") : draft.markdown)
                .help("Enter raw Markdown. Press Command Return to save; Return inserts a new line.")
                .accessibilityHint("Enter raw Markdown. Press Command Return to save; Return inserts a new line.")
                .accessibilityIdentifier("capture.editor")
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    save()
                    return .handled
                }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Save error: \(errorMessage)")
                    .accessibilityIdentifier("capture.error")
            }

            if let destinationNotice = draft.destinationNotice {
                Label(destinationNotice, systemImage: "tray.and.arrow.down")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(destinationNotice)
                    .accessibilityIdentifier("capture.destination.notice")
                    .accessibilityFocused($destinationNoticeFocused)
            }

            HStack {
                Picker("Save to", selection: draftDestinationBinding) {
                    Text("Inbox").tag(UUID?.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)
                .help("Choose Inbox or an existing Project. Project management stays in the main window.")
                .accessibilityHint("Choose Inbox or an existing Project. The selection persists with this Draft and resets to Inbox after saving.")
                .accessibilityIdentifier("capture.destination")
                Spacer()
                Button("Save Thought", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!draft.canSave)
                    .help("Saves this Draft to the selected destination.")
                    .accessibilityHint("Saves this Draft to the selected destination, then resets the next Draft to Inbox.")
                    .accessibilityIdentifier("capture.save")
            }
        }
        .padding(16)
        .frame(width: 420)
        .onAppear { focusEditor() }
        .onAppear(perform: validateDestination)
        .onChange(of: projects.map(\.id)) { _, _ in validateDestination() }
        .onReceive(NotificationCenter.default.publisher(for: .focusCaptureEditor)) { _ in
            focusEditor()
        }
        .confirmationDialog(
            "Clear this Draft?",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("Clear Draft", role: .destructive) { draft.clear() }
            Button("Keep Draft", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Saved Thoughts are not affected.")
        }
    }

    private func focusEditor() {
        Task { @MainActor in
            editorFocused = true
        }
    }

    private func requestClear() {
        guard !draft.markdown.isEmpty else {
            draft.clear()
            return
        }
        confirmsClear = true
    }

    private func save() {
        guard draft.canSave else { return }
        errorMessage = nil

        do {
            let repository = ThoughtRepository(context: modelContext)
            let service = CaptureService(draft: draft) { markdown, projectID in
                if ProcessInfo.processInfo.arguments.contains("--simulate-save-failure") {
                    throw CaptureError.couldNotSave
                }
                let project = projectID.flatMap { id in projects.first { $0.id == id } }
                try repository.capture(markdown: markdown, project: project)
            }
            try service.save()
            onSaved()
        } catch {
            errorMessage = CaptureError.couldNotSave.localizedDescription
            editorFocused = true
        }
    }

    private func validateDestination() {
        guard let projectID = draft.projectID else { return }
        if !projects.contains(where: { $0.id == projectID }) {
            draft.fallBackToInboxBecauseProjectIsUnavailable()
            destinationNoticeFocused = true
        }
    }

    private var draftDestinationBinding: Binding<UUID?> {
        Binding(
            get: { draft.projectID },
            set: { projectID in
                draft.destinationNotice = nil
                draft.projectID = projectID
            }
        )
    }
}
