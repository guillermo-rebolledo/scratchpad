import Foundation
import SwiftData
import Testing
@testable import Thoughtbox

@MainActor
struct UpdatePreservationTests {
    @Test("Relaunching a newer build preserves every local data category")
    func relaunchPreservesLocalData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtboxUpdatePreservation-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suiteName = "ThoughtboxUpdatePreservation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appending(path: "Thoughtbox.store")

        let firstContainer = try makeContainer(at: storeURL)
        let firstRepository = ThoughtRepository(container: firstContainer)
        let project = try firstRepository.createProject(name: "Durable Project")
        _ = try firstRepository.capture(markdown: "Inbox survives")
        _ = try firstRepository.capture(markdown: "Project Thought survives", project: project)
        let trashed = try firstRepository.capture(markdown: "Trash survives", project: project)
        try firstRepository.trash(trashed)

        let firstDraft = DraftStore(defaults: defaults)
        firstDraft.markdown = "Draft survives"
        firstDraft.projectID = project.id
        let firstSettings = SettingsModel(
            defaults: defaults,
            loginItemService: PreservationLoginItemService()
        )
        firstSettings.connectShortcutRegistration { _ in }
        let shortcut = CaptureShortcut(keyCode: 38, modifiers: [.control, .option])
        firstSettings.assignShortcut(shortcut)

        let relaunchedContainer = try makeContainer(at: storeURL)
        let relaunchedRepository = ThoughtRepository(container: relaunchedContainer)
        let relaunchedProjects = try relaunchedRepository.allProjects()
        let relaunchedDraft = DraftStore(defaults: defaults)
        let relaunchedSettings = SettingsModel(
            defaults: defaults,
            loginItemService: PreservationLoginItemService()
        )

        #expect(relaunchedProjects.map(\.name) == ["Durable Project"])
        #expect(try relaunchedRepository.inboxThoughts().map(\.markdown) == ["Inbox survives"])
        #expect(try relaunchedRepository.thoughts(in: relaunchedProjects[0]).map(\.markdown) == ["Project Thought survives"])
        let relaunchedTrash = try relaunchedRepository.trashedThoughts()
        #expect(relaunchedTrash.map(\.markdown) == ["Trash survives"])
        #expect(relaunchedTrash[0].formerProjectID == relaunchedProjects[0].id)
        #expect(relaunchedDraft.markdown == "Draft survives")
        #expect(relaunchedDraft.projectID == relaunchedProjects[0].id)
        #expect(relaunchedSettings.shortcut == shortcut)
    }

    private func makeContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Thought.self,
            Project.self,
            configurations: ModelConfiguration(url: url)
        )
    }
}

@MainActor
private final class PreservationLoginItemService: LoginItemServicing {
    let status: LoginItemStatus = .notRegistered
    func setEnabled(_ enabled: Bool) throws {}
}
