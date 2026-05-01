import XCTest
@testable import ShotMarker

final class TimestampFileStoreTests: XCTestCase {
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

    func testLoadReturnsEmptyArrayWhenFileDoesNotExist() throws {
        let store = TimestampFileStore(fileURL: temporaryDirectory.appendingPathComponent("missing.json"))

        let files = try store.loadTimestampFiles()

        XCTAssertEqual(files, [])
    }

    func testSaveAndLoadRoundTripsTimestampFiles() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("timestamp-files.json")
        let store = TimestampFileStore(fileURL: fileURL)
        let timestampFile = TimestampFile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            trainingDate: Date(timeIntervalSince1970: 10_000),
            startedAt: Date(timeIntervalSince1970: 10_000),
            endedAt: Date(timeIntervalSince1970: 10_600),
            events: [
                ShotMarkerEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                    markedAt: Date(timeIntervalSince1970: 10_120),
                    source: .watch
                )
            ],
            syncStatus: .synced,
            highlightStatus: .notClipped
        )

        try store.saveTimestampFiles([timestampFile])

        XCTAssertEqual(try store.loadTimestampFiles(), [timestampFile])
    }
}
