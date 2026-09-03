import Foundation

struct HighlightClipReviewSourceIdentity: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case photoLibraryAsset
        case fileSHA256
    }

    let kind: Kind
    let value: String

    static func photoLibraryAsset(_ value: String) -> Self {
        Self(kind: .photoLibraryAsset, value: value)
    }

    static func fileSHA256(_ value: String) -> Self {
        Self(kind: .fileSHA256, value: value)
    }
}

struct HighlightClipReviewMarkerIdentity: Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let markedAtMilliseconds: Int64
}

struct HighlightClipReviewTrainingIdentity: Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let startedAtMilliseconds: Int64
    let endedAtMilliseconds: Int64
    let markers: [HighlightClipReviewMarkerIdentity]
}

struct HighlightClipReviewVideoIdentity: Codable, Equatable, Hashable, Sendable {
    let source: HighlightClipReviewSourceIdentity
    let recordedStartAtMilliseconds: Int64
    let durationTicks: Int64
}

struct HighlightClipReviewCombination: Codable, Equatable, Hashable, Sendable {
    let training: HighlightClipReviewTrainingIdentity
    let videos: [HighlightClipReviewVideoIdentity]
}

struct HighlightClipReviewCombinationKey: Equatable, Hashable, Sendable {
    let digest: String
    let combination: HighlightClipReviewCombination
}

struct HighlightClipReviewStoreDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var records: [PersistedHighlightClipReview]

    static let empty = Self(schemaVersion: currentSchemaVersion, records: [])
}

struct PersistedHighlightClipReview: Codable, Equatable, Sendable {
    let combinationDigest: String
    let combination: HighlightClipReviewCombination
    var confirmedItems: [PersistedHighlightClipConfirmation]
    let createdAt: Date
    var updatedAt: Date
}

struct PersistedHighlightClipConfirmation: Codable, Equatable, Sendable {
    let videoIdentity: HighlightClipReviewVideoIdentity
    let markerIDs: [UUID]
    let defaultStart: TimeInterval
    let defaultDuration: TimeInterval
    let start: TimeInterval
    let duration: TimeInterval
    let isIncluded: Bool
    let confirmedAt: Date

    var identity: HighlightClipConfirmationIdentity {
        HighlightClipConfirmationIdentity(videoIdentity: videoIdentity, markerIDs: markerIDs)
    }
}

struct HighlightClipConfirmationIdentity: Equatable, Hashable, Sendable {
    let videoIdentity: HighlightClipReviewVideoIdentity
    let markerIDs: [UUID]
}
