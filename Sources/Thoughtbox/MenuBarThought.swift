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

    static func populatedProjects(from projects: [Project], thoughts: [Thought]) -> [Project] {
        let populatedIDs = Set(
            thoughts
                .filter { $0.trashedAt == nil }
                .compactMap { $0.project?.id }
        )
        return projects.filter { populatedIDs.contains($0.id) }
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
        if case let .project(id) = scope,
           !projectIDs.contains(id) || !thoughts.contains(where: scope.includes) {
            scope = .allThoughts
        }
        return thoughts.filter(scope.includes)
    }

    @discardableResult
    func reconcile(thoughts: [Thought], projectIDs: Set<UUID>) -> Thought? {
        if let thoughtID, let currentThought = thoughts.first(where: { $0.id == thoughtID }) {
            if scope.includes(currentThought) { return currentThought }
            scope = currentThought.project.map { .project($0.id) } ?? .inbox
            return currentThought
        }
        let available = availableThoughts(from: thoughts, projectIDs: projectIDs)
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

    @discardableResult
    func selectThought(_ id: UUID, thoughts: [Thought], projectIDs: Set<UUID>) -> Thought? {
        guard let thought = availableThoughts(from: thoughts, projectIDs: projectIDs)
            .first(where: { $0.id == id }) else { return nil }
        thoughtID = thought.id
        return thought
    }
}

enum MenuBarThoughtEditError: LocalizedError, Equatable {
    case emptyThought
    case couldNotSave
    case thoughtUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyThought: String(localized: "A Thought can’t be empty. Restore some content before saving.")
        case .couldNotSave: String(localized: "Thoughtbox could not save these changes. Your text is still here; try again.")
        case .thoughtUnavailable: String(localized: "The original Thought is no longer available. Your edits were not saved.")
        }
    }
}

@MainActor
enum MenuBarThoughtEditor {
    static func save(
        _ markdown: String,
        loadedThoughtID: UUID?,
        among thoughts: [Thought],
        using repository: ThoughtRepository,
        at date: Date = .now,
        saveChanges: (() throws -> Void)? = nil
    ) throws {
        guard let loadedThoughtID,
              let thought = thoughts.first(where: {
                  $0.id == loadedThoughtID && $0.trashedAt == nil
              }) else {
            throw MenuBarThoughtEditError.thoughtUnavailable
        }
        try save(markdown, to: thought, using: repository, at: date, saveChanges: saveChanges)
    }

    static func save(
        _ markdown: String,
        to thought: Thought,
        using repository: ThoughtRepository,
        at date: Date = .now,
        saveChanges: (() throws -> Void)? = nil
    ) throws {
        guard markdown.containsNonWhitespace else { throw MenuBarThoughtEditError.emptyThought }
        do {
            try repository.update(
                thought,
                markdown: markdown,
                at: date,
                saveChanges: saveChanges
            )
        } catch {
            throw MenuBarThoughtEditError.couldNotSave
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
        NotificationCenter.default.post(name: .focusMenuBarThoughtEditor, object: nil)
    }
}

extension Notification.Name {
    static let focusMenuBarThoughtEditor = Notification.Name("Thoughtbox.focusMenuBarThoughtEditor")
}

private struct MenuBarThoughtView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Thought> { $0.trashedAt == nil },
        sort: [SortDescriptor(\Thought.createdAt, order: .reverse)]
    ) private var thoughts: [Thought]
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Bindable var selection: MenuBarThoughtSelection
    @State private var markdown = ""
    @State private var lastSavedMarkdown = ""
    @State private var loadedThoughtID: UUID?
    @State private var errorMessage: String?
    @State private var selectionNotice: String?
    @FocusState private var editorFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Picker("Source", selection: scopeBinding) {
                    Label("All Thoughts", systemImage: "rectangle.stack")
                        .tag(MenuBarThoughtScope.allThoughts)
                    Label("Inbox", systemImage: "tray")
                        .tag(MenuBarThoughtScope.inbox)
                    if !populatedProjects.isEmpty {
                        Divider()
                        ForEach(populatedProjects) { project in
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
                .frame(maxWidth: 130)

                Picker("Thought", selection: thoughtBinding) {
                    if availableThoughts.isEmpty {
                        Text("No Thoughts")
                            .tag(UUID?.none)
                    } else {
                        ForEach(availableThoughts) { thought in
                            Text(thoughtChoiceName(thought))
                                .tag(Optional(thought.id))
                        }
                    }
                }
                .labelsHidden()
                .disabled(availableThoughts.isEmpty)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Selected Thought")
                .accessibilityValue(selectedThought.map(thoughtChoiceName) ?? String(localized: "No Thoughts"))
                .accessibilityHint("Choose a specific Thought from \(scopeName). Unsaved changes are saved before switching.")
                .accessibilityIdentifier("menuBarThought.thoughtPicker")

                Button("Another Thought", systemImage: "arrow.right") {
                    guard saveCurrentThought() else { return }
                    selection.selectAnother(thoughts: thoughts, projectIDs: projectIDs)
                    loadSelectedThought()
                    focusEditor()
                }
                .labelStyle(.iconOnly)
                .disabled(availableThoughts.count < 2)
                .help("Select the next Thought from \(scopeName).")
                .accessibilityHint("Keeps the selected source and moves to its next Thought.")
                .accessibilityIdentifier("menuBarThought.another")
            }

            Divider()

            if let thought = selectedThought {
                TextEditor(text: $markdown)
                    .font(.body.monospaced())
                    .focused($editorFocused)
                    .frame(maxHeight: .infinity)
                    .padding(4)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Thought Markdown source")
                    .accessibilityValue(markdown)
                    .accessibilityHint("Edit the complete Thought. Press Command Return to save.")
                    .accessibilityIdentifier("menuBarThought.editor")
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        _ = saveCurrentThought()
                        return .handled
                    }

                if let errorMessage {
                    AccessibleErrorMessage(
                        message: errorMessage,
                        accessibilityLabel: "Edit error: \(errorMessage)",
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
                    if hasUnsavedChanges {
                        Text("Unsaved changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("menuBarThought.saveStatus")
                    }
                    Text("⌘↩ to save")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Command Return saves the Thought")
                        .accessibilityIdentifier("menuBarThought.saveHint")
                    Button("Save Thought") { _ = saveCurrentThought() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!hasUnsavedChanges || !markdown.containsNonWhitespace)
                        .help("Save the complete Thought. Shortcut: Command–Return.")
                        .accessibilityHint("Saves the complete edited Thought and keeps it selected.")
                        .accessibilityIdentifier("menuBarThought.save")
                }
            } else {
                ContentUnavailableView {
                    Label("No Thoughts", systemImage: "text.bubble")
                } description: {
                    Text("There are no active Thoughts in \(scopeName). Choose another source or capture a Thought first.")
                    if hasUnsavedChanges {
                        Text("Your unsaved edits are preserved, but their Thought is no longer available.")
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
            loadSelectedThought()
            focusEditor()
        }
        .onChange(of: thoughtDestinations) { _, _ in
            _ = selection.reconcile(thoughts: thoughts, projectIDs: projectIDs)
        }
        .onChange(of: thoughtContents) { _, _ in
            guard !hasUnsavedChanges,
                  let thought = thoughts.first(where: { $0.id == loadedThoughtID }) else { return }
            markdown = thought.markdown
            lastSavedMarkdown = thought.markdown
        }
        .onChange(of: projects.map(\.id)) { _, _ in
            _ = selection.reconcile(thoughts: thoughts, projectIDs: projectIDs)
        }
        .onChange(of: selection.thoughtID) { previousID, selectedID in
            guard loadedThoughtID != selectedID else { return }
            if hasUnsavedChanges, previousID == loadedThoughtID {
                selectionNotice = String(localized: "The selected Thought changed because the previous one is no longer available. Your unsaved edits are preserved.")
            } else {
                loadSelectedThought()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusMenuBarThoughtEditor)) { _ in
            focusEditor()
        }
    }

    private var projectIDs: Set<UUID> { Set(projects.map(\.id)) }

    private var populatedProjects: [Project] {
        MenuBarThoughtScope.populatedProjects(from: projects, thoughts: thoughts)
    }

    private var thoughtDestinations: [String] {
        thoughts.map { thought in
            "\(thought.id.uuidString):\(thought.project?.id.uuidString ?? "inbox")"
        }
    }

    private var thoughtContents: [String] {
        thoughts.map { "\($0.id.uuidString):\($0.markdown)" }
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
                guard scope == selection.scope || saveCurrentThought() else { return }
                selection.selectScope(scope, thoughts: thoughts, projectIDs: projectIDs)
                loadSelectedThought()
                focusEditor()
            }
        )
    }

    private var thoughtBinding: Binding<UUID?> {
        Binding(
            get: { selection.thoughtID },
            set: { thoughtID in
                guard let thoughtID,
                      thoughtID == selection.thoughtID || saveCurrentThought() else { return }
                selection.selectThought(thoughtID, thoughts: thoughts, projectIDs: projectIDs)
                loadSelectedThought()
                focusEditor()
            }
        )
    }

    private func thoughtChoiceName(_ thought: Thought) -> String {
        let excerpt = MarkdownDocument(source: thought.markdown).excerpt
            .replacingOccurrences(of: "\n", with: " ")
        let label: String
        if selection.scope == .allThoughts {
            let destination = thought.project?.name ?? String(localized: "Inbox")
            label = "\(excerpt) — \(destination)"
        } else {
            label = excerpt
        }
        guard label.count > 90 else { return label }
        return String(label.prefix(89)) + "…"
    }

    private var hasUnsavedChanges: Bool { markdown != lastSavedMarkdown }

    @discardableResult
    private func saveCurrentThought() -> Bool {
        guard hasUnsavedChanges else {
            errorMessage = nil
            return true
        }
        do {
            try MenuBarThoughtEditor.save(
                markdown,
                loadedThoughtID: loadedThoughtID,
                among: thoughts,
                using: ThoughtRepository(context: modelContext)
            )
            lastSavedMarkdown = markdown
            errorMessage = nil
            selectionNotice = nil
            announceForAccessibility(String(localized: "Thought saved."))
            return true
        } catch {
            errorMessage = (error as? MenuBarThoughtEditError)?.localizedDescription
                ?? MenuBarThoughtEditError.couldNotSave.localizedDescription
            errorFocused = true
            focusEditor()
            return false
        }
    }

    private func loadSelectedThought() {
        guard let thought = selectedThought else {
            if !hasUnsavedChanges {
                markdown = ""
                lastSavedMarkdown = ""
                loadedThoughtID = nil
            }
            return
        }
        markdown = thought.markdown
        lastSavedMarkdown = thought.markdown
        loadedThoughtID = thought.id
        errorMessage = nil
        selectionNotice = nil
    }

    private func focusEditor() {
        guard selectedThought != nil else { return }
        editorFocused = false
        Task { @MainActor in editorFocused = true }
    }
}
