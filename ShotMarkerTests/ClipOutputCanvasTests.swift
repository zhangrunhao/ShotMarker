@testable import ShotMarker
import CoreGraphics
import XCTest

@MainActor
final class ClipOutputCanvasTests: XCTestCase {
    func testLateSourceCannotReplaceNewCanvas() async {
        let started = expectation(description: "first metadata requested")
        var pending: CheckedContinuation<CGSize, Error>?
        let canvas = ClipOutputCanvas { video in
            if video.id == "first" {
                return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
            }
            return CGSize(width: 360, height: 640)
        }
        let first = Task { await canvas.load(video: source("first")) }
        await fulfillment(of: [started], timeout: 2)
        await canvas.load(video: source("second"))
        pending?.resume(returning: CGSize(width: 640, height: 360))
        await first.value
        XCTAssertEqual(canvas.size, CGSize(width: 360, height: 640))
        XCTAssertFalse(canvas.failed)
    }

    func testReleasedPreviewRejectsLateMetadata() async {
        let started = expectation(description: "metadata requested")
        var pending: CheckedContinuation<CGSize, Error>?
        let canvas = ClipOutputCanvas { _ in
            try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
        }
        let loading = Task { await canvas.load(video: source("first")) }
        await fulfillment(of: [started], timeout: 2)
        canvas.reset()
        pending?.resume(returning: CGSize(width: 1920, height: 1080))
        await loading.value
        XCTAssertNil(canvas.size)
        XCTAssertFalse(canvas.failed)
    }

    func testInvalidCanvasBlocksEditingUntilRetrySucceeds() async {
        var attempts = 0
        let canvas = ClipOutputCanvas { _ in
            attempts += 1
            return attempts == 1 ? CGSize(width: 0, height: 360) : CGSize(width: 640, height: 360)
        }
        await canvas.load(video: source("first"))
        XCTAssertNil(canvas.size)
        XCTAssertTrue(canvas.failed)
        await canvas.load(video: source("first"))
        XCTAssertEqual(canvas.size, CGSize(width: 640, height: 360))
        XCTAssertFalse(canvas.failed)
    }

    private func source(_ id: String) -> SelectedTrainingVideo {
        SelectedTrainingVideo(id: id, recordedStartAt: Date(timeIntervalSince1970: 100), duration: 20)
    }
}
