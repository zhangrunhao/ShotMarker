import Foundation

protocol HighlightJobFileStoreProtocol {
    func copyInputVideo(at sourceURL: URL, jobID: UUID, videoID: String) throws -> String
    func moveOutputVideo(at sourceURL: URL, jobID: UUID) throws -> String
    func url(forRelativePath relativePath: String) throws -> URL
    func removeOutput(for jobID: UUID) throws
    func removeAllFiles(for jobID: UUID) throws
}

struct HighlightJobFileStore: HighlightJobFileStoreProtocol {
    private let baseDirectoryURL: URL
    private let fileManager: FileManager

    init(baseDirectoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShotMarker", isDirectory: true)
    }

    func copyInputVideo(at sourceURL: URL, jobID: UUID, videoID: String) throws -> String {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let fileName = "\(Self.safeFileName(from: videoID)).\(fileExtension)"
        let relativePath = "HighlightJobs/Inputs/\(jobID.uuidString)/\(fileName)"
        let destinationURL = try urlForWriting(relativePath: relativePath)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return relativePath
    }

    func moveOutputVideo(at sourceURL: URL, jobID: UUID) throws -> String {
        let relativePath = "HighlightJobs/Outputs/\(jobID.uuidString)/highlight.mov"
        let destinationURL = try urlForWriting(relativePath: relativePath)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return relativePath
    }

    func url(forRelativePath relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("..") else {
            throw HighlightJobFileStoreError.invalidRelativePath
        }

        return baseDirectoryURL.appendingPathComponent(relativePath)
    }

    func removeOutput(for jobID: UUID) throws {
        try removeDirectoryIfExists(baseDirectoryURL.appendingPathComponent("HighlightJobs/Outputs/\(jobID.uuidString)", isDirectory: true))
    }

    func removeAllFiles(for jobID: UUID) throws {
        try removeDirectoryIfExists(baseDirectoryURL.appendingPathComponent("HighlightJobs/Inputs/\(jobID.uuidString)", isDirectory: true))
        try removeDirectoryIfExists(baseDirectoryURL.appendingPathComponent("HighlightJobs/Outputs/\(jobID.uuidString)", isDirectory: true))
    }

    private func urlForWriting(relativePath: String) throws -> URL {
        let destinationURL = try url(forRelativePath: relativePath)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return destinationURL
    }

    private func removeDirectoryIfExists(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    private static func safeFileName(from value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
    }
}

enum HighlightJobFileStoreError: LocalizedError, Equatable {
    case invalidRelativePath
    case missingFile

    var errorDescription: String? {
        switch self {
        case .invalidRelativePath:
            "任务文件路径无效。"
        case .missingFile:
            "本地视频文件不存在，请重新生成。"
        }
    }
}
