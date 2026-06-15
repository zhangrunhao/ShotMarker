#if os(iOS)
    import AVFoundation
    import CoreTransferable
    import Foundation
    import PhotosUI
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers

    struct TrainingVideoTemporaryFileStore {
        func loadPickedTrainingVideo(from item: PhotosPickerItem) async throws -> PickedTrainingVideo {
            guard let pickedVideo = try await item.loadTransferable(type: PickedTrainingVideo.self) else {
                throw HighlightVideoSelectionError.videoLoadFailed
            }

            return pickedVideo
        }

        func temporaryVideoURL(from videoID: String) -> URL? {
            SelectedTrainingVideoReadinessChecker.temporaryVideoURL(from: videoID)
        }

        func removeTemporaryVideoIfNeeded(_ video: SelectedTrainingVideo) {
            guard let url = temporaryVideoURL(from: video.id) else {
                return
            }

            removeTemporaryVideo(at: url)
        }

        func cleanupTemporaryVideos(_ videos: [SelectedTrainingVideo]) {
            videos.compactMap { temporaryVideoURL(from: $0.id) }.forEach(removeTemporaryVideo)
        }

        func removeTemporaryVideo(at url: URL) {
            try? FileManager.default.removeItem(at: url)
        }

        func metadata(from url: URL) async throws -> TrainingVideoMetadata {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds

            guard duration.isFinite, duration > 0 else {
                throw HighlightVideoSelectionError.invalidDuration
            }

            guard let creationDateItem = try await asset.load(.creationDate),
                  let recordedStartAt = try await creationDateItem.load(.dateValue)
            else {
                throw HighlightVideoSelectionError.missingRecordedStartAt
            }

            return TrainingVideoMetadata(recordedStartAt: recordedStartAt, duration: duration)
        }

        func thumbnailData(from url: URL) async -> Data? {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)

            do {
                let image = try await cgImage(from: generator, at: .zero)
                return UIImage(cgImage: image).jpegData(compressionQuality: 0.72)
            } catch {
                return nil
            }
        }

        private func cgImage(
            from generator: AVAssetImageGenerator,
            at time: CMTime,
        ) async throws -> CGImage {
            try await withCheckedThrowingContinuation { continuation in
                generator.generateCGImageAsynchronously(for: time) { image, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let image else {
                        continuation.resume(throwing: HighlightVideoSelectionError.videoLoadFailed)
                        return
                    }

                    continuation.resume(returning: image)
                }
            }
        }
    }

    struct PickedTrainingVideo: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { video in
                SentTransferredFile(video.url)
            } importing: { received in
                let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
                let copyURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ShotMarker-TrainingVideo-\(UUID().uuidString).\(fileExtension)")

                let isAccessingSecurityScopedResource = received.file.startAccessingSecurityScopedResource()
                defer {
                    if isAccessingSecurityScopedResource {
                        received.file.stopAccessingSecurityScopedResource()
                    }
                }

                try FileManager.default.copyItem(at: received.file, to: copyURL)
                return PickedTrainingVideo(url: copyURL)
            }
        }
    }
#endif
