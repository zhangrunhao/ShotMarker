@testable import ShotMarker
import XCTest

final class HighlightJobFileStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testCopyInputVideoStoresFileUnderJobInputDirectory() throws {
        let store = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000020001"))
        let sourceURL = temporaryDirectory.appendingPathComponent("picked-source.mov")
        try Data([1, 2, 3]).write(to: sourceURL)

        let relativePath = try store.copyInputVideo(at: sourceURL, jobID: jobID, videoID: sourceURL.absoluteString)
        let copiedURL = try store.url(forRelativePath: relativePath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedURL.path))
        XCTAssertEqual(try Data(contentsOf: copiedURL), Data([1, 2, 3]))
        XCTAssertTrue(relativePath.contains("Inputs/\(jobID.uuidString)"))
        XCTAssertEqual(copiedURL.pathExtension, "mov")
    }

    func testMoveOutputVideoStoresFileUnderJobOutputDirectory() throws {
        let store = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000020002"))
        let sourceURL = temporaryDirectory.appendingPathComponent("export.mov")
        try Data([4, 5, 6]).write(to: sourceURL)

        let relativePath = try store.moveOutputVideo(at: sourceURL, jobID: jobID)
        let movedURL = try store.url(forRelativePath: relativePath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path))
        XCTAssertEqual(try Data(contentsOf: movedURL), Data([4, 5, 6]))
        XCTAssertEqual(relativePath, "HighlightJobs/Outputs/\(jobID.uuidString)/highlight.mov")
    }

    func testRemoveOutputKeepsInputForRestart() throws {
        let store = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000020003"))
        let inputSourceURL = temporaryDirectory.appendingPathComponent("input.mov")
        let outputSourceURL = temporaryDirectory.appendingPathComponent("output.mov")
        try Data([1]).write(to: inputSourceURL)
        try Data([2]).write(to: outputSourceURL)
        let inputRelativePath = try store.copyInputVideo(at: inputSourceURL, jobID: jobID, videoID: inputSourceURL.absoluteString)
        let outputRelativePath = try store.moveOutputVideo(at: outputSourceURL, jobID: jobID)

        try store.removeOutput(for: jobID)

        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.url(forRelativePath: inputRelativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.url(forRelativePath: outputRelativePath).path))
    }

    func testRemoveAllFilesDeletesInputAndOutputForJob() throws {
        let store = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000020004"))
        let inputSourceURL = temporaryDirectory.appendingPathComponent("input.mov")
        let outputSourceURL = temporaryDirectory.appendingPathComponent("output.mov")
        try Data([1]).write(to: inputSourceURL)
        try Data([2]).write(to: outputSourceURL)
        let inputRelativePath = try store.copyInputVideo(at: inputSourceURL, jobID: jobID, videoID: inputSourceURL.absoluteString)
        let outputRelativePath = try store.moveOutputVideo(at: outputSourceURL, jobID: jobID)

        try store.removeAllFiles(for: jobID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.url(forRelativePath: inputRelativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.url(forRelativePath: outputRelativePath).path))
    }
}
