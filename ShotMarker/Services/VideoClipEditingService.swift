import AVFoundation
import Foundation

struct VideoClipEditingService {
    func makeTestClip(from sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration: CMTime = try await asset.load(.duration)
        let segments = VideoClipSegmentPlanner.testSegments(forDuration: duration.seconds)
        return try await exportClip(from: asset, segments: segments)
    }

    private func exportClip(from asset: AVAsset, segments: [VideoClipSegment]) async throws -> URL {
        guard !segments.isEmpty else {
            throw VideoClipEditingError.emptySegments
        }

        let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = sourceVideoTracks.first else {
            throw VideoClipEditingError.missingVideoTrack
        }

        let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first

        // AVMutableComposition 是一个“空时间线”。
        // 我们不会直接修改原视频，而是把原视频中的若干时间片段插入到这条新时间线里。
        let composition = AVMutableComposition()

        // 新时间线至少需要一条视频轨道。后面每插入一个片段，都会写入这条轨道。
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid,
        ) else {
            throw VideoClipEditingError.compositionTrackUnavailable
        }

        // 如果原视频有音频，就给新时间线也建一条音频轨道。
        // 没有音频的视频也可以正常剪，不需要强制失败。
        let compositionAudioTrack: AVMutableCompositionTrack? = if sourceAudioTrack == nil {
            nil
        } else {
            composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid,
            )
        }

        // 保留原视频方向信息。否则竖屏视频导出后可能变成横着或旋转 90 度。
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        // insertionTime 表示“下一个片段应该放在新视频的哪个时间点”。
        // 第一个片段从 0 秒开始；每插完一段，就往后移动这段的时长。
        var insertionTime = CMTime.zero
        for segment in segments {
            // timeRange 表示从原视频里截哪一段，例如 0-2 秒，或 5-7 秒。
            let segmentDuration = CMTime(seconds: segment.duration, preferredTimescale: 600)
            let timeRange = CMTimeRange(
                start: CMTime(seconds: segment.start, preferredTimescale: 600),
                duration: segmentDuration,
            )

            // 把原视频的这一段插入到新时间线的视频轨道里。
            try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: insertionTime)

            // 音频也用同样的 timeRange 和 insertionTime，保证声音和画面同步拼接。
            if let sourceAudioTrack, let compositionAudioTrack {
                try compositionAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: insertionTime)
            }

            // 下一段紧跟在当前片段后面，于是两个片段会拼成一个连续的新视频。
            insertionTime = CMTimeAdd(insertionTime, segmentDuration)
        }

        return try await export(composition)
    }

    private func export(_ composition: AVAsset) async throws -> URL {
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality,
        ) else {
            throw VideoClipEditingError.exportSessionUnavailable
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotMarker-TestClip-\(UUID().uuidString).mov")
        try await exportSession.export(to: outputURL, as: .mov)
        return outputURL
    }
}

enum VideoClipEditingError: LocalizedError {
    case emptySegments
    case missingVideoTrack
    case compositionTrackUnavailable
    case exportSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .emptySegments:
            "视频太短，无法生成测试剪辑。"
        case .missingVideoTrack:
            "没有找到可剪辑的视频轨道。"
        case .compositionTrackUnavailable:
            "无法创建视频拼接轨道。"
        case .exportSessionUnavailable:
            "无法创建视频导出任务。"
        }
    }
}
