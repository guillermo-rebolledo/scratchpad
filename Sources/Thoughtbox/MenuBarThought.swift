import AppKit
import Observation
import SwiftData
import SwiftUI

enum MenuBarThoughtScope: Codable, Equatable, Hashable {
    case allThoughts
    case inbox
    case project(UUID)

    var storageValue: String {
        switch self {
        case .allThoughts: "all"
        case .inbox: "inbox"
        case let .project(id): "project:\(id.uuidString)"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "all": self = .allThoughts
        case "inbox": self = .inbox
        default:
            guard storageValue.hasPrefix("project:"),
                  let id = UUID(uuidString: String(storageValue.dropFirst("project:".count)))
            else { return nil }
            self = .project(id)
        }
    }

    func includes(_ thought: Thought) -> Bool {
        guard thought.trashedAt == nil else { return false }
        return switch self {
        case .allThoughts: true
        case .inbox: thought.project == nil
        case let .project(id): thought.project?.id == id
        }
    }
}

@MainActor
@Observable
final class MenuBarThoughtSelection {
    private enum Key {
        static let scope = "menuBarThought.scope"
        static let thoughtID = "menuBarThought.thoughtID"
    }

    private let defaults: UserDefaults

    var scope: MenuBarThoughtScope {
        didSet { defaults.set(scope.storageValue, forKey: Key.scope) }
    }

    private(set) var thoughtID: UUID? {
        didSet {
            if let thoughtID {
                defaults.set(thoughtID.uuidString, forKey: Key.thoughtID)
            } else {
                defaults.removeObject(forKey: Key.thoughtID)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        scope = defaults.string(forKey: Key.scope)
            .flatMap(MenuBarThoughtScope.init(storageValue:)) ?? .allThoughts
        thoughtID = defaults.string(forKey: Key.thoughtID).flatMap(UUID.init(uuidString:))
        self.defaults = defaults
    }

    func availableThoughts(from thoughts: [Thought], projectIDs: Set<UUID>) -> [Thought] {
        if case let .project(id) = scope, !projectIDs.contains(id) {
            scope = .allThoughts
        }
        return thoughts.filter(scope.includes)
    }

    @discardableResult
    func reconcile(thoughts: [Thought], projectIDs: Set<UUID>) -> Thought? {
        let available = availableThoughts(from: thoughts, projectIDs: projectIDs)
        if let thoughtID, let selected = available.first(where: { $0.id == thoughtID }) {
            return selected
        }
        if let thoughtID, let movedThought = thoughts.first(where: { $0.id == thoughtID }) {
            scope = movedThought.project.map { .project($0.id) } ?? .inbox
            return movedThought
        }
        thoughtID = available.first?.id
        return available.first
    }

    @discardableResult
    func selectAnother(thoughts: [Thought], projectIDs: Set<UUID>) -> Thought? {
        let available = availableThoughts(from: thoughts, projectIDs: projectIDs)
        guard !available.isEmpty else {
            thoughtID = nil
            return nil
        }
        guard let thoughtID,
              let index = available.firstIndex(where: { $0.id == thoughtID }),
              available.count > 1 else {
            self.thoughtID = available.first?.id
            return available.first
        }
        let selected = available[available.index(after: index) == available.endIndex ? available.startIndex : available.index(after: index)]
        self.thoughtID = selected.id
        return selected
    }

    func selectScope(_ scope: MenuBarThoughtScope, thoughts: [Thought], projectIDs: Set<UUID>) {
        self.scope = scope
        thoughtID = availableThoughts(from: thoughts, projectIDs: projectIDs).first?.id
    }
}

enum ThoughtAppendError: LocalizedError, Equatable {
    case emptyNote
    case couldNotSave

    var errorDescription: String? {
        switch self {
        case .emptyNote: String(localized: "Enter a note before appending.")
        case .couldNotSave: String(localized: "Thoughtbox could not append this note. Your text is still here; try again.")
        }
    }
}

@MainActor
enum ThoughtAppender {
    static func append(
        _ note: String,
        to thought: Thought,
        using repository: ThoughtRepository,
        at date: Date = .now,
        saveChanges: (() throws -> Void)? = nil
    ) throws {
        guard note.containsNonWhitespace else { throw ThoughtAppendError.emptyNote }
        let existingBreaks = thought.markdown.reversed().prefix { $0 == "\n" }.count
        let noteBreaks = note.prefix { $0 == "\n" }.count
        let missingBreaks = max(0, 2 - min(2, existingBreaks + noteBreaks))
        let separator = String(repeating: "\n", count: missingBreaks)
        let markdown = thought.markdown + separator + note
        do {
            try repository.update(
                thought,
                markdown: markdown,
                at: date,
                saveChanges: saveChanges
            )
        } catch {
            throw ThoughtAppendError.couldNotSave
        }
    }
}

@MainActor
final class MenuBarThoughtController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init(container: ModelContainer, selection: MenuBarThoughtSelection) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Thoughtbox Thought")
            image?.isTemplate = true
            button.image = image
            button.toolTip = String(localized: "Open a Thought")
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
        }

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = NSSize(width: 390, height: 510)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarThoughtView(selection: selection)
                .modelContainer(container)
        )
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        NotificationCenter.default.post(name: .focusMenuBarThoughtNote, object: nil)
    }
}

extension Notification.Name {
    static let focusMenuBarThoughtNote = Notification.Name("Thoughtbox.focusMenuBarThoughtNote")
}

private struct MenuBarThoughtView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Thought> { $0.trashedAt == nil },
        sort: [SortDescriptor(\Thought.createdAt, order: .reverse)]
    ) private var thoughts: [Thought]
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Bindable var selection: MenuBarThoughtSelection
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var selectionNotice: String?
    @FocusState private var noteFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Picker("Source", selection: scopeBinding) {
                    Label("All Thoughts", systemImage: "rectangle.stack")
                        .tag(MenuBarThoughtScope.allThoughts)
                    Label("Inbox", systemImage: "tray")
                        .tag(MenuBarThoughtScope.inbox)
                    if !projects.isEmpty {
                        Divider()
                        ForEach(projects) { project in
                            Label(project.name, systemImage: "folder")
                                .tag(MenuBarThoughtScope.project(project.id))
                        }
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Thought source")
                .accessibilityValue(scopeName)
                .accessibilityHint("Choose All Thoughts, Inbox, or one Project.")
                .accessibilityIdentifier("menuBarThought.source")

                Spacer()

                Button("Another Thought", systemImage: "arrow.right") {
                    selection.selectAnother(thoughts: thoughts, projectIDs: projectIDs)
                    note = ""
                    errorMessage = nil
                    selectionNotice = nil
                    focusNote()
                }
                .labelStyle(.iconOnly)
                .disabled(availableThoughts.count < 2)
                .help("Select the next Thought from \(scopeName).")
                .accessibilityHint("Keeps the selected source and moves to its next Thought.")
                .accessibilityIdentifier("menuBarThought.another")
            }

            Divider()

            if let thought = selectedThought {
                ScrollView {
                    MarkdownReader(markdown: thought.markdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
                .accessibilityLabel("Selected Thought")
                .accessibilityValue(thought.markdown)
                .accessibilityIdentifier("menuBarThought.thought")

                Divider()

                TextEditor(text: $note)
                    .font(.body.monospaced())
                    .focused($noteFocused)
                    .frame(height: 92)
                    .padding(4)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Note to append")
                    .accessibilityValue(note.isEmpty ? String(localized: "Empty") : note)
                    .accessibilityHint("Press Command Return to append this note to the selected Thought.")
                    .accessibilityIdentifier("menuBarThought.note")
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        appendNote(to: thought)
                        return .handled
                    }

                if let errorMessage {
                    AccessibleErrorMessage(
                        message: errorMessage,
                        accessibilityLabel: "Append error: \(errorMessage)",
                        identifier: "menuBarThought.error"
                    )
                    .accessibilityFocused($errorFocused)
                }

                if let selectionNotice {
                    Label(selectionNotice, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("menuBarThought.selectionNotice")
                }

                HStack {
                    Label(thought.project?.name ?? String(localized: "Inbox"), systemImage: thought.project == nil ? "tray" : "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Append to Thought") { appendNote(to: thought) }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!note.containsNonWhitespace)
                        .help("Append this note to the same Thought and keep it selected.")
                        .accessibilityHint("Saves the note after the existing Markdown and keeps this Thought selected.")
                        .accessibilityIdentifier("menuBarThought.append")
                }
            } else {
                ContentUnavailableView {
                    Label("No Thoughts", systemImage: "text.bubble")
                } description: {
                    Text("There are no active Thoughts in \(scopeName). Choose another source or capture a Thought first.")
                    if note.containsNonWhitespace {
                        Text("Your unappended note is preserved and will be available when a Thought can be selected.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("menuBarThought.empty")
            }
        }
        .padding(16)
        .frame(width: 390, height: 510)
        .onAppear {
            _ = selection.reconcile(thoughts: thoughts, projectIDs: projectIDs)
            focusNote()
        }
        .onChange(of: thoughtDestinations) { _, _ in
            _ = selection.reconcile(thoughts: thoughts, projectIDs: projectIDs)
        }
        .onChange(of: projects.map(\.id)) { _, _ in
            _ = selection.reconcile(thoughts: thoughts, projectIDs: projectIDs)
        }
        .onChange(of: selection.thoughtID) { previousID, selectedID in
            guard previousID != nil,
                  previousID != selectedID,
                  note.containsNonWhitespace else { return }
            selectionNotice = String(localized: "The selected Thought changed because the previous one is no longer available. Your note is still here; review the new Thought before appending.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusMenuBarThoughtNote)) { _ in
            focusNote()
        }
    }

    private var projectIDs: Set<UUID> { Set(projects.map(\.id)) }

    private var thoughtDestinations: [String] {
        thoughts.map { thought in
            "\(thought.id.uuidString):\(thought.project?.id.uuidString ?? "inbox")"
        }
    }

    private var availableThoughts: [Thought] {
        thoughts.filter(selection.scope.includes)
    }

    private var selectedThought: Thought? {
        guard let thoughtID = selection.thoughtID else { return nil }
        return availableThoughts.first { $0.id == thoughtID }
    }

    private var scopeName: String {
        switch selection.scope {
        case .allThoughts: String(localized: "All Thoughts")
        case .inbox: String(localized: "Inbox")
        case let .project(id): projects.first(where: { $0.id == id })?.name ?? String(localized: "All Thoughts")
        }
    }

    private var scopeBinding: Binding<MenuBarThoughtScope> {
        Binding(
            get: { selection.scope },
            set: { scope in
                selection.selectScope(scope, thoughts: thoughts, projectIDs: projectIDs)
                note = ""
                errorMessage = nil
                selectionNotice = nil
                focusNote()
            }
        )
    }

    private func appendNote(to thought: Thought) {
        do {
            try ThoughtAppender.append(note, to: thought, using: ThoughtRepository(context: modelContext))
            note = ""
            errorMessage = nil
            selectionNotice = nil
            announceForAccessibility(String(localized: "Note appended to Thought."))
        } catch {
            errorMessage = (error as? ThoughtAppendError)?.localizedDescription
                ?? ThoughtAppendError.couldNotSave.localizedDescription
            errorFocused = true
        }
        focusNote()
    }

    private func focusNote() {
        guard selectedThought != nil else { return }
        noteFocused = false
        Task { @MainActor in noteFocused = true }
    }
}
