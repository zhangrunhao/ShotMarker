import Foundation

nonisolated enum HighlightClipReviewStoreNotice: Equatable, Sendable {
    case corruptDocumentRecovered
    case unsupportedSchemaVersion(Int)
}

nonisolated struct HighlightClipReviewStoreLoadResult: Equatable, Sendable {
    let record: PersistedHighlightClipReview?
    let notice: HighlightClipReviewStoreNotice?
}

nonisolated enum HighlightClipReviewStoreError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidConfirmation
    case duplicateMarkerAssignment

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion:
            "片段确认数据来自更新版本，请更新 App 后再确认。"
        case .invalidConfirmation:
            "片段确认数据无效，请恢复默认范围后再试。"
        case .duplicateMarkerAssignment:
            "片段关联打点冲突，请重新进入审核。"
        }
    }
}

nonisolated protocol HighlightClipReviewStoring: Sendable {
    func loadRecord(
        for key: HighlightClipReviewCombinationKey,
    ) async throws -> HighlightClipReviewStoreLoadResult

    func upsert(
        _ confirmation: PersistedHighlightClipConfirmation,
        for key: HighlightClipReviewCombinationKey,
        now: Date,
    ) async throws

    func deleteRecords(forTrainingSessionID id: UUID) async throws

    func reconcile(
        validTrainingIdentities: Set<HighlightClipReviewTrainingIdentity>,
    ) async throws
}

actor FileHighlightClipReviewStore: HighlightClipReviewStoring {
    typealias AtomicWrite = @Sendable (Data, URL) throws -> Void

    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }

    private struct DocumentLoad {
        let document: HighlightClipReviewStoreDocument
        let notice: HighlightClipReviewStoreNotice?
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let atomicWrite: AtomicWrite

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        atomicWrite: @escaping AtomicWrite = FileHighlightClipReviewStore.writeAtomically,
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.now = now
        self.atomicWrite = atomicWrite
    }

    func loadRecord(
        for key: HighlightClipReviewCombinationKey,
    ) throws -> HighlightClipReviewStoreLoadResult {
        let loaded = try loadDocument()
        let record = loaded.document.records.first {
            $0.combinationDigest == key.digest && $0.combination == key.combination
        }
        return HighlightClipReviewStoreLoadResult(
            record: record,
            notice: loaded.notice,
        )
    }

    func upsert(
        _ confirmation: PersistedHighlightClipConfirmation,
        for key: HighlightClipReviewCombinationKey,
        now: Date,
    ) throws {
        try Task.checkCancellation()
        let loaded = try loadDocument()
        try Self.rejectUnsupportedSchemaNotice(loaded.notice)
        let document = try HighlightClipReviewStoreMutation.upserting(
            confirmation,
            for: key,
            now: now,
            in: loaded.document,
        )
        let data = try Self.encode(document)
        try Task.checkCancellation()
        try atomicWrite(data, fileURL)
    }

    func deleteRecords(forTrainingSessionID id: UUID) throws {
        try Task.checkCancellation()
        let loaded = try loadDocument()
        try Self.rejectUnsupportedSchemaNotice(loaded.notice)
        var document = loaded.document
        let originalCount = document.records.count
        document.records.removeAll { $0.combination.training.id == id }
        guard document.records.count != originalCount else {
            return
        }
        let data = try Self.encode(document)
        try Task.checkCancellation()
        try atomicWrite(data, fileURL)
    }

    func reconcile(
        validTrainingIdentities: Set<HighlightClipReviewTrainingIdentity>,
    ) throws {
        try Task.checkCancellation()
        let loaded = try loadDocument()
        try Self.rejectUnsupportedSchemaNotice(loaded.notice)
        var document = loaded.document
        let originalCount = document.records.count
        document.records.removeAll {
            !validTrainingIdentities.contains($0.combination.training)
        }
        guard document.records.count != originalCount else {
            return
        }
        let data = try Self.encode(document)
        try Task.checkCancellation()
        try atomicWrite(data, fileURL)
    }

    private func loadDocument() throws -> DocumentLoad {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return DocumentLoad(document: .empty, notice: nil)
        }

        let data = try Data(contentsOf: fileURL)
        let header: SchemaHeader
        do {
            header = try JSONDecoder().decode(SchemaHeader.self, from: data)
        } catch {
            return try recoverCorruptDocument()
        }

        if header.schemaVersion > HighlightClipReviewStoreDocument.currentSchemaVersion {
            return DocumentLoad(
                document: .empty,
                notice: .unsupportedSchemaVersion(header.schemaVersion),
            )
        }
        guard header.schemaVersion == HighlightClipReviewStoreDocument.currentSchemaVersion else {
            return try recoverCorruptDocument()
        }

        do {
            return DocumentLoad(
                document: try JSONDecoder().decode(
                    HighlightClipReviewStoreDocument.self,
                    from: data,
                ),
                notice: nil,
            )
        } catch {
            return try recoverCorruptDocument()
        }
    }

    private func recoverCorruptDocument() throws -> DocumentLoad {
        let recoveryURL = fileURL.deletingLastPathComponent().appendingPathComponent(
            "highlight-clip-reviews.corrupt-\(Self.recoveryTimestamp(now())).json",
        )
        try fileManager.moveItem(at: fileURL, to: recoveryURL)
        try atomicWrite(Self.encode(.empty), fileURL)
        return DocumentLoad(document: .empty, notice: .corruptDocumentRecovered)
    }

    private static func rejectUnsupportedSchemaNotice(
        _ notice: HighlightClipReviewStoreNotice?,
    ) throws {
        guard case .unsupportedSchemaVersion(let version) = notice else {
            return
        }
        throw HighlightClipReviewStoreError.unsupportedSchemaVersion(version)
    }

    private static func encode(_ document: HighlightClipReviewStoreDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private static func recoveryTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("ShotMarker", isDirectory: true)
            .appendingPathComponent("highlight-clip-reviews.json")
    }

    private static func writeAtomically(_ data: Data, to fileURL: URL) throws {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(
            ".highlight-clip-reviews-\(UUID().uuidString).tmp",
        )
        do {
            try data.write(to: temporaryURL)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}

actor InMemoryHighlightClipReviewStore: HighlightClipReviewStoring {
    private var document: HighlightClipReviewStoreDocument
    private let loadError: (any Error)?
    private let upsertError: (any Error)?
    private let deleteError: (any Error)?
    private let reconcileError: (any Error)?

    private(set) var upsertCount = 0
    private(set) var deletedTrainingSessionIDs: [UUID] = []
    private(set) var lastValidTrainingIdentities: Set<HighlightClipReviewTrainingIdentity>?

    init(
        seedDocument: HighlightClipReviewStoreDocument = .empty,
        loadError: (any Error)? = nil,
        upsertError: (any Error)? = nil,
        deleteError: (any Error)? = nil,
        reconcileError: (any Error)? = nil,
    ) {
        document = seedDocument
        self.loadError = loadError
        self.upsertError = upsertError
        self.deleteError = deleteError
        self.reconcileError = reconcileError
    }

    func loadRecord(
        for key: HighlightClipReviewCombinationKey,
    ) throws -> HighlightClipReviewStoreLoadResult {
        if let loadError {
            throw loadError
        }
        guard document.schemaVersion <= HighlightClipReviewStoreDocument.currentSchemaVersion else {
            return HighlightClipReviewStoreLoadResult(
                record: nil,
                notice: .unsupportedSchemaVersion(document.schemaVersion),
            )
        }
        let record = document.records.first {
            $0.combinationDigest == key.digest && $0.combination == key.combination
        }
        return HighlightClipReviewStoreLoadResult(record: record, notice: nil)
    }

    func upsert(
        _ confirmation: PersistedHighlightClipConfirmation,
        for key: HighlightClipReviewCombinationKey,
        now: Date,
    ) throws {
        upsertCount += 1
        if let upsertError {
            throw upsertError
        }
        try rejectUnsupportedSchema()
        document = try HighlightClipReviewStoreMutation.upserting(
            confirmation,
            for: key,
            now: now,
            in: document,
        )
    }

    func deleteRecords(forTrainingSessionID id: UUID) throws {
        deletedTrainingSessionIDs.append(id)
        if let deleteError {
            throw deleteError
        }
        try rejectUnsupportedSchema()
        document.records.removeAll { $0.combination.training.id == id }
    }

    func reconcile(
        validTrainingIdentities: Set<HighlightClipReviewTrainingIdentity>,
    ) throws {
        lastValidTrainingIdentities = validTrainingIdentities
        if let reconcileError {
            throw reconcileError
        }
        try rejectUnsupportedSchema()
        document.records.removeAll {
            !validTrainingIdentities.contains($0.combination.training)
        }
    }

    func confirmations(
        for key: HighlightClipReviewCombinationKey,
    ) -> [PersistedHighlightClipConfirmation] {
        document.records.first {
            $0.combinationDigest == key.digest && $0.combination == key.combination
        }?.confirmedItems ?? []
    }

    private func rejectUnsupportedSchema() throws {
        guard document.schemaVersion <= HighlightClipReviewStoreDocument.currentSchemaVersion else {
            throw HighlightClipReviewStoreError.unsupportedSchemaVersion(document.schemaVersion)
        }
    }
}

private nonisolated enum HighlightClipReviewStoreMutation {
    static func upserting(
        _ confirmation: PersistedHighlightClipConfirmation,
        for key: HighlightClipReviewCombinationKey,
        now: Date,
        in document: HighlightClipReviewStoreDocument,
    ) throws -> HighlightClipReviewStoreDocument {
        try validate(confirmation, for: key)
        var document = document
        let recordIndex = document.records.firstIndex {
            $0.combinationDigest == key.digest && $0.combination == key.combination
        }

        if let recordIndex {
            var record = document.records[recordIndex]
            if let confirmationIndex = record.confirmedItems.firstIndex(where: {
                $0.identity == confirmation.identity
            }) {
                let previous = record.confirmedItems[confirmationIndex]
                record.confirmedItems[confirmationIndex] = PersistedHighlightClipConfirmation(
                    videoIdentity: confirmation.videoIdentity,
                    markerIDs: confirmation.markerIDs,
                    defaultStart: previous.defaultStart,
                    defaultDuration: previous.defaultDuration,
                    start: confirmation.start,
                    duration: confirmation.duration,
                    isIncluded: confirmation.isIncluded,
                    confirmedAt: confirmation.confirmedAt,
                )
            } else {
                let occupiedMarkerIDs = Set(record.confirmedItems.flatMap(\.markerIDs))
                guard occupiedMarkerIDs.isDisjoint(with: confirmation.markerIDs) else {
                    throw HighlightClipReviewStoreError.duplicateMarkerAssignment
                }
                record.confirmedItems.append(confirmation)
            }
            record.updatedAt = now
            document.records[recordIndex] = record
        } else {
            document.records.append(
                PersistedHighlightClipReview(
                    combinationDigest: key.digest,
                    combination: key.combination,
                    confirmedItems: [confirmation],
                    createdAt: now,
                    updatedAt: now,
                ),
            )
        }
        return document
    }

    private static func validate(
        _ confirmation: PersistedHighlightClipConfirmation,
        for key: HighlightClipReviewCombinationKey,
    ) throws {
        guard !confirmation.markerIDs.isEmpty,
              Set(confirmation.markerIDs).count == confirmation.markerIDs.count,
              !confirmation.videoIdentity.source.value.isEmpty,
              key.combination.videos.contains(confirmation.videoIdentity)
        else {
            throw HighlightClipReviewStoreError.invalidConfirmation
        }

        let validMarkerIDs = Set(key.combination.training.markers.map(\.id))
        guard Set(confirmation.markerIDs).isSubset(of: validMarkerIDs) else {
            throw HighlightClipReviewStoreError.invalidConfirmation
        }

        let videoDuration = Double(confirmation.videoIdentity.durationTicks)
            / Double(HighlightClipReviewIdentityBuilder.videoTimescale)
        guard validRange(
            start: confirmation.defaultStart,
            duration: confirmation.defaultDuration,
            videoDuration: videoDuration,
        ), validRange(
            start: confirmation.start,
            duration: confirmation.duration,
            videoDuration: videoDuration,
        ) else {
            throw HighlightClipReviewStoreError.invalidConfirmation
        }
    }

    private static func validRange(
        start: TimeInterval,
        duration: TimeInterval,
        videoDuration: TimeInterval,
    ) -> Bool {
        guard videoDuration.isFinite,
              videoDuration > 0,
              start.isFinite,
              duration.isFinite,
              isNormalizedTenth(start),
              isNormalizedTenth(duration),
              start >= 0,
              duration > 0,
              start + duration <= videoDuration,
              duration >= min(1, videoDuration)
        else {
            return false
        }
        return true
    }

    private static func isNormalizedTenth(_ value: TimeInterval) -> Bool {
        abs((value * 10).rounded(.toNearestOrAwayFromZero) - (value * 10)) < 0.000_001
    }
}
