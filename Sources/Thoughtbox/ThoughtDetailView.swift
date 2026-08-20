import SwiftData
import SwiftUI

private enum ThoughtPresentationMode: String, CaseIterable, Identifiable {
    case read = "Read"
    case edit = "Edit"

    var id: Self { self }
}

struct ThoughtDetailView: View {
    let thought: Thought
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

                Picker("Thought presentation", selection: $mode) {
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
                ThoughtSourceEditor(thought: thought)
            }
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

    init(thought: Thought) {
        self.thought = thought
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
        .onAppear { editorFocused = true }
        .onDisappear { saveNow() }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        pendingSave?.cancel()
        guard markdown != lastSavedMarkdown else { return }

        do {
            let repository = ThoughtRepository(context: modelContext)
            try repository.update(thought, markdown: markdown)
            lastSavedMarkdown = markdown
            saveError = nil
        } catch {
            saveError = "Thoughtbox could not save these changes. Keep this editor open and try again."
        }
    }
}
