@testable import ShotMarker
import AVFoundation
import XCTest

final class HighlightClipReviewMediaProviderTests: XCTestCase {
    @MainActor
    func testThumbnailUsesCurrentRangeMidpointAndExactTargetSize() async throws {
        var requests: [HighlightClipFrameRequest] = []
        let provider = makeProvider { request in
            requests.append(request)
            return Data([1])
        }
        let item = makeItem(start: 4, duration: 6)

        _ = try await provider.thumbnailData(
            for: item,
            video: makeVideo(),
            targetSize: CGSize(width: 320, height: 180),
        )

        XCTAssertEqual(requests.map(\.time), [7])
        XCTAssertEqual(requests.map(\.targetSize), [CGSize(width: 320, height: 180)])
    }

    @MainActor
    func testFilmstripSamplesUniformBinCentersInsideLocalWindow() async throws {
        var times: [TimeInterval] = []
        let provider = makeProvider { request in
            times.append(request.time)
            return Data([1])
        }

        _ = try await provider.filmstripFrames(
            for: makeVideo(),
            timeRange: HighlightClipRange(start: 0, duration: 12),
            count: 3,
            targetSize: CGSize(width: 120, height: 80),
        )

        XCTAssertEqual(times, [2, 6, 10])
    }

    @MainActor
    func testIdenticalFrameRequestHitsCacheButSizeAndVideoRemainPartOfKey() async throws {
        var generationCount = 0
        let provider = makeProvider(cacheLimit: 8) { _ in
            generationCount += 1
            return Data([UInt8(generationCount)])
        }
        let item = makeItem(start: 4, duration: 6)

        _ = try await provider.thumbnailData(
            for: item,
            video: makeVideo(),
            targetSize: .init(width: 100, height: 100),
        )
        _ = try await provider.thumbnailData(
            for: item,
            video: makeVideo(),
            targetSize: .init(width: 100, height: 100),
        )
        _ = try await provider.thumbnailData(
            for: item,
            video: makeVideo(),
            targetSize: .init(width: 200, height: 100),
        )

        XCTAssertEqual(generationCount, 2)
    }

    @MainActor
    func testCacheEvictsLeastRecentlyUsedEntryAtConfiguredLimit() async throws {
        var generationCount = 0
        let provider = makeProvider(cacheLimit: 2) { _ in
            generationCount += 1
            return Data([UInt8(generationCount)])
        }

        _ = try await provider.frameData(
            for: makeVideo(),
            at: 1,
            targetSize: .init(width: 10, height: 10),
        )
        _ = try await provider.frameData(
            for: makeVideo(),
            at: 2,
            targetSize: .init(width: 10, height: 10),
        )
        _ = try await provider.frameData(
            for: makeVideo(),
            at: 3,
            targetSize: .init(width: 10, height: 10),
        )
        _ = try await provider.frameData(
            for: makeVideo(),
            at: 1,
            targetSize: .init(width: 10, height: 10),
        )

        XCTAssertEqual(generationCount, 4)
    }

    @MainActor
    func testCancellationCancelsInFlightFrameGeneration() async {
        let started = expectation(description: "frame generation started")
        let cancelled = expectation(description: "frame generation cancelled")
        let provider = makeProvider { _ in
            started.fulfill()
            return try await withTaskCancellationHandler {
                try await Task.sleep(for: .seconds(60))
                return Data([1])
            } onCancel: {
                cancelled.fulfill()
            }
        }
        let task = Task {
            try await provider.frameData(
                for: makeVideo(),
                at: 1,
                targetSize: .init(width: 10, height: 10),
            )
        }
        await fulfillment(of: [started], timeout: 1)

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await fulfillment(of: [cancelled], timeout: 1)
    }

    @MainActor
    private func makeProvider(
        cacheLimit: Int = 64,
        generate: @escaping (HighlightClipFrameRequest) async throws -> Data,
    ) -> HighlightClipReviewMediaProvider {
        HighlightClipReviewMediaProvider(
            cacheLimit: cacheLimit,
            loadAsset: { _ in AVURLAsset(url: URL(fileURLWithPath: "/tmp/video.mov")) },
            generateFrame: { _, request in try await generate(request) },
        )
    }

    private func makeVideo(id: String = "video") -> SelectedTrainingVideo {
        SelectedTrainingVideo(
            id: id,
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
    }

    private func makeItem(start: TimeInterval, duration: TimeInterval) -> HighlightClipReviewItem {
        HighlightClipReviewItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000080001")!,
            videoID: "video",
            markerReferences: [
                HighlightClipMarkerReference(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000080101")!,
                    markedAt: Date(timeIntervalSince1970: 110),
                    timeInVideo: 10,
                    originalMatchedNumber: 1,
                ),
            ],
            defaultStart: start,
            defaultDuration: duration,
            start: start,
            duration: duration,
            isIncluded: true,
        )
    }
}
