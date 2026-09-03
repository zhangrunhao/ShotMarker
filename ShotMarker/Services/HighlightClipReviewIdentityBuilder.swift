import CoreMedia
import CryptoKit
import Foundation

nonisolated enum HighlightClipReviewIdentityError: LocalizedError, Equatable {
    case missingSourceIdentity
    case invalidVideoMetadata
    case duplicateVideoIdentity

    var errorDescription: String? {
        switch self {
        case .missingSourceIdentity:
            "无法建立视频的稳定身份，请重新选择视频。"
        case .invalidVideoMetadata:
            "视频时间信息无效，请重新选择视频。"
        case .duplicateVideoIdentity:
            "选择的视频身份重复，请移除重复视频后再试。"
        }
    }
}

nonisolated enum HighlightClipReviewIdentityBuilder {
    static let videoTimescale: CMTimeScale = 600

    static func trainingIdentity(for session: TrainingSession) -> HighlightClipReviewTrainingIdentity {
        let markers = session.events
            .map {
                HighlightClipReviewMarkerIdentity(
                    id: $0.id,
                    markedAtMilliseconds: milliseconds($0.markedAt),
                )
            }
            .sorted {
                if $0.markedAtMilliseconds == $1.markedAtMilliseconds {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.markedAtMilliseconds < $1.markedAtMilliseconds
            }
        return HighlightClipReviewTrainingIdentity(
            id: session.id,
            startedAtMilliseconds: milliseconds(session.startedAt),
            endedAtMilliseconds: milliseconds(session.endedAt),
            markers: markers,
        )
    }

    static func combinationKey(
        for session: TrainingSession,
        videos: [SelectedTrainingVideo],
    ) throws -> HighlightClipReviewCombinationKey {
        let videoIdentities = try videos.map(videoIdentity(for:))
        guard Set(videoIdentities).count == videoIdentities.count else {
            throw HighlightClipReviewIdentityError.duplicateVideoIdentity
        }

        let combination = HighlightClipReviewCombination(
            training: trainingIdentity(for: session),
            videos: videoIdentities,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(combination)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return HighlightClipReviewCombinationKey(digest: digest, combination: combination)
    }

    static func videoIdentity(
        for video: SelectedTrainingVideo,
    ) throws -> HighlightClipReviewVideoIdentity {
        guard let source = video.reviewSourceIdentity else {
            throw HighlightClipReviewIdentityError.missingSourceIdentity
        }
        guard video.duration.isFinite, video.duration > 0 else {
            throw HighlightClipReviewIdentityError.invalidVideoMetadata
        }
        return HighlightClipReviewVideoIdentity(
            source: source,
            recordedStartAtMilliseconds: milliseconds(video.recordedStartAt),
            durationTicks: CMTime(
                seconds: video.duration,
                preferredTimescale: videoTimescale,
            ).value,
        )
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.toNearestOrAwayFromZero))
    }
}
