import AppKit
import SwiftData
import SwiftUI

private enum LibrarySelection: Hashable {
    case allThoughts
    case inbox
    case project(UUID)

    var title: String {
        switch self {
        case .allThoughts: "All Thoughts"
        case .inbox: "Inbox"
        case .project: "Project"
        }
    }
}

private struct ProjectEditorContext: Identifiable {
    let id = UUID()
    let project: Project?
}

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Thought> { $0.trashedAt == nil },
        sort: [SortDescriptor(\Thought.createdAt, order: .reverse)]
    ) private var activeThoughts: [Thought]
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var collection: LibrarySelection? = .allThoughts
    @State private var selectedThoughtIDs: Set<UUID> = []
    @State private var editNavigationGuard = ThoughtEditNavigationGuard()
    @State private var projectEditor: ProjectEditorContext?
    @State private var searchText = ""
    @State private var operationMessage: String?
    @State private var operationIsError = false
    @FocusState private var thoughtListFocused: Bool
    @AccessibilityFocusState private var operationFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(selection: guardedCollection) {
                Label("All Thoughts", systemImage: "rectangle.stack")
                    .tag(LibrarySelection.allThoughts)
                    .help("Shows every active Thought, newest first.")
                    .accessibilityHint("Shows every active Thought, newest first.")

                Label("Inbox", systemImage: "tray")
                    .tag(LibrarySelection.inbox)
                    .help("Shows active Thoughts that are not assigned to a Project.")
                    .accessibilityHint("Shows active Thoughts that are not assigned to a Project.")

                Section("Projects") {
                    ForEach(projects) { project in
                        Label(project.name, systemImage: "folder")
                            .tag(LibrarySelection.project(project.id))
                            .help("Shows active Thoughts in \(project.name), newest first.")
                            .accessibilityHint("Shows active Thoughts in this Project, newest first.")
                            .accessibilityIdentifier("project.sidebar.\(project.id.uuidString)")
                            .contextMenu {
                                Button("Rename Project") { beginRename(project) }
                            }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Button("New Project", systemImage: "plus", action: beginCreate)
                        .labelStyle(.iconOnly)
                        .help("Create a Project in the main window.")
                        .accessibilityLabel("New Project")
                        .accessibilityHint("Creates a Project in the main window.")
                        .accessibilityIdentifier("project.create")

                    Button("Rename Project", systemImage: "pencil", action: renameSelectedProject)
                        .labelStyle(.iconOnly)
                        .disabled(selectedProject == nil)
                        .help("Rename the selected Project without changing its order.")
                        .accessibilityLabel("Rename Project")
                        .accessibilityHint("Renames the selected Project without changing its order.")
                        .accessibilityIdentifier("project.rename")
                    Spacer()
                }
                .padding(8)
                .background(.bar)
            }
            .navigationTitle("Thoughtbox")
            .accessibilityIdentifier("library.sidebar")
        } content: {
            Group {
                if visibleThoughts.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: "text.badge.plus")
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        Button("Capture Thought") { AppState.shared.showCapture() }
                            .help("Opens the persistent Draft editor.")
                            .accessibilityHint("Opens the persistent Draft editor.")
                    }
                } else {
                    List(visibleThoughts, selection: guardedSelection) { thought in
                        ThoughtRow(thought: thought, showsDestination: collection == .allThoughts)
                            .tag(thought.id)
                    }
                    .focused($thoughtListFocused)
                    .accessibilityLabel("\(collectionTitle) list")
                    .accessibilityIdentifier("library.thoughts")
                }
            }
            .navigationTitle(collectionTitle)
            .searchable(text: guardedSearchText, placement: .toolbar, prompt: "Search \(collectionTitle)")
            .toolbar {
                Button("Focus Thought List", systemImage: "list.bullet") {
                    thoughtListFocused = true
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut("l", modifiers: .command)
                .help("Move keyboard focus to the Thought list.")
                .accessibilityLabel("Focus Thought List")
                .accessibilityHint("Moves keyboard focus to the Thought list. Command A selects all visible results.")
            }
            .safeAreaInset(edge: .top) {
                if let operationMessage {
                    Label(
                        operationMessage,
                        systemImage: operationIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(operationIsError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
                    .accessibilityLabel(operationMessage)
                    .accessibilityFocused($operationFocused)
                    .accessibilityIdentifier("bulk.status")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedThoughtIDs.isEmpty {
                    bulkMoveBar
                }
            }
        } detail: {
            if let selectedThought {
                ThoughtDetailView(thought: selectedThought, editNavigationGuard: editNavigationGuard)
                    .id(selectedThought.id)
            } else if selectedThoughtIDs.count > 1 {
                ContentUnavailableView(
                    "\(selectedThoughtIDs.count) Thoughts Selected",
                    systemImage: "checklist"
                )
            } else {
                ContentUnavailableView("Select a Thought", systemImage: "doc.text")
            }
        }
        .onAppear { selectNewestThought() }
        .onChange(of: visibleThoughts.map(\.id)) { oldIDs, _ in
            reconcileSelection(selectNewestIfEmpty: oldIDs.isEmpty)
        }
        .onChange(of: searchText) { _, _ in
            announceSearchResults()
        }
        .onChange(of: collection) { _, _ in
            reconcileSelection(forceSingleSelection: true, selectNewestIfEmpty: true)
            announceSearchResults()
        }
        .onChange(of: selectedThoughtIDs) { _, selection in
            announce("\(selection.count) Thought\(selection.count == 1 ? "" : "s") selected")
        }
        .sheet(item: $projectEditor) { editor in
            ProjectEditorSheet(project: editor.project) { savedProject in
                requestCollection(.project(savedProject.id))
            }
        }
    }

    private var collectionThoughts: [Thought] {
        return switch collection ?? .allThoughts {
        case .allThoughts:
            activeThoughts
        case .inbox:
            activeThoughts.filter { $0.project == nil }
        case let .project(projectID):
            activeThoughts.filter { $0.project?.id == projectID }
        }
    }

    private var visibleThoughts: [Thought] {
        ThoughtSearch.filter(collectionThoughts, query: searchText)
    }

    private var selectedThought: Thought? {
        guard selectedThoughtIDs.count == 1, let selectedID = selectedThoughtIDs.first else { return nil }
        return visibleThoughts.first { $0.id == selectedID }
    }

    private var selectedProject: Project? {
        guard case let .project(projectID) = collection else { return nil }
        return projects.first { $0.id == projectID }
    }

    private var collectionTitle: String {
        if let selectedProject { return selectedProject.name }
        return collection?.title ?? "Thoughts"
    }

    private var emptyTitle: String {
        if searchText.containsNonWhitespace { return "No Search Results" }
        return switch collection ?? .allThoughts {
        case .allThoughts: "No Thoughts Yet"
        case .inbox: "Inbox Is Empty"
        case .project: "Project Is Empty"
        }
    }

    private var emptyDescription: String {
        if searchText.containsNonWhitespace {
            return "No active Thoughts in \(collectionTitle) match “\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))”."
        }
        return switch collection ?? .allThoughts {
        case .allThoughts: "Capture a Thought from the menu bar or press Command N."
        case .inbox: "Capture to Inbox or move an existing Thought here."
        case .project: "Capture to this Project or move an existing Thought here."
        }
    }

    private var guardedSelection: Binding<Set<UUID>> {
        Binding(
            get: { selectedThoughtIDs },
            set: { requestedIDs in
                guard requestedIDs == selectedThoughtIDs || editNavigationGuard.canLeaveEditor() else { return }
                selectedThoughtIDs = requestedIDs
            }
        )
    }

    private var guardedCollection: Binding<LibrarySelection?> {
        Binding(
            get: { collection },
            set: { requestedCollection in
                guard requestedCollection == collection || editNavigationGuard.canLeaveEditor() else { return }
                collection = requestedCollection
            }
        )
    }

    private var guardedSearchText: Binding<String> {
        Binding(
            get: { searchText },
            set: { requestedSearch in
                guard requestedSearch == searchText || editNavigationGuard.canLeaveEditor() else { return }
                searchText = requestedSearch
            }
        )
    }

    private var bulkMoveBar: some View {
        HStack {
            Text("\(selectedThoughtIDs.count) selected")
                .accessibilityLabel("\(selectedThoughtIDs.count) Thought\(selectedThoughtIDs.count == 1 ? "" : "s") selected")
                .accessibilityIdentifier("bulk.selection.count")
            Spacer()
            Menu("Move Selected") {
                Button("Inbox") { moveSelection(to: nil) }
                ForEach(projects) { project in
                    Button(project.name) { moveSelection(to: project) }
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .help("Moves every selected active Thought together in one save.")
            .accessibilityHint("Choose Inbox or one Project. All selected Thoughts move atomically.")
            .accessibilityIdentifier("bulk.destination")
        }
        .padding(8)
        .background(.bar)
    }

    private func selectNewestThought(force: Bool = false) {
        guard force || selectedThoughtIDs.isEmpty else { return }
        selectedThoughtIDs = Set(visibleThoughts.prefix(1).map(\.id))
    }

    private func reconcileSelection(
        forceSingleSelection: Bool = false,
        selectNewestIfEmpty: Bool
    ) {
        let visibleIDs = Set(visibleThoughts.map(\.id))
        selectedThoughtIDs.formIntersection(visibleIDs)
        if forceSingleSelection || (selectedThoughtIDs.isEmpty && selectNewestIfEmpty) {
            selectedThoughtIDs = Set(visibleThoughts.prefix(1).map(\.id))
        }
    }

    private func beginCreate() {
        projectEditor = ProjectEditorContext(project: nil)
    }

    private func beginRename(_ project: Project) {
        projectEditor = ProjectEditorContext(project: project)
    }

    private func renameSelectedProject() {
        guard let selectedProject else { return }
        beginRename(selectedProject)
    }

    private func requestCollection(_ requestedCollection: LibrarySelection) {
        guard requestedCollection == collection || editNavigationGuard.canLeaveEditor() else { return }
        collection = requestedCollection
    }

    private func moveSelection(to project: Project?) {
        guard editNavigationGuard.canLeaveEditor() else { return }
        let selectedThoughts = activeThoughts.filter { selectedThoughtIDs.contains($0.id) }
        guard !selectedThoughts.isEmpty else { return }

        do {
            let repository = ThoughtRepository(context: modelContext)
            let changedCount: Int
            if ProcessInfo.processInfo.arguments.contains("--simulate-bulk-move-failure") {
                changedCount = try repository.move(selectedThoughts, to: project) {
                    throw ProjectError.couldNotSave
                }
            } else {
                changedCount = try repository.move(selectedThoughts, to: project)
            }
            let destinationName = project?.name ?? "Inbox"
            operationMessage = if changedCount == 0 {
                "Every selected Thought is already in \(destinationName)."
            } else {
                "Moved \(changedCount) Thought\(changedCount == 1 ? "" : "s") to \(destinationName)."
            }
            operationIsError = false
            focusOperationStatus()
        } catch {
            operationMessage = OrganizationError.bulkMoveFailed.localizedDescription
            operationIsError = true
            focusOperationStatus()
        }
    }

    private func announceSearchResults() {
        guard searchText.containsNonWhitespace else { return }
        announce("\(visibleThoughts.count) search result\(visibleThoughts.count == 1 ? "" : "s") in \(collectionTitle)")
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    private func focusOperationStatus() {
        operationFocused = false
        Task { @MainActor in
            operationFocused = true
        }
    }
}

private struct ThoughtRow: View {
    let thought: Thought
    let showsDestination: Bool

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MarkdownDocument(source: thought.markdown).excerpt)
                .lineLimit(2)
            HStack {
                Text(Self.dateFormatter.string(from: thought.createdAt))
                if showsDestination {
                    Text("·")
                    Text(thought.project?.name ?? "Inbox")
                        .accessibilityIdentifier("thought.destination.\(thought.id.uuidString)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thought created \(Self.dateFormatter.string(from: thought.createdAt)), in \(thought.project?.name ?? "Inbox")")
        .accessibilityValue(thought.markdown)
    }
}

private struct ProjectEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var nameFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @State private var name: String
    @State private var errorMessage: String?

    let project: Project?
    let onSaved: (Project) -> Void

    init(project: Project?, onSaved: @escaping (Project) -> Void) {
        self.project = project
        self.onSaved = onSaved
        _name = State(initialValue: project?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(project == nil ? "New Project" : "Rename Project")
                .font(.title2.weight(.semibold))

            TextField("Project name", text: $name)
                .focused($nameFocused)
                .accessibilityLabel("Project name")
                .accessibilityHint("Names are trimmed and compared without regard to capitalization.")
                .accessibilityIdentifier("project.name")
                .onSubmit(save)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Project error: \(errorMessage)")
                    .accessibilityIdentifier("project.error")
                    .accessibilityFocused($errorFocused)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(project == nil ? "Create Project" : "Save Name", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!name.containsNonWhitespace)
                    .accessibilityHint("Saves the trimmed Project name if it is unique.")
                    .accessibilityIdentifier("project.save")
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { nameFocused = true }
    }

    private func save() {
        errorMessage = nil
        do {
            let repository = ThoughtRepository(context: modelContext)
            let savedProject: Project
            if let project {
                try repository.renameProject(project, to: name)
                savedProject = project
            } else {
                savedProject = try repository.createProject(name: name)
            }
            onSaved(savedProject)
            dismiss()
        } catch {
            if let projectError = error as? ProjectError {
                errorMessage = projectError.localizedDescription
            } else {
                errorMessage = ProjectError.couldNotSave.localizedDescription
            }
            errorFocused = true
            nameFocused = true
        }
    }
}
