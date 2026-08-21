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

private enum ThoughtPresentationMode: String, CaseIterable, Identifiable {
    case read = "Read"
    case edit = "Edit"

    var id: Self { self }
}

struct ThoughtDetailView: View {
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
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Picker("Thought presentation", selection: guardedMode) {
                    ForEach(ThoughtPresentationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .help("Read renders Markdown. Edit shows the canonical source and auto-saves changes.")
                .accessibilityHint("Read renders Markdown. Edit shows the canonical source and auto-saves changes.")
                .accessibilityIdentifier("thought.mode")
            }
            .padding()

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
            } else {
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Changes saved")
            }
        }
        .padding()
        .onAppear {
            editNavigationGuard.saveBeforeLeaving = saveNow
            editorFocused = true
        }
        .onDisappear {
            if saveNow() {
                editNavigationGuard.saveBeforeLeaving = nil
            }
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
            saveError = "Thoughtbox could not save these changes. Restore non-empty content or retry before leaving Edit."
            editorFocused = true
            return false
        }
    }
}
