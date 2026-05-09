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
