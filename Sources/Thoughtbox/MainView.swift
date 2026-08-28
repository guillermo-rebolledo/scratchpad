import AppKit
import SwiftData
import SwiftUI

private enum LibrarySelection: Hashable {
    case allThoughts
    case inbox
    case project(UUID)
    case trash

    var title: String {
        switch self {
        case .allThoughts: String(localized: "All Thoughts")
        case .inbox: String(localized: "Inbox")
        case .project: String(localized: "Project")
        case .trash: String(localized: "Trash")
        }
    }
}

private struct ProjectEditorContext: Identifiable {
    let id = UUID()
    let project: Project?
}

private struct ProjectDeletionConfirmation {
    let projectID: UUID
    let projectName: String
    let trashedThoughtCount: Int
}

private struct SimulatedExportFailure: Error {}

struct ProjectCommandActions {
    let canModifySelectedProject: Bool
    let create: () -> Void
    let rename: () -> Void
    let delete: () -> Void
}

struct ProjectCommandActionsKey: FocusedValueKey {
    typealias Value = ProjectCommandActions
}

extension FocusedValues {
    var projectCommandActions: ProjectCommandActions? {
        get { self[ProjectCommandActionsKey.self] }
        set { self[ProjectCommandActionsKey.self] = newValue }
    }
}

struct ThoughtSelectionCommandActions {
    let selectionCount: Int
    let isTrash: Bool
    let destinations: [ThoughtDestinationCommand]
    let move: (ThoughtDestination) -> Void
    let trash: () -> Void
    let restore: () -> Void
    let deletePermanently: () -> Void
    let exportTrash: () -> Void
}

struct ThoughtSelectionCommandActionsKey: FocusedValueKey {
    typealias Value = ThoughtSelectionCommandActions
}

extension FocusedValues {
    var thoughtSelectionCommandActions: ThoughtSelectionCommandActions? {
        get { self[ThoughtSelectionCommandActionsKey.self] }
        set { self[ThoughtSelectionCommandActionsKey.self] = newValue }
    }
}

enum ExportAccessibility {
    static let label = String(localized: "Export")
    static let hint = String(localized: "Choose Export All or export the selected trashed Thoughts.")
}

struct LibraryColumnWidth {
    let minimum: CGFloat
    let ideal: CGFloat
    let maximum: CGFloat
}

enum LibraryColumnMetrics {
    static let sidebar = LibraryColumnWidth(minimum: 180, ideal: 220, maximum: 260)
    static let thoughtList = LibraryColumnWidth(minimum: 220, ideal: 280, maximum: 340)
    static let detail = LibraryColumnWidth(minimum: 440, ideal: 560, maximum: 1_200)
}

struct MainView: View {
    @Environment(DraftStore.self) private var draft
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Thought> { $0.trashedAt == nil },
        sort: [SortDescriptor(\Thought.createdAt, order: .reverse)]
    ) private var activeThoughts: [Thought]
    @Query(
        filter: #Predicate<Thought> { $0.trashedAt != nil },
        sort: [SortDescriptor(\Thought.createdAt, order: .reverse)]
    ) private var trashedThoughts: [Thought]
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var collection: LibrarySelection? = .allThoughts
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selectedThoughtIDs: Set<UUID> = []
    @State private var editNavigationGuard = ThoughtEditNavigationGuard()
    @State private var projectEditor: ProjectEditorContext?
    @State private var searchText = ""
    @State private var operationMessage: String?
    @State private var operationIsError = false
    @State private var confirmsPermanentDeletion = false
    @State private var pendingPermanentDeletionIDs: Set<UUID> = []
    @State private var pendingPermanentDeletionSelectionAfterRemoval: Set<UUID>?
    @State private var projectDeletionConfirmation: ProjectDeletionConfirmation?
    @State private var confirmsProjectDeletion = false
    @State private var exportIsRunning = false
    @State private var exportCanBeCancelled = false
    @State private var exportTask: Task<Void, Never>?
    @FocusState private var thoughtListFocused: Bool
    @AccessibilityFocusState private var operationFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: guardedCollection) {
                Label("All Thoughts", systemImage: "rectangle.stack")
                    .tag(LibrarySelection.allThoughts)
                    .help("Shows every active Thought, newest first.")
                    .accessibilityHint("Shows every active Thought, newest first.")
                    .accessibilityIdentifier("library.sidebar.all")

                Label("Inbox", systemImage: "tray")
                    .tag(LibrarySelection.inbox)
                    .help("Shows active Thoughts that are not assigned to a Project.")
                    .accessibilityHint("Shows active Thoughts that are not assigned to a Project.")

                Label("Trash", systemImage: "trash")
                    .tag(LibrarySelection.trash)
                    .help("Shows trashed Thoughts newest first. Trash is retained until you permanently delete it.")
                    .accessibilityHint("Shows trashed Thoughts newest first. Search is scoped to Trash.")
                    .accessibilityIdentifier("trash.sidebar")

                Section("Projects") {
                    ForEach(projects) { project in
                        Label(project.name, systemImage: "folder")
                            .tag(LibrarySelection.project(project.id))
                            .help("Shows active Thoughts in \(project.name), newest first.")
                            .accessibilityHint("Shows active Thoughts in this Project, newest first.")
                            .accessibilityIdentifier("project.sidebar.\(project.id.uuidString)")
                            .contextMenu {
                                Button("Rename Project") { beginRename(project) }
                                    .help("Renames this Project without changing its order.")
                                Button("Delete Project", role: .destructive) {
                                    requestDeleteProject(project)
                                }
                                .help("Deletes this Project only when it contains no active Thoughts.")
                            }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Button("New Project", systemImage: "plus", action: beginCreate)
                        .controlSize(.regular)
                        .help("Create a Project.")
                        .accessibilityLabel("New Project")
                        .accessibilityHint("Creates a Project in the main window.")
                        .accessibilityIdentifier("project.create")
                    Spacer()
                }
                .padding(8)
                .background(.bar)
            }
            .navigationTitle("Thoughtbox")
            .navigationSplitViewColumnWidth(
                min: LibraryColumnMetrics.sidebar.minimum,
                ideal: LibraryColumnMetrics.sidebar.ideal,
                max: LibraryColumnMetrics.sidebar.maximum
            )
        } content: {
            Group {
                if visibleThoughts.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: emptySystemImage)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        emptyActions
                    }
                } else {
                    List(visibleThoughts, selection: guardedSelection) { thought in
                        ThoughtRow(
                            thought: thought,
                            isInTrash: collection == .trash,
                            restoreDestinationName: restoreDestinationName(for: thought)
                        )
                            .tag(thought.id)
                            .swipeActions(edge: .trailing, allowsFullSwipe: collection != .trash) {
                                if collection == .trash {
                                    Button(role: .destructive) {
                                        requestPermanentDeletion(for: thought)
                                    } label: {
                                        Label("Delete Permanently", systemImage: "trash.slash")
                                    }
                                    .accessibilityHint("Opens a confirmation before permanently deleting only this Thought.")
                                    .accessibilityIdentifier("thought.swipe.delete")
                                } else {
                                    Button(role: .destructive) {
                                        trashThought(thought)
                                    } label: {
                                        Label("Move to Trash", systemImage: "trash")
                                    }
                                    .accessibilityHint("Moves only this Thought to Trash. You can restore it later.")
                                    .accessibilityIdentifier("thought.swipe.trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if collection == .trash {
                                    Button {
                                        restoreThought(thought)
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.accentColor)
                                    .accessibilityHint("Restores only this Thought to its former Project when available, otherwise Inbox.")
                                    .accessibilityIdentifier("thought.swipe.restore")
                                }
                            }
                            .contextMenu {
                                if collection != .trash {
                                    Button(role: .destructive) {
                                        trashThought(thought)
                                    } label: {
                                        Label("Move to Trash", systemImage: "trash")
                                    }
                                    .help("Moves this Thought to Trash. You can restore it later.")
                                }
                            }
                    }
                    .focused($thoughtListFocused)
                    .accessibilityLabel("\(collectionTitle) list")
                    .accessibilityIdentifier("library.thoughts")
                }
            }
            .ignoresSafeArea(
                .container,
                edges: columnVisibility == .doubleColumn ? .leading : []
            )
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

                Menu("Export", systemImage: "square.and.arrow.up") {
                    Button("Export All…") { beginExport(scope: .allActive) }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                        .accessibilityHint("Opens the system folder picker and exports every active Thought. Trash is excluded.")
                        .accessibilityIdentifier("export.all")
                    Button("Export Selected Trash…") { beginExport(scope: .selectedTrash) }
                        .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                        .disabled(collection != .trash || selectedThoughtIDs.isEmpty)
                        .accessibilityHint("Available in Trash when one or more Thoughts are selected.")
                        .accessibilityIdentifier("export.selected.trash")
                }
                .disabled(exportIsRunning)
                .help("Export portable canonical Markdown through the system folder picker.")
                .accessibilityLabel(ExportAccessibility.label)
                .accessibilityHint(ExportAccessibility.hint)
                .accessibilityIdentifier("export.menu")
            }
            .safeAreaInset(edge: .top) {
                if let operationMessage {
                    HStack(spacing: 8) {
                        if exportIsRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: operationIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        }
                        Text(operationMessage)
                        Spacer()
                        if exportCanBeCancelled {
                            Button("Cancel Export", role: .cancel, action: cancelExport)
                                .keyboardShortcut(.cancelAction)
                                .help("Stops before the next Markdown file. Files already exported remain in the chosen folder.")
                                .accessibilityHint("Stops the export before its next file and reports how many files were already written.")
                                .accessibilityIdentifier("export.cancel")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .statusMessageStyle(isError: operationIsError)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(operationIsError ? "Library error: \(operationMessage)" : operationMessage)
                    .accessibilityFocused($operationFocused)
                    .accessibilityIdentifier("bulk.status")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if showsSelectionActionBar {
                    selectionActionBar
                }
            }
            .navigationSplitViewColumnWidth(
                min: LibraryColumnMetrics.thoughtList.minimum,
                ideal: LibraryColumnMetrics.thoughtList.ideal,
                max: LibraryColumnMetrics.thoughtList.maximum
            )
        } detail: {
            Group {
                if let selectedThought {
                    ThoughtDetailView(
                        thought: selectedThought,
                        editNavigationGuard: editNavigationGuard,
                        onMoveToTrash: collection == .trash ? nil : { trashSelection() }
                    )
                        .id(selectedThought.id)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("thought.detail")
                } else if selectedThoughtIDs.count > 1 {
                    ContentUnavailableView(
                        "\(selectedThoughtIDs.count) Thoughts Selected",
                        systemImage: "checklist"
                    )
                } else {
                    ContentUnavailableView("Select a Thought", systemImage: "doc.text")
                }
            }
            .navigationSplitViewColumnWidth(
                min: LibraryColumnMetrics.detail.minimum,
                ideal: LibraryColumnMetrics.detail.ideal,
                max: LibraryColumnMetrics.detail.maximum
            )
        }
        .navigationSplitViewStyle(.balanced)
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
            announceForAccessibility(
                String(localized: "\(selection.count) Thought\(selection.count == 1 ? "" : "s") selected")
            )
        }
        .focusedSceneValue(\.projectCommandActions, focusedProjectCommandActions)
        .focusedSceneValue(\.thoughtSelectionCommandActions, focusedThoughtSelectionCommandActions)
        .sheet(item: $projectEditor) { editor in
            ProjectEditorSheet(project: editor.project) { savedProject in
                if editor.project == nil || collection == .project(savedProject.id) {
                    requestCollection(.project(savedProject.id))
                }
            }
        }
        .confirmationDialog(
            permanentDeletionTitle,
            isPresented: $confirmsPermanentDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive, action: permanentlyDeleteConfirmed)
                .accessibilityIdentifier("trash.delete.confirm")
            Button("Keep in Trash", role: .cancel) {}
        } message: {
            Text("This cannot be undone. The selected Thought\(pendingPermanentDeletionIDs.count == 1 ? "" : "s") will be removed from this Mac.")
        }
        .confirmationDialog(
            projectDeletionTitle,
            isPresented: $confirmsProjectDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive, action: deleteProjectConfirmed)
                .accessibilityIdentifier("project.delete.confirm")
            Button("Keep Project", role: .cancel) {}
        } message: {
            Text(projectDeletionMessage)
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
        case .trash:
            trashedThoughts
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

    private var showsSelectionActionBar: Bool {
        guard !selectedThoughtIDs.isEmpty else { return false }
        return collection == .trash || selectedThoughtIDs.count > 1
    }

    private var focusedProjectCommandActions: ProjectCommandActions {
        ProjectCommandActions(
            canModifySelectedProject: selectedProject != nil,
            create: beginCreate,
            rename: renameSelectedProject,
            delete: requestDeleteSelectedProject
        )
    }

    private var focusedThoughtSelectionCommandActions: ThoughtSelectionCommandActions {
        let selected = collection == .trash
            ? trashedThoughts.filter { selectedThoughtIDs.contains($0.id) }
            : activeThoughts.filter { selectedThoughtIDs.contains($0.id) }
        let commonProjectID = selected.first?.project?.id
        let hasCommonDestination = !selected.isEmpty && selected.allSatisfy { $0.project?.id == commonProjectID }

        return ThoughtSelectionCommandActions(
            selectionCount: selected.count,
            isTrash: collection == .trash,
            destinations: ThoughtDestinationCommand.options(
                projects: projects,
                currentProjectID: commonProjectID,
                marksCurrent: hasCommonDestination
            ),
            move: { destination in
                moveSelection(to: destination.project(in: projects))
            },
            trash: trashSelection,
            restore: restoreSelection,
            deletePermanently: requestPermanentDeletion,
            exportTrash: { beginExport(scope: .selectedTrash) }
        )
    }

    private var permanentDeletionTitle: String {
        let count = pendingPermanentDeletionIDs.count
        return count == 1
            ? String(localized: "Permanently delete this Thought?")
            : String(localized: "Permanently delete \(count) Thoughts?")
    }

    private var projectDeletionTitle: String {
        guard let confirmation = projectDeletionConfirmation else {
            return String(localized: "Delete this Project?")
        }
        return String(localized: "Delete “\(confirmation.projectName)”?")
    }

    private var projectDeletionMessage: String {
        guard let confirmation = projectDeletionConfirmation else {
            return String(localized: "This cannot be undone.")
        }
        guard confirmation.trashedThoughtCount > 0 else {
            return String(localized: "The empty Project will be permanently deleted. This cannot be undone.")
        }
        let count = confirmation.trashedThoughtCount
        return String(localized: "\(count) Thought\(count == 1 ? "" : "s") in Trash formerly belonged to this Project. If restored later, \(count == 1 ? "it" : "they") will go to Inbox. The Project deletion cannot be undone.")
    }

    private var collectionTitle: String {
        if let selectedProject { return selectedProject.name }
        return collection?.title ?? String(localized: "Thoughts")
    }

    private var emptyTitle: String {
        if searchText.containsNonWhitespace { return String(localized: "No Search Results") }
        return switch collection ?? .allThoughts {
        case .allThoughts: String(localized: "No Thoughts Yet")
        case .inbox: String(localized: "Inbox Is Empty")
        case .project: String(localized: "Project Is Empty")
        case .trash: String(localized: "Trash Is Empty")
        }
    }

    private var emptyDescription: String {
        if searchText.containsNonWhitespace {
            let kind = collection == .trash ? String(localized: "trashed") : String(localized: "active")
            return String(localized: "No \(kind) Thoughts in \(collectionTitle) match “\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))”.")
        }
        return switch collection ?? .allThoughts {
        case .allThoughts: String(localized: "Capture a Thought from the menu bar or press Command N.")
        case .inbox: String(localized: "Capture to Inbox or move an existing Thought here.")
        case .project: String(localized: "Capture to this Project or move an existing Thought here.")
        case .trash: String(localized: "Thoughts remain here until you restore or permanently delete them.")
        }
    }

    private var emptySystemImage: String {
        if searchText.containsNonWhitespace { return "magnifyingglass" }
        return collection == .trash ? "trash" : "text.badge.plus"
    }

    private func restoreDestinationName(for thought: Thought) -> String? {
        guard thought.trashedAt != nil else { return nil }
        guard let formerProjectID = thought.formerProjectID else { return String(localized: "Inbox") }
        return projects.first(where: { $0.id == formerProjectID })?.name ?? String(localized: "Inbox")
    }

    @ViewBuilder
    private var emptyActions: some View {
        if searchText.containsNonWhitespace {
            Button("Clear Search", action: clearSearch)
                .help("Clears the current query and returns to every Thought in this collection.")
                .accessibilityHint("Clears the current query and returns to every Thought in this collection.")
                .accessibilityIdentifier("library.empty.clearSearch")
        } else {
            switch collection ?? .allThoughts {
            case .allThoughts:
                Button("Capture Thought", action: showCapture)
                    .help("Opens the persistent Draft editor.")
                    .accessibilityHint("Opens the persistent Draft editor. Any saved Thought appears in All Thoughts.")
                    .accessibilityIdentifier("library.empty.capture")
            case .inbox:
                Button("Capture to Inbox") { showCapture(in: nil) }
                    .help("Opens the persistent Draft editor preselected to Inbox.")
                    .accessibilityHint("Opens the persistent Draft editor and preserves Inbox as its destination.")
                    .accessibilityIdentifier("library.empty.capture")
            case .project:
                if let selectedProject {
                    Button("Capture to \(selectedProject.name)") { showCapture(in: selectedProject.id) }
                        .help("Opens the persistent Draft editor preselected to this Project.")
                        .accessibilityHint("Opens the persistent Draft editor and preserves this Project as its destination.")
                        .accessibilityIdentifier("library.empty.capture")
                }
            case .trash:
                EmptyView()
            }
        }
    }

    private func showCapture() {
        AppState.shared.showCapture()
    }

    private func showCapture(in projectID: UUID?) {
        draft.prepareForCapture(in: projectID)
        AppState.shared.showCapture()
    }

    private func clearSearch() {
        guard editNavigationGuard.canLeaveEditor() else { return }
        searchText = ""
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

    @ViewBuilder
    private var selectionActionBar: some View {
        if collection == .trash {
            trashActionBar
        } else {
            activeActionBar
        }
    }

    private var activeActionBar: some View {
        HStack(spacing: 8) {
            Text("\(selectedThoughtIDs.count) selected")
                .accessibilityLabel("\(selectedThoughtIDs.count) Thought\(selectedThoughtIDs.count == 1 ? "" : "s") selected")
                .accessibilityIdentifier("bulk.selection.count")
            Spacer()
            Menu("Move", systemImage: "folder") {
                Button("Inbox") { moveSelection(to: nil) }
                ForEach(projects) { project in
                    Button(project.name) { moveSelection(to: project) }
                }
            }
            .controlSize(.regular)
            .help("Moves every selected active Thought together in one save.")
            .accessibilityLabel("Move Selected")
            .accessibilityHint("Choose Inbox or one Project. All selected Thoughts move atomically.")
            .accessibilityIdentifier("bulk.destination")

            Button(role: .destructive, action: trashSelection) {
                Label("Move to Trash", systemImage: "trash")
            }
                .labelStyle(.iconOnly)
                .controlSize(.regular)
                .help("Moves every selected Thought to Trash immediately in one save.")
                .accessibilityLabel("Move to Trash")
                .accessibilityValue("\(selectedThoughtIDs.count) Thoughts selected")
                .accessibilityHint("Moves all selected Thoughts to Trash without confirmation. You can restore them later.")
                .accessibilityIdentifier("trash.move")
        }
        .padding(8)
        .background(.bar)
    }

    private var trashActionBar: some View {
        HStack(spacing: 8) {
            Text("\(selectedThoughtIDs.count) selected")
                .accessibilityLabel("\(selectedThoughtIDs.count) Thought\(selectedThoughtIDs.count == 1 ? "" : "s") selected in Trash")
                .accessibilityIdentifier("bulk.selection.count")
            Spacer()
            Button("Restore", systemImage: "arrow.uturn.backward", action: restoreSelection)
                .controlSize(.regular)
                .help("Restores each selected Thought to its former Project when available, otherwise Inbox.")
                .accessibilityLabel("Restore Selected")
                .accessibilityHint("Restores all selected Thoughts atomically. Missing Projects fall back to Inbox.")
                .accessibilityIdentifier("trash.restore")
            Button("Delete", systemImage: "trash.slash", role: .destructive, action: requestPermanentDeletion)
                .controlSize(.regular)
                .help("Always asks for confirmation before permanently deleting the selected Thoughts.")
                .accessibilityLabel("Delete Permanently")
                .accessibilityHint("Opens a confirmation that states how many Thoughts will be permanently deleted.")
                .accessibilityIdentifier("trash.delete")
            Button("Export Selected", systemImage: "square.and.arrow.up") { beginExport(scope: .selectedTrash) }
                .labelStyle(.iconOnly)
                .controlSize(.regular)
                .disabled(exportIsRunning)
                .help("Exports only the selected trashed Thoughts without restoring them.")
                .accessibilityLabel("Export Selected Trash")
                .accessibilityValue("\(selectedThoughtIDs.count) Thought\(selectedThoughtIDs.count == 1 ? "" : "s") selected in Trash")
                .accessibilityHint("Opens the system folder picker, then exports the selected trashed Thoughts as portable Markdown.")
                .accessibilityIdentifier("export.selected.trash.button")
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
            let destinationName = project?.name ?? String(localized: "Inbox")
            operationMessage = if changedCount == 0 {
                String(localized: "Every selected Thought is already in \(destinationName).")
            } else {
                String(localized: "Moved \(changedCount) Thought\(changedCount == 1 ? "" : "s") to \(destinationName).")
            }
            operationIsError = false
            focusOperationStatus()
        } catch {
            operationMessage = OrganizationError.bulkMoveFailed.localizedDescription
            operationIsError = true
            focusOperationStatus()
        }
    }

    private func trashSelection() {
        let selected = activeThoughts.filter { selectedThoughtIDs.contains($0.id) }
        trashThoughts(selected)
    }

    private func trashThought(_ thought: Thought) {
        trashThoughts([thought], selectionAfterRemoval: selectionAfterRemovingRow(thought))
    }

    private func trashThoughts(
        _ selected: [Thought],
        selectionAfterRemoval: Set<UUID>? = nil
    ) {
        guard editNavigationGuard.canLeaveEditor() else { return }
        guard !selected.isEmpty else { return }

        do {
            let repository = ThoughtRepository(context: modelContext)
            let count: Int
            if ProcessInfo.processInfo.arguments.contains("--simulate-trash-failure") {
                count = try repository.trash(selected) { throw TrashError.trashFailed }
            } else {
                count = try repository.trash(selected)
            }
            if let selectionAfterRemoval {
                selectedThoughtIDs = selectionAfterRemoval
            }
            operationMessage = String(localized: "Moved \(count) Thought\(count == 1 ? "" : "s") to Trash.")
            operationIsError = false
            focusOperationStatus()
        } catch {
            operationMessage = TrashError.trashFailed.localizedDescription
            operationIsError = true
            focusOperationStatus()
        }
    }

    private func selectionAfterRemovingRow(_ thought: Thought) -> Set<UUID> {
        guard selectedThoughtIDs.contains(thought.id) else { return selectedThoughtIDs }

        var remainingSelection = selectedThoughtIDs
        remainingSelection.remove(thought.id)
        guard remainingSelection.isEmpty,
              let removedIndex = visibleThoughts.firstIndex(where: { $0.id == thought.id }) else {
            return remainingSelection
        }

        let nextIndex = visibleThoughts.index(after: removedIndex)
        if nextIndex < visibleThoughts.endIndex {
            return [visibleThoughts[nextIndex].id]
        }
        if removedIndex > visibleThoughts.startIndex {
            return [visibleThoughts[visibleThoughts.index(before: removedIndex)].id]
        }
        return []
    }

    private func restoreSelection() {
        let selected = trashedThoughts.filter { selectedThoughtIDs.contains($0.id) }
        restoreThoughts(selected)
    }

    private func restoreThought(_ thought: Thought) {
        restoreThoughts([thought], selectionAfterRemoval: selectionAfterRemovingRow(thought))
    }

    private func restoreThoughts(
        _ selected: [Thought],
        selectionAfterRemoval: Set<UUID>? = nil
    ) {
        guard editNavigationGuard.canLeaveEditor() else { return }
        guard !selected.isEmpty else { return }

        do {
            let repository = ThoughtRepository(context: modelContext)
            let result: RestoreResult
            if ProcessInfo.processInfo.arguments.contains("--simulate-restore-failure") {
                result = try repository.restore(selected) { throw TrashError.restoreFailed }
            } else {
                result = try repository.restore(selected)
            }
            if let selectionAfterRemoval {
                selectedThoughtIDs = selectionAfterRemoval
            }
            if result.inboxFallbackCount == 0 {
                operationMessage = String(localized: "Restored \(result.restoredCount) Thought\(result.restoredCount == 1 ? "" : "s") to \(result.restoredCount == 1 ? "its" : "their") former destination.")
            } else {
                operationMessage = String(localized: "Restored \(result.restoredCount) Thought\(result.restoredCount == 1 ? "" : "s"). \(result.inboxFallbackCount) went to Inbox because \(result.inboxFallbackCount == 1 ? "its former Project no longer exists" : "their former Projects no longer exist").")
            }
            operationIsError = false
            focusOperationStatus()
        } catch {
            operationMessage = TrashError.restoreFailed.localizedDescription
            operationIsError = true
            focusOperationStatus()
        }
    }

    private func requestPermanentDeletion() {
        guard editNavigationGuard.canLeaveEditor() else { return }
        pendingPermanentDeletionIDs = selectedThoughtIDs.intersection(Set(trashedThoughts.map(\.id)))
        pendingPermanentDeletionSelectionAfterRemoval = nil
        confirmsPermanentDeletion = !pendingPermanentDeletionIDs.isEmpty
    }

    private func requestPermanentDeletion(for thought: Thought) {
        guard editNavigationGuard.canLeaveEditor(), thought.trashedAt != nil else { return }
        pendingPermanentDeletionIDs = [thought.id]
        pendingPermanentDeletionSelectionAfterRemoval = selectionAfterRemovingRow(thought)
        confirmsPermanentDeletion = true
    }

    private func permanentlyDeleteConfirmed() {
        let deleting = trashedThoughts.filter { pendingPermanentDeletionIDs.contains($0.id) }
        let requestedCount = deleting.count
        guard requestedCount > 0 else { return }

        do {
            let repository = ThoughtRepository(context: modelContext)
            let count: Int
            if ProcessInfo.processInfo.arguments.contains("--simulate-permanent-delete-failure") {
                count = try repository.permanentlyDelete(deleting) { throw TrashError.permanentDeletionFailed }
            } else {
                count = try repository.permanentlyDelete(deleting)
            }
            if let pendingPermanentDeletionSelectionAfterRemoval {
                selectedThoughtIDs = pendingPermanentDeletionSelectionAfterRemoval
            } else {
                selectedThoughtIDs.subtract(pendingPermanentDeletionIDs)
            }
            pendingPermanentDeletionIDs = []
            pendingPermanentDeletionSelectionAfterRemoval = nil
            operationMessage = String(localized: "Permanently deleted \(count) Thought\(count == 1 ? "" : "s").")
            operationIsError = false
            focusOperationStatus()
        } catch {
            operationMessage = TrashError.permanentDeletionFailed.localizedDescription
            operationIsError = true
            focusOperationStatus()
        }
    }

    private func requestDeleteSelectedProject() {
        guard let project = selectedProject, editNavigationGuard.canLeaveEditor() else { return }
        requestDeleteProject(project)
    }

    private func requestDeleteProject(_ project: Project) {
        guard editNavigationGuard.canLeaveEditor() else { return }
        do {
            let impact = try ThoughtRepository(context: modelContext).projectDeletionImpact(for: project)
            guard impact.activeThoughtCount == 0 else {
                throw TrashError.projectContainsActiveThoughts(count: impact.activeThoughtCount)
            }
            projectDeletionConfirmation = ProjectDeletionConfirmation(
                projectID: project.id,
                projectName: project.name,
                trashedThoughtCount: impact.trashedThoughtCount
            )
            confirmsProjectDeletion = true
        } catch let error as TrashError {
            operationMessage = error.localizedDescription
            operationIsError = true
            focusOperationStatus()
        } catch {
            operationMessage = TrashError.projectDeletionFailed.localizedDescription
            operationIsError = true
            focusOperationStatus()
        }
    }

    private func deleteProjectConfirmed() {
        guard let confirmation = projectDeletionConfirmation,
              let project = projects.first(where: { $0.id == confirmation.projectID }) else { return }
        do {
            let result = try ThoughtRepository(context: modelContext).deleteProject(project, draft: draft)
            if collection == .project(confirmation.projectID) {
                collection = .inbox
                selectedThoughtIDs = []
            }
            projectDeletionConfirmation = nil
            operationMessage = if result.draftDestinationReset {
                String(localized: "Deleted \(confirmation.projectName). Your Draft is intact and its destination is now Inbox.")
            } else {
                String(localized: "Deleted \(confirmation.projectName).")
            }
            operationIsError = false
            focusOperationStatus()
        } catch let error as TrashError {
            operationMessage = error.localizedDescription
            operationIsError = true
            focusOperationStatus()
        } catch {
            operationMessage = TrashError.projectDeletionFailed.localizedDescription
            operationIsError = true
            focusOperationStatus()
        }
    }

    private func beginExport(scope: ThoughtExportScope) {
        guard !exportIsRunning, editNavigationGuard.canLeaveEditor() else { return }
        let source: [Thought]
        switch scope {
        case .allActive:
            source = activeThoughts
        case .selectedTrash:
            source = trashedThoughts.filter { selectedThoughtIDs.contains($0.id) }
        }
        guard !source.isEmpty else {
            operationMessage = scope == .allActive
                ? String(localized: "There are no active Thoughts to export. Trash is excluded from Export All.")
                : String(localized: "Select one or more Thoughts in Trash before exporting.")
            operationIsError = true
            focusOperationStatus()
            return
        }

        let items = source.map(ThoughtExportItem.init(thought:))
        exportIsRunning = true
        operationMessage = String(localized: "Choose a destination for \(items.count) Thought\(items.count == 1 ? "" : "s")…")
        operationIsError = false
        focusOperationStatus()
        exportTask = Task { @MainActor in
            let destination = await SystemExportDestinationPicker().chooseDestination()
            guard let destination else {
                exportIsRunning = false
                exportCanBeCancelled = false
                exportTask = nil
                operationMessage = String(localized: "Export canceled. No files were written.")
                operationIsError = false
                focusOperationStatus()
                return
            }
            guard !Task.isCancelled else {
                exportIsRunning = false
                exportCanBeCancelled = false
                exportTask = nil
                operationMessage = String(localized: "Export canceled. No files were written.")
                operationIsError = false
                focusOperationStatus()
                return
            }

            exportCanBeCancelled = true
            operationMessage = String(localized: "Exporting \(items.count) Thought\(items.count == 1 ? "" : "s")…")
            operationIsError = false
            focusOperationStatus()
            let simulateFailure = ProcessInfo.processInfo.arguments.contains("--simulate-export-write-failure")
            let worker = Task.detached(priority: .userInitiated) {
                let plan = MarkdownExportPlanner().makePlan(for: items, scope: scope)
                guard !Task.isCancelled else {
                    return MarkdownExportOutcome.completed(.init(
                        writtenRelativePaths: [],
                        failures: [],
                        wasCancelled: true
                    ))
                }
                if simulateFailure {
                    let writer = MarkdownExportWriter { _, _ in throw SimulatedExportFailure() }
                    return MarkdownExportService(writer: writer).export(plan, to: destination)
                }
                return MarkdownExportService().export(plan, to: destination)
            }
            let outcome = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            exportIsRunning = false
            exportCanBeCancelled = false
            exportTask = nil
            presentExportOutcome(outcome, destination: destination, requestedCount: items.count)
        }
    }

    private func cancelExport() {
        guard exportCanBeCancelled else { return }
        exportCanBeCancelled = false
        exportTask?.cancel()
        operationMessage = String(localized: "Canceling export safely…")
        operationIsError = false
        focusOperationStatus()
    }

    private func presentExportOutcome(
        _ outcome: MarkdownExportOutcome,
        destination: URL,
        requestedCount: Int
    ) {
        switch outcome {
        case .cancelled:
            operationMessage = String(localized: "Export canceled. No files were written.")
            operationIsError = false
        case let .completed(result) where result.wasCancelled:
            let failureCopy = result.failures.isEmpty
                ? ""
                : String(localized: " \(result.failures.count) output\(result.failures.count == 1 ? " failed" : "s failed") before cancellation.")
            operationMessage = String(localized: "Export canceled after writing \(result.writtenRelativePaths.count) of \(requestedCount) Thought\(requestedCount == 1 ? "" : "s"). Files already exported remain in \(destination.lastPathComponent).\(failureCopy)")
            operationIsError = !result.failures.isEmpty
        case let .completed(result) where result.isFullSuccess:
            operationMessage = String(localized: "Exported \(result.writtenRelativePaths.count) Thought\(result.writtenRelativePaths.count == 1 ? "" : "s") to \(destination.lastPathComponent).")
            operationIsError = false
        case let .completed(result):
            let shownPaths = result.failures.prefix(3).map(\.relativePath).joined(separator: ", ")
            let remainingCount = max(0, result.failures.count - 3)
            let remaining = remainingCount == 0 ? "" : String(localized: ", and \(remainingCount) more")
            operationMessage = String(localized: "Exported \(result.writtenRelativePaths.count) of \(requestedCount) Thought\(requestedCount == 1 ? "" : "s"). Could not write: \(shownPaths)\(remaining). No existing files were overwritten.")
            operationIsError = true
        }
        focusOperationStatus()
    }

    private func announceSearchResults() {
        guard searchText.containsNonWhitespace else { return }
        announceForAccessibility(
            String(localized: "\(visibleThoughts.count) search result\(visibleThoughts.count == 1 ? "" : "s") in \(collectionTitle)")
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
    let isInTrash: Bool
    let restoreDestinationName: String?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var creationDate: String {
        Self.dateFormatter.string(from: thought.createdAt)
    }

    private var contextTitle: String {
        if isInTrash { return String(localized: "Trash") }
        return thought.project?.name ?? String(localized: "Inbox")
    }

    private var contextSystemImage: String {
        if isInTrash { return "trash" }
        return thought.project == nil ? "tray" : "folder"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MarkdownDocument(source: thought.markdown).excerpt)
                .font(.body)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Label(creationDate, systemImage: "clock")
                    .lineLimit(1)
                    .layoutPriority(1)

                Label(contextTitle, systemImage: contextSystemImage)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("thought.destination.\(thought.id.uuidString)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityContext)
        .accessibilityValue(thought.markdown)
    }

    private var accessibilityContext: String {
        if isInTrash {
            return "Thought created \(creationDate), in Trash, restores to \(restoreDestinationName ?? String(localized: "Inbox"))"
        }
        return "Thought created \(creationDate), in \(contextTitle)"
    }
}

private struct ProjectEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var nameFocused: Bool
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
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    DispatchQueue.main.async {
                        save()
                    }
                    return .handled
                }

            if let errorMessage {
                AccessibleErrorMessage(
                    message: errorMessage,
                    accessibilityLabel: "Project error: \(errorMessage)",
                    identifier: "project.error"
                )
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(project == nil ? "Create Project" : "Save Name", action: save)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Saves the trimmed Project name if it is unique.")
                    .accessibilityIdentifier("project.save")
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear(perform: focusName)
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
            if let errorMessage {
                announceForAccessibility(errorMessage, priority: .high)
            }
            focusName()
        }
    }

    private func focusName() {
        nameFocused = false
        Task { @MainActor in
            nameFocused = true
        }
    }
}
