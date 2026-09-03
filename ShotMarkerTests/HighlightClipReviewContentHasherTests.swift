@testable import ShotMarker
import XCTest

final class HighlightClipReviewContentHasherTests: XCTestCase {
    func testSameBytesProduceSameLowercaseSHA256AndDifferentBytesDoNot() async throws {
        let firstURL = try makeFile(bytes: Data("same-content".utf8))
        let secondURL = try makeFile(bytes: Data("same-content".utf8))
        let differentURL = try makeFile(bytes: Data("different-content".utf8))
        let hasher = HighlightClipReviewContentHasher(chunkSize: 4)

        let first = try await hasher.sha256(for: firstURL)
        let second = try await hasher.sha256(for: secondURL)
        let different = try await hasher.sha256(for: differentURL)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, different)
        XCTAssertEqual(first.count, 64)
        XCTAssertEqual(first, first.lowercased())
    }

    func testReaderNeverReceivesMoreThanConfiguredChunkSize() async throws {
        let fileURL = try makeFile(bytes: Data(repeating: 0x5a, count: 25))
        let lock = NSLock()
        var requestedCounts: [Int] = []
        let hasher = HighlightClipReviewContentHasher(
            chunkSize: 7,
            readChunk: { handle, count in
                lock.lock()
                requestedCounts.append(count)
                lock.unlock()
                return try handle.read(upToCount: count)
            },
        )

        _ = try await hasher.sha256(for: fileURL)

        XCTAssertFalse(requestedCounts.isEmpty)
        XCTAssertTrue(requestedCounts.allSatisfy { $0 == 7 })
    }

    func testReadFailurePropagatesWithoutReturningPartialDigest() async {
        let fileURL = try! makeFile(bytes: Data("bytes".utf8))
        let hasher = HighlightClipReviewContentHasher(
            chunkSize: 4,
            readChunk: { _, _ in throw TestError.readFailed },
        )

        await XCTAssertThrowsErrorAsync(try await hasher.sha256(for: fileURL)) {
            XCTAssertEqual($0 as? TestError, .readFailed)
        }
    }

    func testCallerCancellationStopsDetachedHashingTask() async throws {
        let fileURL = try makeFile(bytes: Data([1]))
        let readStarted = expectation(description: "hash read started")
        let allowFirstReadToFinish = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var readCount = 0
        let hasher = HighlightClipReviewContentHasher(
            chunkSize: 1,
            readChunk: { _, _ in
                lock.lock()
                readCount += 1
                let isFirstRead = readCount == 1
                lock.unlock()
                guard isFirstRead else {
                    return nil
                }
                readStarted.fulfill()
                allowFirstReadToFinish.wait()
                return Data([1])
            },
        )
        let task = Task {
            try await hasher.sha256(for: fileURL)
        }
        await fulfillment(of: [readStarted], timeout: 1)

        task.cancel()
        allowFirstReadToFinish.signal()

        do {
            _ = try await task.value
            XCTFail("Expected caller cancellation to stop hashing")
        } catch is CancellationError {
            // Expected.
        }
    }
}

private extension HighlightClipReviewContentHasherTests {
    func makeFile(bytes: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("video.mov")
        try bytes.write(to: fileURL)
        return fileURL
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
) async {
    do {
        _ = try await expression()
        XCTFail("Expected async expression to throw")
    } catch {
        errorHandler(error)
    }
}

private enum TestError: Error, Equatable {
    case readFailed
}
