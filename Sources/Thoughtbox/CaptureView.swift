import SwiftData
import SwiftUI

struct CaptureView: View {
    @Environment(DraftStore.self) private var draft
    @Environment(\.modelContext) private var modelContext
    @FocusState private var editorFocused: Bool
    @State private var errorMessage: String?
    @State private var confirmsClear = false

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
                .accessibilityValue(draft.markdown.isEmpty ? "Empty" : draft.markdown)
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

            HStack {
                Text("Saves to Inbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Inbox contains Thoughts that are not assigned to a Project.")
                    .accessibilityHint("Inbox contains Thoughts that are not assigned to a Project.")
                Spacer()
                Button("Save Thought", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!draft.canSave)
                    .help("Saves this Draft as a Thought in Inbox.")
                    .accessibilityHint("Saves this Draft as a Thought in Inbox.")
                    .accessibilityIdentifier("capture.save")
            }
        }
        .padding(16)
        .frame(width: 420)
        .onAppear { focusEditor() }
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
            let service = CaptureService(draft: draft) { markdown in
                if ProcessInfo.processInfo.arguments.contains("--simulate-save-failure") {
                    throw CaptureError.couldNotSave
                }
                try repository.capture(markdown: markdown)
            }
            try service.save()
            onSaved()
        } catch {
            errorMessage = CaptureError.couldNotSave.localizedDescription
            editorFocused = true
        }
    }
}
