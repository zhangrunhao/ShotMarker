@testable import ShotMarker
import XCTest

final class HighlightTaskFileStoreTests: XCTestCase {
    func testReselectingSameFileRepairsMissingPrivateInputWithoutChangingVideoIdentity() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let source = fixture.directory.appendingPathComponent("source.mov")
        try Data("video bytes".utf8).write(to: source)
        let files = HighlightTaskFileStore(baseDirectory: fixture.directory)
        let id = UUID()
        let first = try await files.prepareInputs([
            SelectedTrainingVideo(id: source.absoluteString, recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60),
        ], taskID: id, existing: [])
        try await files.commitInputs(first, creating: true)
        guard case .taskInputFile(let path) = first.videos[0].source else { return XCTFail("Expected file") }
        let privateURL = try files.url(forRelativePath: path)
        try FileManager.default.removeItem(at: privateURL)
        let repair = try await files.prepareInputs([
            SelectedTrainingVideo(id: source.absoluteString, recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60,
                reviewSourceIdentity: first.videos[0].sourceIdentity),
        ], taskID: id, existing: first.videos)
        try await files.commitInputs(repair, creating: false)
        XCTAssertEqual(repair.videos, first.videos)
        XCTAssertEqual(try Data(contentsOf: privateURL), Data("video bytes".utf8))
    }

    func testCreationCopiesAllFileInputsAndKeepsOnlyPhotoReferences() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let input = fixture.directory.appendingPathComponent("source.mov")
        try Data("video bytes".utf8).write(to: input)
        let fileStore = HighlightTaskFileStore(baseDirectory: fixture.directory)
        let taskID = UUID()
        let prepared = try await fileStore.prepareInputs([
            SelectedTrainingVideo(id: input.absoluteString, recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60),
            SelectedTrainingVideo(id: "photo", recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60,
                reviewSourceIdentity: .photoLibraryAsset("photo")),
        ], taskID: taskID, existing: [])
        try await fileStore.commitInputs(prepared, creating: true)
        guard case .taskInputFile(let path) = prepared.videos[0].source else { return XCTFail("Expected private file") }
        XCTAssertFalse(path.contains("source.mov"))
        XCTAssertEqual(try Data(contentsOf: fileStore.url(forRelativePath: path)), Data("video bytes".utf8))
        XCTAssertEqual(prepared.videos[0].sourceIdentity.kind, .fileSHA256)
        XCTAssertEqual(prepared.videos[1].source, .photoLibraryAsset(localIdentifier: "photo"))
        try await fileStore.removeTask(taskID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }

    func testCreationThroughPrivateAliasCopiesInputsBeforeTaskDirectoriesExist() async throws {
        #if targetEnvironment(simulator)
            // Simulator sandboxes can live under /Users, outside the /private alias.
            let temporary = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        #else
            let temporaryPath = FileManager.default.temporaryDirectory.standardizedFileURL.path
            let privatePath = temporaryPath.hasPrefix("/private/") ? temporaryPath : "/private" + temporaryPath
            let temporary = URL(fileURLWithPath: privatePath, isDirectory: true)
        #endif
        let root = temporary.appendingPathComponent("ShotMarker-PrivateAliasTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mov")
        let bytes = Data("private alias input".utf8)
        try bytes.write(to: source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("HighlightTasks").path))
        let files = HighlightTaskFileStore(baseDirectory: root)
        let prepared = try await files.prepareInputs([
            SelectedTrainingVideo(id: source.absoluteString, recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60),
        ], taskID: UUID(), existing: [])

        try await files.commitInputs(prepared, creating: true)

        guard case let .taskInputFile(path) = prepared.videos[0].source else { return XCTFail("Expected task-owned input") }
        XCTAssertEqual(try Data(contentsOf: files.url(forRelativePath: path)), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    func testPathsRejectTraversalAbsoluteAndCrossTaskSymlink() throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let store = HighlightTaskFileStore(baseDirectory: fixture.directory)
        for path in ["../outside", "/outside", "HighlightTasks/../outside", "HighlightTasks//file"] {
            XCTAssertThrowsError(try store.url(forRelativePath: path))
        }
        let task = UUID()
        let link = fixture.directory.appendingPathComponent("HighlightTasks/\(task)")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.directory)
        XCTAssertThrowsError(try store.url(forRelativePath: "HighlightTasks/\(task)/Inputs/file.mov"))
    }

    func testCleanupPreservesReferencedInputsAndCurrentOutputOnly() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let store = HighlightTaskFileStore(baseDirectory: fixture.directory,
            temporaryDirectory: fixture.directory.appendingPathComponent("tmp"))
        var task = try HighlightTaskTestFixture.task()
        let old = fixture.directory.appendingPathComponent("old.mov")
        try Data([1]).write(to: old)
        let outputID = UUID()
        let path = try await store.moveOutput(at: old, taskID: task.id, outputID: outputID)
        task.currentOutput = HighlightTaskOutput(id: outputID, relativePath: path, configurationRevision: 1, generatedAt: Date())
        let orphan = fixture.directory.appendingPathComponent("orphan.mov")
        try Data([2]).write(to: orphan)
        let orphanPath = try await store.moveOutput(at: orphan, taskID: task.id, outputID: UUID())
        try await store.cleanOrphans(referencing: [task])
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.url(forRelativePath: path).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.url(forRelativePath: orphanPath).path))
    }
}
