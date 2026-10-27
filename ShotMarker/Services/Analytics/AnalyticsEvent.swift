import Foundation

nonisolated enum AnalyticsEvent: String, CaseIterable, Sendable {
    case appLaunch = "app_launch"
    case trainingSyncStarted = "training_sync_started"
    case trainingSyncSucceeded = "training_sync_succeeded"
    case trainingSyncFailed = "training_sync_failed"
    case trainingSyncIgnored = "training_sync_ignored"
    case trainingSyncAckFailed = "training_sync_ack_failed"
    case highlightGenerateStarted = "highlight_generate_started"
    case highlightGenerateSucceeded = "highlight_generate_succeeded"
    case highlightGenerateFailed = "highlight_generate_failed"
    case highlightGenerateCancelled = "highlight_generate_cancelled"
    case highlightSaveStarted = "highlight_save_started"
    case highlightSaveSucceeded = "highlight_save_succeeded"
    case highlightSaveFailed = "highlight_save_failed"
    case highlightSaveCancelled = "highlight_save_cancelled"
    case highlightSaveStateFailed = "highlight_save_state_failed"
}

nonisolated enum AnalyticsStage: String, Sendable {
    case received, decode, `import`, ack, validation, queue, export, commit, permission
    case photosWrite = "photos_write"
    case localState = "local_state"
}

nonisolated enum AnalyticsReason: String, Sendable {
    case invalidInput = "invalid_input"
    case decodeFailed = "decode_failed"
    case importFailed = "import_failed"
    case ackFailed = "ack_failed"
    case beforeCutover = "before_cutover"
    case background, busy
    case invalidTask = "invalid_task"
    case revisionConflict = "revision_conflict"
    case sourceUnavailable = "source_unavailable"
    case exportFailed = "export_failed"
    case outputCommitFailed = "output_commit_failed"
    case permissionDenied = "permission_denied"
    case missingOutput = "missing_output"
    case photosWriteFailed = "photos_write_failed"
    case stateUpdateFailed = "state_update_failed"
    case userCancelled = "user_cancelled"
    case backgrounded, cancelled, interrupted, unknown
}

nonisolated protocol AnalyticsTracking: Sendable {
    func track(_ event: AnalyticsEvent)
    func track(_ event: AnalyticsEvent, operationID: UUID, stage: AnalyticsStage, reason: AnalyticsReason?)
}

nonisolated extension AnalyticsTracking {
    // Existing clients used by the retired pipeline remain source compatible.
    func track(_ event: AnalyticsEvent, operationID: UUID, stage: AnalyticsStage) {
        track(event, operationID: operationID, stage: stage, reason: nil)
    }

    func track(_ event: AnalyticsEvent, operationID: UUID, stage: AnalyticsStage, reason: AnalyticsReason?) {
        track(event)
    }
}

nonisolated struct NoopAnalyticsTracker: AnalyticsTracking {
    func track(_ event: AnalyticsEvent) {}
}
