import SwiftData
import SwiftUI

private enum LibraryCollection: String, CaseIterable, Identifiable {
    case allThoughts = "All Thoughts"
    case inbox = "Inbox"

    var id: Self { self }
    var presentation: (systemImage: String, help: String) {
        switch self {
        case .allThoughts:
            ("rectangle.stack", "Shows every active Thought, newest first.")
        case .inbox:
            ("tray", "Shows Thoughts that are not assigned to a Project.")
        }
    }
}

struct MainView: View {
    @Query(sort: \Thought.createdAt, order: .reverse) private var thoughts: [Thought]
    @State private var collection: LibraryCollection? = .allThoughts
    @State private var selectedThoughtID: UUID?
    @State private var editNavigationGuard = ThoughtEditNavigationGuard()

    var body: some View {
        NavigationSplitView {
            List(LibraryCollection.allCases, selection: $collection) { item in
                Label(item.rawValue, systemImage: item.presentation.systemImage)
                    .tag(item)
                    .help(item.presentation.help)
                    .accessibilityHint(item.presentation.help)
            }
            .navigationTitle("Thoughtbox")
            .accessibilityIdentifier("library.sidebar")
        } content: {
            Group {
                if thoughts.isEmpty {
                    ContentUnavailableView {
                        Label("No Thoughts Yet", systemImage: "text.badge.plus")
                    } description: {
                        Text("Capture a Thought from the menu bar or press Command N.")
                    } actions: {
                        Button("Capture Thought") { AppState.shared.showCapture() }
                            .help("Opens the persistent Draft editor.")
                            .accessibilityHint("Opens the persistent Draft editor.")
                    }
                } else {
                    List(thoughts, selection: guardedSelection) { thought in
                        ThoughtRow(thought: thought)
                            .tag(thought.id)
                    }
                    .accessibilityLabel("\(collection?.rawValue ?? "Thoughts") list")
                    .accessibilityIdentifier("library.thoughts")
                }
            }
            .navigationTitle(collection?.rawValue ?? "Thoughts")
        } detail: {
            if let selectedThought {
                ThoughtDetailView(thought: selectedThought, editNavigationGuard: editNavigationGuard)
                    .id(selectedThought.id)
            } else {
                ContentUnavailableView("Select a Thought", systemImage: "doc.text")
            }
        }
        .onAppear(perform: selectNewestThought)
        .onChange(of: thoughts.map(\.id)) { _, _ in selectNewestThought() }
    }

    private var selectedThought: Thought? {
        thoughts.first { $0.id == selectedThoughtID }
    }

    private var guardedSelection: Binding<UUID?> {
        Binding(
            get: { selectedThoughtID },
            set: { requestedID in
                guard requestedID == selectedThoughtID || editNavigationGuard.canLeaveEditor() else { return }
                selectedThoughtID = requestedID
            }
        )
    }

    private func selectNewestThought() {
        guard selectedThought == nil else { return }
        selectedThoughtID = thoughts.first?.id
    }

}

private struct ThoughtRow: View {
    let thought: Thought

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
            Text(Self.dateFormatter.string(from: thought.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thought created \(Self.dateFormatter.string(from: thought.createdAt))")
        .accessibilityValue(thought.markdown)
    }
}
