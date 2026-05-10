@testable import ShotMarker
import AVFoundation
import XCTest

final class VideoClipEditingServiceTests: XCTestCase {
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

    func testMakeTestClipExportsTwoSegmentsIntoOneMovie() async throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("source.mov")
        try await makeSilentVideo(at: sourceURL, duration: 6)

        let outputURL = try await VideoClipEditingService().makeTestClip(from: sourceURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertNotEqual(outputURL, sourceURL)

        let outputAsset = AVURLAsset(url: outputURL)
        let outputDuration: CMTime = try await outputAsset.load(.duration)
        XCTAssertEqual(outputDuration.seconds, 4, accuracy: 0.2)
    }

    func testMakeHighlightClipExportsPlannedSegmentsIntoOneMovie() async throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("highlight-source.mov")
        try await makeSilentVideo(at: sourceURL, duration: 8)
        let markerAt = Date(timeIntervalSince1970: 1_000)
        let firstMarkerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000002001"))
        let secondMarkerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000002002"))
        let segments = [
            HighlightClipSegment(
                markerID: firstMarkerID,
                videoID: "video",
                markerAt: markerAt,
                start: 1,
                duration: 2,
            ),
            HighlightClipSegment(
                markerID: secondMarkerID,
                videoID: "video",
                markerAt: markerAt.addingTimeInterval(10),
                start: 5,
                duration: 1,
            ),
        ]

        var requestedVideoIDs: [String] = []
        let outputURL = try await VideoClipEditingService().makeHighlightClip(from: segments) { request in
            requestedVideoIDs.append(request.videoID)
            return AVURLAsset(url: sourceURL)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(requestedVideoIDs, ["video"])
        let outputAsset = AVURLAsset(url: outputURL)
        let outputDuration: CMTime = try await outputAsset.load(.duration)
        XCTAssertEqual(outputDuration.seconds, 3, accuracy: 0.2)
    }

    func testMakeHighlightClipRequestsOnlyNeededSegmentsForEachSourceVideo() async throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("highlight-request-source.mov")
        try await makeSilentVideo(at: sourceURL, duration: 40)
        let markerAt = Date(timeIntervalSince1970: 1_000)
        let firstMarkerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000002301"))
        let secondMarkerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000002302"))
        let thirdMarkerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000002303"))
        let segments = [
            HighlightClipSegment(
                markerID: firstMarkerID,
                videoID: "long-video",
                markerAt: markerAt,
                start: 6,
                duration: 6,
            ),
            HighlightClipSegment(
                markerID: secondMarkerID,
                videoID: "short-video",
                markerAt: markerAt.addingTimeInterval(60),
                start: 10,
                duration: 5,
            ),
            HighlightClipSegment(
                markerID: thirdMarkerID,
                videoID: "long-video",
                markerAt: markerAt.addingTimeInterval(120),
                start: 18,
                duration: 6,
            ),
        ]

        var assetRequests: [HighlightClipAssetRequest] = []
        _ = try await VideoClipEditingService().makeHighlightClip(from: segments) { request in
            assetRequests.append(request)
            return AVURLAsset(url: sourceURL)
        }

        XCTAssertEqual(assetRequests.map(\.videoID), ["long-video", "short-video"])
        XCTAssertEqual(assetRequests[0].segments.map(\.start), [6, 18])
        XCTAssertEqual(assetRequests[0].requestedDuration, 12)
        XCTAssertEqual(assetRequests[1].segments.map(\.start), [10])
        XCTAssertEqual(assetRequests[1].requestedDuration, 5)
    }

    func testAssetRequestPrefersMediumDeliveryForSmallClipSetFromLongSourceVideo() throws {
        let markerAt = Date(timeIntervalSince1970: 1_000)
        let markerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000002401"))
        let request = HighlightClipAssetRequest(
            videoID: "long-video",
            segments: [
                HighlightClipSegment(
                    markerID: markerID,
                    videoID: "long-video",
                    markerAt: markerAt,
                    start: 1_200,
                    duration: 120,
                ),
            ],
        )

        XCTAssertEqual(
            request.photoLibraryDeliveryQuality(forSourceDuration: 3_600),
            .medium,
        )
        XCTAssertEqual(
            request.photoLibraryDeliveryQuality(forSourceDuration: 240),
            .high,
        )
    }

    @MainActor
    func testMakeHighlightClipReportsMatchedMarkerProgress() async throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("highlight-progress-source.mov")
        try await makeSilentVideo(at: sourceURL, duration: 8)
        let markerAt = Date(timeIntervalSince1970: 1_000)
        let firstMarkerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000002101"))
        let secondMarkerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000002102"))
        let segments = [
            HighlightClipSegment(
                markerID: firstMarkerID,
                videoID: "video",
                markerAt: markerAt,
                start: 1,
                duration: 2,
                markerNumber: 1,
                markerTotalCount: 2,
            ),
            HighlightClipSegment(
                markerID: secondMarkerID,
                videoID: "video",
                markerAt: markerAt.addingTimeInterval(10),
                start: 5,
                duration: 1,
                markerNumber: 2,
                markerTotalCount: 2,
            ),
        ]

        var progressUpdates: [HighlightClipGenerationProgress] = []
        let outputURL = try await VideoClipEditingService().makeHighlightClip(
            from: segments,
            progressHandler: { progressUpdates.append($0) },
        ) { _ in
            AVURLAsset(url: sourceURL)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(progressUpdates.first, HighlightClipGenerationProgress(completedMarkerCount: 0, totalMarkerCount: 2))
        XCTAssertEqual(progressUpdates.last, HighlightClipGenerationProgress(completedMarkerCount: 2, totalMarkerCount: 2))
        XCTAssertFalse(progressUpdates.dropLast().contains(
            HighlightClipGenerationProgress(completedMarkerCount: 2, totalMarkerCount: 2),
        ))
    }

    func testHighlightClipExportProgressDoesNotReachTotalBeforeExportFinishes() {
        XCTAssertEqual(
            VideoClipEditingService.completedMarkerCount(
                forExportProgress: 1,
                totalMarkerCount: 9,
                isFinished: false,
            ),
            8,
        )
        XCTAssertEqual(
            VideoClipEditingService.completedMarkerCount(
                forExportProgress: 1,
                totalMarkerCount: 9,
                isFinished: true,
            ),
            9,
        )
    }

    func testMarkerLabelOverlayStyleUsesLargeOpaqueLabel() {
        let style = HighlightClipMarkerLabelOverlayStyle.default

        XCTAssertGreaterThanOrEqual(style.fontSizeRatio, 0.1)
        XCTAssertEqual(style.backgroundAlpha, 1)
    }

    private func makeSilentVideo(at url: URL, duration: TimeInterval) async throws {
        let writer = try makeAssetWriter(at: url)
        let input = makeWriterInput()
        let adaptor = makePixelBufferAdaptor(for: input)
        guard writer.canAdd(input) else {
            throw TestVideoError.cannotAddWriterInput
        }

        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? TestVideoError.writerStartFailed
        }

        writer.startSession(atSourceTime: .zero)
        try await writeFrames(
            duration: duration,
            writer: writer,
            input: input,
            adaptor: adaptor,
        )
    }

    private func writeFrames(
        duration: TimeInterval,
        writer: AVAssetWriter,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "ShotMarker.VideoClipEditingServiceTests.video-writer")
            let frameRate: Int32 = 30
            let frameCount = Int(duration * Double(frameRate))
            var frameIndex = 0
            var didResume = false

            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData, frameIndex < frameCount {
                    do {
                        let pixelBuffer = try Self.makePixelBuffer(
                            width: 160,
                            height: 160,
                            value: UInt8(frameIndex % 255),
                        )
                        let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)
                        XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: presentationTime))
                        frameIndex += 1
                    } catch {
                        input.markAsFinished()
                        writer.cancelWriting()
                        if !didResume {
                            didResume = true
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                }

                guard frameIndex >= frameCount else {
                    return
                }

                input.markAsFinished()
                writer.finishWriting {
                    if !didResume {
                        didResume = true
                        if let error = writer.error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    private func makeAssetWriter(at url: URL) throws -> AVAssetWriter {
        try AVAssetWriter(outputURL: url, fileType: .mov)
    }

    private func makeWriterInput() -> AVAssetWriterInput {
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 160,
                AVVideoHeightKey: 160,
            ],
        )
        input.expectsMediaDataInRealTime = false
        return input
    }

    private func makePixelBufferAdaptor(
        for input: AVAssetWriterInput,
    ) -> AVAssetWriterInputPixelBufferAdaptor {
        AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 160,
                kCVPixelBufferHeightKey as String: 160,
            ],
        )
    }

    private static func makePixelBuffer(width: Int, height: Int, value: UInt8) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer,
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw TestVideoError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, Int32(value), CVPixelBufferGetDataSize(pixelBuffer))
        }

        return pixelBuffer
    }

    private enum TestVideoError: Error {
        case cannotAddWriterInput
        case pixelBufferCreationFailed(CVReturn)
        case writerStartFailed
    }
}
