@testable import ShotMarker
import AVFoundation
import Photos
import XCTest

final class VideoClipPhotoLibrarySaverTests: XCTestCase {
    func testSaveVideoRequestsAddOnlyAccessAndSavesWhenAuthorized() async throws {
        let videoURL = URL(fileURLWithPath: "/tmp/test.mov")
        let logger = SpyAppLogger()
        var savedURLs: [URL] = []
        let saver = VideoClipPhotoLibrarySaver(
            requestAuthorization: { .authorized },
            saveVideoToLibrary: { savedURLs.append($0) },
            logger: logger,
        )

        try await saver.saveVideo(at: videoURL)

        XCTAssertEqual(savedURLs, [videoURL])
        XCTAssertEqual(logger.entry(named: "photos.save.authorization.requested")?.level, .info)
        XCTAssertEqual(logger.entry(named: "photos.save.succeeded")?.level, .info)
    }

    func testSaveVideoThrowsWhenAccessIsDenied() async {
        let logger = SpyAppLogger()
        let saver = VideoClipPhotoLibrarySaver(
            requestAuthorization: { .denied },
            saveVideoToLibrary: { _ in XCTFail("Should not save without photo library access") },
            logger: logger,
        )

        do {
            try await saver.saveVideo(at: URL(fileURLWithPath: "/tmp/test.mov"))
            XCTFail("Expected photo library access error")
        } catch VideoClipPhotoLibraryError.accessDenied {
            let entry = logger.entry(named: "photos.save.authorization.denied")
            XCTAssertEqual(entry?.level, .warning)
            XCTAssertEqual(entry?.category, .photos)
            XCTAssertEqual(entry?.context["authorizationStatus"], "denied")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSaveVideoLogsFailureErrorMetadata() async {
        let logger = SpyAppLogger()
        let saveError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let saver = VideoClipPhotoLibrarySaver(
            requestAuthorization: { .authorized },
            saveVideoToLibrary: { _ in throw saveError },
            logger: logger,
        )

        do {
            try await saver.saveVideo(at: URL(fileURLWithPath: "/tmp/test.mov"))
            XCTFail("Expected save failure")
        } catch {
            let entry = logger.entry(named: "photos.save.failed")
            XCTAssertEqual(entry?.level, .error)
            XCTAssertEqual(entry?.category, .photos)
            XCTAssertEqual(entry?.errorDomain, NSURLErrorDomain)
            XCTAssertEqual(entry?.errorCode, NSURLErrorNotConnectedToInternet)
        }
    }

    func testPhotoLibraryVideoAccessTreatsNetworkErrorAsPickerFallbackCandidate() {
        let error = NSError(domain: PHPhotosErrorDomain, code: 3169)

        XCTAssertTrue(PhotoLibraryVideoAccess.shouldFallbackToPickerFile(for: error))
    }

    func testPhotoLibraryVideoAccessMapsNetworkErrorToActionableMessage() {
        let error = NSError(domain: PHPhotosErrorDomain, code: 3169)
        let userFacingError = PhotoLibraryVideoAccess.userFacingError(for: error)

        XCTAssertEqual(
            (userFacingError as? LocalizedError)?.errorDescription,
            "无法从 iCloud 读取所选视频。请确认网络可用，或先在照片 App 打开这个视频让它下载完成后再试。",
        )
    }

    func testPhotoLibraryVideoAccessCancelsAssetRequestWhenItTimesOut() async {
        var didStartRequest = false
        var cancelledRequestIDs: [PHImageRequestID] = []

        do {
            _ = try await PhotoLibraryVideoAccess.requestAVAsset(
                deliveryQuality: .high,
                timeout: .milliseconds(1),
                startRequest: { options, _ in
                    didStartRequest = true
                    XCTAssertEqual(options.deliveryMode, .highQualityFormat)
                    return PHImageRequestID(42)
                },
                cancelRequest: { cancelledRequestIDs.append($0) },
            )
            XCTFail("Expected request timeout")
        } catch PhotoLibraryVideoAccessError.requestTimedOut {
            XCTAssertTrue(didStartRequest)
            XCTAssertEqual(cancelledRequestIDs, [PHImageRequestID(42)])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPhotoLibraryVideoAccessRequestsCurrentVideoVersion() async throws {
        let asset = AVMutableComposition()

        let requestedAsset = try await PhotoLibraryVideoAccess.requestAVAsset(
            deliveryQuality: .high,
            timeout: .seconds(1),
            startRequest: { options, completion in
                XCTAssertEqual(options.version, .current)
                completion(asset, nil)
                return PHImageRequestID(42)
            },
        )

        XCTAssertTrue(requestedAsset === asset)
    }

    func testPhotoLibraryVideoAccessTreatsTimeoutAsPickerFallbackCandidate() {
        XCTAssertTrue(PhotoLibraryVideoAccess.shouldFallbackToPickerFile(for: PhotoLibraryVideoAccessError.requestTimedOut))
    }

    func testPhotoLibraryVideoAccessMapsTimeoutToActionableMessage() {
        let userFacingError = PhotoLibraryVideoAccess.userFacingError(for: PhotoLibraryVideoAccessError.requestTimedOut)

        XCTAssertEqual(
            (userFacingError as? LocalizedError)?.errorDescription,
            "系统相册无法读取所选视频的高质量版本，常见于 iCloud 未下载或相册内裁剪、调整后的视频。请先在照片 App 打开并等待下载完成，或导出/复制为新视频后再选择。",
        )
    }

    func testPhotoLibraryVideoAccessWithTimeoutReturnsCompletedValue() async throws {
        let value = try await PhotoLibraryVideoAccess.withTimeout(timeout: .seconds(1)) {
            "loaded"
        }

        XCTAssertEqual(value, "loaded")
    }

    func testPhotoLibraryVideoAccessWithTimeoutThrowsWhenOperationDoesNotComplete() async {
        do {
            _ = try await PhotoLibraryVideoAccess.withTimeout(timeout: .milliseconds(1)) {
                try await Task.sleep(for: .seconds(60))
                return "loaded"
            }
            XCTFail("Expected request timeout")
        } catch PhotoLibraryVideoAccessError.requestTimedOut {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPhotoLibraryVideoAccessWithTimeoutReturnsPromptlyWhenOperationIgnoresCancellation() async {
        let start = ContinuousClock.now

        do {
            _ = try await PhotoLibraryVideoAccess.withTimeout(timeout: .milliseconds(1)) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                        continuation.resume()
                    }
                }
                return "loaded"
            }
            XCTFail("Expected request timeout")
        } catch PhotoLibraryVideoAccessError.requestTimedOut {
            let elapsed = start.duration(to: .now)
            XCTAssertTrue(elapsed < .milliseconds(100), "Expected timeout to return promptly, got \(elapsed)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct SpyLogEntry {
    let level: AppLogLevel
    let category: AppLogCategory
    let name: String
    let message: String
    let context: [String: String]
    let errorDomain: String?
    let errorCode: Int?
    let errorDescription: String?
}

private final class SpyAppLogger: AppLogging {
    private(set) var entries: [SpyLogEntry] = []

    func debug(_ name: String, category: AppLogCategory, message: String, context: [String: String]) {
        append(level: .debug, category: category, name: name, message: message, context: context)
    }

    func info(_ name: String, category: AppLogCategory, message: String, context: [String: String]) {
        append(level: .info, category: category, name: name, message: message, context: context)
    }

    func warning(_ name: String, category: AppLogCategory, message: String, context: [String: String]) {
        append(level: .warning, category: category, name: name, message: message, context: context)
    }

    func error(
        _ name: String,
        category: AppLogCategory,
        message: String,
        error: Error?,
        context: [String: String],
    ) {
        let nsError = error as NSError?
        append(
            level: .error,
            category: category,
            name: name,
            message: message,
            context: context,
            errorDomain: nsError?.domain,
            errorCode: nsError?.code,
            errorDescription: error.map { String(describing: $0) },
        )
    }

    func entry(named name: String) -> SpyLogEntry? {
        entries.first { $0.name == name }
    }

    private func append(
        level: AppLogLevel,
        category: AppLogCategory,
        name: String,
        message: String,
        context: [String: String],
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        errorDescription: String? = nil,
    ) {
        entries.append(
            SpyLogEntry(
                level: level,
                category: category,
                name: name,
                message: message,
                context: context,
                errorDomain: errorDomain,
                errorCode: errorCode,
                errorDescription: errorDescription,
            ),
        )
    }
}
