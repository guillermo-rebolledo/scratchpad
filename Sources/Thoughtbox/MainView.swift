import SwiftData
import SwiftUI

private enum LibraryCollection: String, CaseIterable, Identifiable {
    case allThoughts = "All Thoughts"
    case inbox = "Inbox"

    var id: Self { self }
    var systemImage: String {
        switch self {
        case .allThoughts: "rectangle.stack"
        case .inbox: "tray"
        }
    }
}

struct MainView: View {
    @Query(sort: \Thought.createdAt, order: .reverse) private var thoughts: [Thought]
    @State private var collection: LibraryCollection? = .allThoughts
    @State private var selectedThoughtID: UUID?

    var body: some View {
        NavigationSplitView {
            List(LibraryCollection.allCases, selection: $collection) { item in
                Label(item.rawValue, systemImage: item.systemImage)
                    .tag(item)
                    .help(help(for: item))
                    .accessibilityHint(help(for: item))
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
                    List(thoughts, selection: $selectedThoughtID) { thought in
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
                ScrollView {
                    Text(selectedThought.markdown)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .accessibilityLabel("Thought Markdown")
                        .accessibilityValue(selectedThought.markdown)
                }
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

    private func selectNewestThought() {
        guard selectedThought == nil else { return }
        selectedThoughtID = thoughts.first?.id
    }

    private func help(for collection: LibraryCollection) -> String {
        switch collection {
        case .allThoughts: "Shows every active Thought, newest first."
        case .inbox: "Shows Thoughts that are not assigned to a Project."
        }
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
            Text(thought.markdown)
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
