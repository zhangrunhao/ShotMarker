import SwiftUI
import WatchKit

struct WatchTrainingView: View {
    // StateObject 必须在 init 里创建，因为生产环境需要把真正的 HealthKit runtime manager
    // 注入到 ViewModel；测试或预览也可以传入替身，避免弹权限或依赖 watchOS 系统会话。
    @StateObject private var viewModel: WatchTrainingViewModel
    @State private var buttonScale = 1.0
    @State private var pendingLongPressToggle: DispatchWorkItem?
    @State private var isPressingButton = false
    @State private var isCompletingLongPress = false
    @State private var isShowingDiagnostics = false

    private let syncService: WatchTrainingSyncServiceProtocol
    private let longPressTransitionDuration = 0.5
    private let returnTransitionDuration = 0.18

    @MainActor
    init(
        syncService: WatchTrainingSyncServiceProtocol? = nil,
        runtimeSessionManager: WatchTrainingRuntimeSessionManaging? = nil,
    ) {
        self.syncService = syncService ?? WatchTrainingSyncService()
        _viewModel = StateObject(
            wrappedValue: WatchTrainingViewModel(
                // ViewModel 默认是 no-op manager，只有真正的 WatchTrainingView 使用 HealthKit 实现。
                // 这样能同时满足两件事：单测稳定可控，真机训练时启动 HKWorkoutSession。
                runtimeSessionManager: runtimeSessionManager ?? HealthKitWorkoutRuntimeSessionManager(),
            ),
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(viewModel.buttonTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(width: 128, height: 128)
                .background(viewModel.buttonColor)
                .clipShape(Circle())
                .contentShape(Circle())
                .scaleEffect(buttonScale)
                .accessibilityAddTraits(.isButton)
                .simultaneousGesture(longPressTransitionGesture)
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    if viewModel.handleDoubleTap() {
                        WKInterfaceDevice.current().play(.success)
                    }
                })

            Text(viewModel.markerCountText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                isShowingDiagnostics = true
            } label: {
                Label("诊断", systemImage: "wave.3.right.circle")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .sheet(isPresented: $isShowingDiagnostics) {
            WatchSyncDiagnosticsView(snapshotProvider: syncService.diagnosticsSnapshot)
        }
    }

    private var longPressTransitionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isCompletingLongPress else {
                    return
                }

                guard abs(value.translation.width) < 18, abs(value.translation.height) < 18 else {
                    cancelLongPressTransition()
                    return
                }

                guard !isPressingButton, pendingLongPressToggle == nil else {
                    return
                }

                isPressingButton = true
                startLongPressTransition()
            }
            .onEnded { _ in
                isPressingButton = false

                guard !isCompletingLongPress else {
                    return
                }

                cancelLongPressTransition()
            }
    }

    private func startLongPressTransition() {
        let toggle = DispatchWorkItem {
            pendingLongPressToggle = nil
            isCompletingLongPress = true
            let completedPayload = viewModel.handleLongPress(syncService: syncService)

            if completedPayload != nil {
                WKInterfaceDevice.current().play(.click)
            }

            withAnimation(.easeOut(duration: returnTransitionDuration)) {
                buttonScale = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + returnTransitionDuration) {
                isCompletingLongPress = false
            }
        }

        pendingLongPressToggle = toggle

        withAnimation(.easeInOut(duration: longPressTransitionDuration)) {
            buttonScale = 0.5
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + longPressTransitionDuration, execute: toggle)
    }

    private func cancelLongPressTransition() {
        pendingLongPressToggle?.cancel()
        pendingLongPressToggle = nil

        withAnimation(.easeOut(duration: 0.12)) {
            buttonScale = 1.0
        }
    }
}
