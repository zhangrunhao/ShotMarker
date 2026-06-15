import Foundation

struct HighlightJob: Identifiable, Codable, Equatable {
    let id: UUID
    var trainingSession: TrainingSession
    var selectedVideos: [HighlightJobVideo]
    var clipSettings: ClipSettings
    var status: HighlightJobStatus
    var progress: HighlightJobProgress
    var outputVideoPath: String?
    var photoLibrarySavedAt: Date? = nil
    var photoLibrarySaveErrorMessage: String? = nil
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    var canCancel: Bool {
        status == .queued || status == .running || status == .saving
    }

    var canRestart: Bool {
        status == .failed || status == .interrupted
    }

    var canClear: Bool {
        status == .completed || status == .failed || status == .interrupted
    }

    enum CodingKeys: String, CodingKey {
        case id
        case trainingSession
        case selectedVideos
        case clipSettings
        case status
        case progress
        case outputVideoPath
        case photoLibrarySavedAt
        case photoLibrarySaveErrorMessage
        case errorMessage
        case createdAt
        case updatedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(trainingSession, forKey: .trainingSession)
        try container.encode(selectedVideos, forKey: .selectedVideos)
        try container.encode(clipSettings, forKey: .clipSettings)
        try container.encode(status, forKey: .status)
        try container.encode(progress, forKey: .progress)
        try container.encode(outputVideoPath, forKey: .outputVideoPath)
        try container.encode(photoLibrarySavedAt, forKey: .photoLibrarySavedAt)
        try container.encode(photoLibrarySaveErrorMessage, forKey: .photoLibrarySaveErrorMessage)
        try container.encode(errorMessage, forKey: .errorMessage)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct HighlightJobVideo: Identifiable, Codable, Equatable {
    let id: String
    let recordedStartAt: Date
    let duration: TimeInterval
    let source: HighlightJobVideoSource

    var selectedTrainingVideo: SelectedTrainingVideo {
        SelectedTrainingVideo(id: id, recordedStartAt: recordedStartAt, duration: duration)
    }
}

enum HighlightJobVideoSource: Codable, Equatable {
    case photoLibraryAsset(localIdentifier: String)
    case jobInputFile(relativePath: String)
}

enum HighlightJobStatus: String, Codable, Equatable {
    case queued
    case running
    case saving
    case completed
    case failed
    case interrupted

    var isLaunchInterruptedState: Bool {
        self == .queued || self == .running || self == .saving
    }
}

struct HighlightJobProgress: Codable, Equatable {
    var completedMarkerCount: Int
    var totalMarkerCount: Int

    static let zero = HighlightJobProgress(completedMarkerCount: 0, totalMarkerCount: 0)

    var fractionCompleted: Double? {
        guard totalMarkerCount > 0 else {
            return nil
        }

        return min(max(Double(completedMarkerCount) / Double(totalMarkerCount), 0), 1)
    }
}
