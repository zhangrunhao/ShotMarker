#if DEBUG && os(iOS)
    import CoreTransferable
    import PhotosUI
    import SwiftUI
    import UniformTypeIdentifiers

    struct VideoClipTestButton: View {
        @State private var selectedItem: PhotosPickerItem?
        @State private var isProcessing = false
        @State private var alert: VideoClipTestAlert?

        private let service = VideoClipEditingService()
        private let photoLibrarySaver = VideoClipPhotoLibrarySaver()

        var body: some View {
            VStack(alignment: .trailing, spacing: 8) {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                }

                PhotosPicker(selection: $selectedItem, matching: .videos) {
                    Label(isProcessing ? "剪辑中" : "测试剪辑", systemImage: "scissors")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else {
                    return
                }

                Task {
                    await makeClip(from: newItem)
                }
            }
            .alert(alert?.title ?? "", isPresented: isShowingAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(alert?.message ?? "")
            }
        }

        private var isShowingAlert: Binding<Bool> {
            Binding(
                get: { alert != nil },
                set: { isPresented in
                    if !isPresented {
                        alert = nil
                    }
                },
            )
        }

        @MainActor
        private func makeClip(from item: PhotosPickerItem) async {
            isProcessing = true
            defer {
                isProcessing = false
                selectedItem = nil
            }

            do {
                guard let pickedVideo = try await item.loadTransferable(type: PickedVideo.self) else {
                    throw VideoClipTestError.videoLoadFailed
                }

                let outputURL = try await service.makeTestClip(from: pickedVideo.url)
                try await photoLibrarySaver.saveVideo(at: outputURL)
                try? FileManager.default.removeItem(at: outputURL)
                alert = VideoClipTestAlert(title: "测试剪辑完成", message: "新视频已保存到相册。")
            } catch {
                alert = VideoClipTestAlert(
                    title: "测试剪辑失败",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                )
            }
        }
    }

    private struct PickedVideo: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { video in
                SentTransferredFile(video.url)
            } importing: { received in
                let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
                let copyURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ShotMarker-PickedVideo-\(UUID().uuidString).\(fileExtension)")

                try FileManager.default.copyItem(at: received.file, to: copyURL)
                return PickedVideo(url: copyURL)
            }
        }
    }

    private struct VideoClipTestAlert {
        let title: String
        let message: String
    }

    private enum VideoClipTestError: LocalizedError {
        case videoLoadFailed

        var errorDescription: String? {
            "无法读取选择的视频。"
        }
    }
#endif
