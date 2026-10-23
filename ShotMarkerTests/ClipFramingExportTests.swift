@testable import ShotMarker
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// These tests decode the final movie. A composition object alone cannot prove framing.
final class ClipFramingExportTests: XCTestCase {
    private var directory: URL!
    private var invisibleLabels: MarkerLabelStyle {
        var style = MarkerLabelStyle.default
        style.textOpacity = 0
        style.backgroundOpacity = 0
        return style
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testTransparentLabelsStillExportCenterAndEdgeCropsWithFullOverlapDuration() async throws {
        let source = try await makeVideo(name: "grid")
        let framings: [ClipFraming] = [
            .original,
            .init(scale: 2, centerX: 0.5, centerY: 0.5),
            .init(scale: 2, centerX: 0.25, centerY: 0.75),
            .init(scale: 2.2, centerX: 0.7, centerY: 0.3),
            .init(scale: 4, centerX: 0.875, centerY: 0.125),
            .init(scale: 4, centerX: 0.125, centerY: 0.125),
            .init(scale: 4, centerX: 0.125, centerY: 0.875),
            .init(scale: 4, centerX: 0.875, centerY: 0.875),
        ]
        let sourcePixels = try await pixels(source, at: 0.4)
        // Compare decoded source landmarks: codec/color-space conversion need not preserve raw RGB.
        XCTAssertLessThan(sourcePixels.color(0.2, 0.8)[0], sourcePixels.color(0.8, 0.2)[0])
        XCTAssertGreaterThan(sourcePixels.color(0.2, 0.8)[1], sourcePixels.color(0.8, 0.2)[1])
        let segments = framings.map { segment("grid", framing: $0) }
        let output = try await export(segments, sources: ["grid": source])
        let duration = try await output.load(.duration)
        XCTAssertEqual(duration.seconds, Double(framings.count), accuracy: 0.04)
        for (index, framing) in framings.enumerated() {
            let image = try await pixels(output, at: Double(index) + 0.4, evidence: "landscape-\(index)")
            XCTAssertEqual(image.width, 320)
            XCTAssertEqual(image.height, 180)
            for point in [CGPoint(x: 0.02, y: 0.02), CGPoint(x: 0.15, y: 0.2), CGPoint(x: 0.8, y: 0.75), CGPoint(x: 0.98, y: 0.98)] {
                let expectedX = framing.centerX + (point.x - 0.5) / framing.scale
                let expectedY = framing.centerY + (point.y - 0.5) / framing.scale
                assertColor(image.color(point.x, point.y), matches: sourcePixels.color(expectedX, expectedY))
            }
        }
    }

    func testEncodedRotationAndMixedSourcesUseTheirOwnDirectionAndFirstSourceCanvas() async throws {
        let landscape = try await makeVideo(name: "landscape")
        let portrait = try await makeVideo(
            name: "rotated",
            transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 180, ty: 0)
        )
        let landscapePixels = try await pixels(landscape, at: 0.4)
        let portraitPixels = try await pixels(portrait, at: 0.4)
        let sources: [String: AVAsset] = ["landscape": landscape, "portrait": portrait]
        let output = try await export([
            segment("landscape"),
            segment("portrait", framing: .init(scale: 2, centerX: 0.25, centerY: 0.75)),
            segment("landscape", framing: .init(scale: 2, centerX: 0.75, centerY: 0.25)),
        ], sources: sources)
        let rotated = try await pixels(output, at: 1.4, evidence: "rotated-edge")
        XCTAssertEqual(rotated.width, 320)
        XCTAssertEqual(rotated.height, 180)
        assertBlack(rotated.color(0.1, 0.5))
        assertBlack(rotated.color(0.9, 0.5))
        // Upright (x,y) maps to encoded (y, 1-x) for this clockwise transform.
        assertColor(rotated.color(0.5, 0.5), matches: portraitPixels.color(0.25, 0.75))
        let last = try await pixels(output, at: 2.4, evidence: "mixed-last-landscape")
        assertColor(last.color(0.2, 0.8), matches: landscapePixels.color(0.6, 0.4))

        let portraitFirst = try await export([
            segment("portrait"), segment("landscape"),
        ], sources: sources)
        let first = try await pixels(portraitFirst, at: 0.4, evidence: "portrait-first")
        XCTAssertEqual(first.width, 180)
        XCTAssertEqual(first.height, 320)
        assertColor(first.color(0.2, 0.8), matches: portraitPixels.color(0.2, 0.8))
        let second = try await pixels(portraitFirst, at: 1.4)
        assertBlack(second.color(0.5, 0.1))
        assertColor(second.color(0.2, 0.5), matches: landscapePixels.color(0.2, 0.5))
    }

    func testMirroredAndNativelyPortraitSourcesUseUprightCropCoordinates() async throws {
        let landscape = try await makeVideo(name: "canvas")
        let portrait = try await makeVideo(name: "native-portrait", width: 180, height: 320)
        let mirrored = try await makeVideo(name: "mirrored", transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 320, ty: 0))
        let portraitPixels = try await pixels(portrait, at: 0.4)
        let mirroredPixels = try await pixels(mirrored, at: 0.4)
        let output = try await export([
            segment("canvas"),
            segment("portrait", framing: .init(scale: 2, centerX: 0.75, centerY: 0.25)),
            segment("mirror", framing: .init(scale: 2, centerX: 0.25, centerY: 0.75)),
        ], sources: ["canvas": landscape, "portrait": portrait, "mirror": mirrored])
        let middle = try await pixels(output, at: 1.4, evidence: "native-portrait")
        assertBlack(middle.color(0.1, 0.5))
        assertColor(middle.color(0.5, 0.5), matches: portraitPixels.color(0.75, 0.25))
        let last = try await pixels(output, at: 2.4, evidence: "mirrored-edge")
        assertColor(last.color(0.2, 0.8), matches: mirroredPixels.color(0.1, 0.9))
        assertColor(last.color(0.8, 0.2), matches: mirroredPixels.color(0.4, 0.6))
    }

    func testLabelsStayInCanvasCoordinatesAndChangeAtCutWithoutFading() async throws {
        let source = try await makeVideo(name: "black", black: true)
        var style = MarkerLabelStyle.default
        style.normalizedCenterX = 0.8
        style.normalizedCenterY = 0.2
        style.fontSizeRatio = 0.16
        style.backgroundOpacity = 0
        let output = try await export([
            segment("black", number: 8),
            segment("black", number: 8, framing: .init(scale: 4, centerX: 0.125, centerY: 0.875)),
            segment("black", number: 1, framing: .init(scale: 2, centerX: 0.75, centerY: 0.25)),
        ], sources: ["black": source], style: style)
        let original = try await pixels(output, at: 0.4, evidence: "labeled-original")
        let zoomed = try await pixels(output, at: 1.4, evidence: "labeled-zoomed")
        let before = try await pixels(output, at: 1.9666667)
        let after = try await pixels(output, at: 2, evidence: "labeled-cut")
        let later = try await pixels(output, at: 2.4)
        XCTAssertGreaterThan(original.brightPixelCount, 50, "Label must actually render")
        XCTAssertEqual(original.brightBounds, zoomed.brightBounds)
        XCTAssertLessThan(original.averageDifference(zoomed), 0.01)
        XCTAssertLessThan(zoomed.averageDifference(before), 0.01)
        XCTAssertGreaterThan(before.averageDifference(after), 0.0005, "Number must change at the cut")
        XCTAssertLessThan(after.averageDifference(later), 0.01, "No fade or old label after the cut")
        XCTAssertGreaterThan(original.brightBounds.midX, 220)
        XCTAssertLessThan(original.brightBounds.midY, 60)
        let reference = try Pixels(XCTUnwrap(VideoClipEditingService.makeMarkerLabelOverlayImage(
            text: "1/8", metrics: HighlightClipMarkerLabelOverlayMetrics.make(renderSize: CGSize(width: 320, height: 180), style: style)
        )))
        let origin = MarkerLabelLayout.clampedOrigin(for: CGPoint(x: 0.8, y: 0.2), labelSize: CGSize(width: reference.width, height: reference.height), in: CGRect(x: 0, y: 0, width: 320, height: 180))
        XCTAssertLessThan(after.difference(from: reference, at: origin), 0.06, "Glyphs must remain upright, with the existing font and padding")
    }

    func testAudioStaysAlignedWhenOnlyMiddleSourceHasSound() async throws {
        let silent = try await makeVideo(name: "silent")
        let audible = AVMutableComposition()
        let video = try XCTUnwrap(audible.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let sourceVideoTracks = try await silent.loadTracks(withMediaType: .video)
        let sourceVideo = try XCTUnwrap(sourceVideoTracks.first)
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)), of: sourceVideo, at: .zero)
        let audioURL = directory.appendingPathComponent("tone.wav")
        try makeTone().write(to: audioURL)
        let toneAsset = AVURLAsset(url: audioURL)
        let sourceAudio = try await toneAsset.loadTracks(withMediaType: .audio)
        let toneReader = try AVAssetReader(asset: toneAsset)
        let toneOutput = AVAssetReaderTrackOutput(track: try XCTUnwrap(sourceAudio.first), outputSettings: nil)
        toneReader.add(toneOutput)
        XCTAssertTrue(toneReader.startReading())
        var toneSamples = 0
        while let buffer = toneOutput.copyNextSampleBuffer() { toneSamples += CMSampleBufferGetNumSamples(buffer) }
        XCTAssertEqual(toneReader.status, .completed)
        XCTAssertEqual(toneSamples, 44100)
        let audio = try XCTUnwrap(audible.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try audio.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)), of: XCTUnwrap(sourceAudio.first), at: .zero)
        let output = try await export([
            segment("silent"),
            segment("audible", framing: .init(scale: 2, centerX: 0.25, centerY: 0.75)),
            segment("silent", framing: .init(scale: 4, centerX: 0.875, centerY: 0.125)),
        ], sources: ["silent": silent, "audible": audible])
        let duration = try await output.load(.duration)
        XCTAssertEqual(duration.seconds, 3, accuracy: 0.04)
        let outputAudio = try await output.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: output)
        let trackOutput = AVAssetReaderTrackOutput(track: try XCTUnwrap(outputAudio.first), outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(trackOutput)
        XCTAssertTrue(reader.startReading())
        var energy = [Double](repeating: 0, count: 3)
        var count = [Int](repeating: 0, count: 3)
        while let sample = trackOutput.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [UInt8](repeating: 0, count: length)
            XCTAssertEqual(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &bytes), kCMBlockBufferNoErr)
            let description = try XCTUnwrap(CMSampleBufferGetFormatDescription(sample))
            let format = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(description)).pointee
            for index in stride(from: 0, to: length - 1, by: 2) {
                let sampleTime = time + Double(index / 2) / Double(format.mChannelsPerFrame) / format.mSampleRate
                let bucket = min(max(Int(sampleTime), 0), 2)
                // Measure interiors, excluding AAC priming/tail and sample buffers crossing a cut.
                let fraction = sampleTime - floor(sampleTime)
                guard fraction >= 0.2, fraction < 0.8 else { continue }
                let value = Double(Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)) / 32768
                energy[bucket] += value * value
                count[bucket] += 1
            }
        }
        XCTAssertEqual(reader.status, .completed)
        let rms = zip(energy, count).map { sqrt($0 / Double(max($1, 1))) }
        XCTAssertLessThan(rms[0], 0.02)
        XCTAssertGreaterThan(rms[1], 0.2)
        XCTAssertLessThan(rms[2], 0.02)
    }

    func testCancellingRealFramingExportFinishesPendingFramesAndDeletesPartialMovie() async throws {
        let source = try await makeVideo(name: "cancel-source")
        let outputURL = directory.appendingPathComponent("cancelled.mov")
        let rendering = expectation(description: "real export rendered frames")
        let service = VideoClipEditingService(outputURL: outputURL, exportAsset: { session, url, type in
            let monitor = Task { @MainActor in
                while session.progress == 0, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
                if !Task.isCancelled { rendering.fulfill() }
            }
            defer { monitor.cancel() }
            try await session.export(to: url, as: type)
        })
        let segments = (0..<120).map { index in
            segment("source", framing: .init(scale: 2, centerX: index.isMultiple(of: 2) ? 0.25 : 0.75, centerY: 0.5))
        }
        let task = Task {
            try await service.makeHighlightClip(from: segments, markerLabelStyle: .default) { _ in source }
        }
        await fulfillment(of: [rendering], timeout: 10)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected real export cancellation")
        } catch {
            XCTAssertTrue(task.isCancelled)
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    private func makeTone() -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        let sampleRate = 44100
        text("RIFF"); integer(UInt32(36 + sampleRate * 2)); text("WAVEfmt ")
        integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1))
        integer(UInt32(sampleRate)); integer(UInt32(sampleRate * 2))
        integer(UInt16(2)); integer(UInt16(16)); text("data"); integer(UInt32(sampleRate * 2))
        for index in 0..<sampleRate {
            integer(Int16(sin(Double(index) * 2 * .pi * 440 / Double(sampleRate)) * 16000))
        }
        return data
    }

    private func segment(_ id: String, number: Int = 1, framing: ClipFraming = .original) -> HighlightClipSegment {
        HighlightClipSegment(markerIDs: [UUID()], videoID: id, start: 0, duration: 1,
                             markerNumber: number, markerTotalCount: 8, framing: framing)
    }

    private func export(_ segments: [HighlightClipSegment], sources: [String: AVAsset], style: MarkerLabelStyle? = nil) async throws -> AVURLAsset {
        let url = directory.appendingPathComponent("output-\(UUID().uuidString).mov")
        _ = try await VideoClipEditingService(outputURL: url).makeHighlightClip(
            from: segments, markerLabelStyle: style ?? invisibleLabels
        ) { request in try XCTUnwrap(sources[request.videoID]) }
        return AVURLAsset(url: url)
    }

    private func makeVideo(name: String, transform: CGAffineTransform = .identity, black: Bool = false, width: Int = 320, height: Int = 180) async throws -> AVURLAsset {
        let url = directory.appendingPathComponent("\(name).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * stride + x * 4
                base[offset] = black ? 0 : 50
                base[offset + 1] = black ? 0 : UInt8(Double(y) / Double(height - 1) * 255)
                base[offset + 2] = black ? 0 : UInt8(Double(x) / Double(width - 1) * 255)
                base[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        for index in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
        return AVURLAsset(url: url)
    }

    private func pixels(_ asset: AVAsset, at seconds: Double, evidence: String? = nil) async throws -> Pixels {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let result = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        XCTAssertEqual(result.actualTime.seconds, seconds, accuracy: 0.035)
        if let evidence {
            let evidenceDirectory = URL(fileURLWithPath: "/tmp/ShotMarkerFramingEvidence", isDirectory: true)
            try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(evidenceDirectory.appendingPathComponent("\(evidence).png") as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, result.image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
        }
        return try Pixels(result.image)
    }

    private func assertColor(_ color: [Double], matches expected: [Double], file: StaticString = #filePath, line: UInt = #line) {
        for index in 0..<3 { XCTAssertEqual(color[index], expected[index], accuracy: 0.08, file: file, line: line) }
    }

    private func assertBlack(_ color: [Double], file: StaticString = #filePath, line: UInt = #line) {
        for component in color { XCTAssertLessThan(component, 0.06, file: file, line: line) }
    }
}

private struct Pixels {
    let width: Int
    let height: Int
    let data: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = bytes
    }

    func color(_ x: Double, _ y: Double) -> [Double] {
        let offset = (min(Int(y * Double(height)), height - 1) * width + min(Int(x * Double(width)), width - 1)) * 4
        return (0..<3).map { Double(data[offset + $0]) / 255 }
    }

    var brightPixelCount: Int { stride(from: 0, to: data.count, by: 4).filter { data[$0] > 180 }.count }
    var brightBounds: CGRect {
        var bounds = CGRect.null
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4] > 180 {
                bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return bounds
    }

    func difference(from reference: Self, at origin: CGPoint) -> Double {
        var difference = 0.0
        for y in 0..<reference.height {
            for x in 0..<reference.width {
                let offset = ((Int(origin.y) + y) * width + Int(origin.x) + x) * 4
                difference += abs(Double(data[offset]) - Double(reference.data[(y * reference.width + x) * 4]))
            }
        }
        return difference / Double(reference.width * reference.height) / 255
    }

    func averageDifference(_ other: Self) -> Double {
        zip(data, other.data).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(data.count) / 255
    }
}
