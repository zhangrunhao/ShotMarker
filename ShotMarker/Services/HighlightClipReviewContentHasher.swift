import CryptoKit
import Foundation

nonisolated protocol HighlightClipReviewContentHashing: Sendable {
    func sha256(for fileURL: URL) async throws -> String
}

nonisolated struct HighlightClipReviewContentHasher: HighlightClipReviewContentHashing, @unchecked Sendable {
    typealias ReadChunk = (FileHandle, Int) throws -> Data?

    private let chunkSize: Int
    private let readChunk: ReadChunk

    init(
        chunkSize: Int = 1_048_576,
        readChunk: @escaping ReadChunk = { handle, count in
            try handle.read(upToCount: count)
        },
    ) {
        precondition(chunkSize > 0)
        self.chunkSize = chunkSize
        self.readChunk = readChunk
    }

    func sha256(for fileURL: URL) async throws -> String {
        let hashingTask = Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            var digest = SHA256()
            while true {
                try Task.checkCancellation()
                guard let data = try readChunk(handle, chunkSize), !data.isEmpty else {
                    break
                }
                digest.update(data: data)
            }
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return try await withTaskCancellationHandler {
            try await hashingTask.value
        } onCancel: {
            hashingTask.cancel()
        }
    }
}
