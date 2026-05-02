import SwiftUI
import WatchKit

struct WatchTrainingView: View {
    @StateObject private var viewModel = WatchTrainingViewModel()
    @State private var buttonScale = 1.0
    @State private var pendingLongPressToggle: DispatchWorkItem?
    @State private var isPressingButton = false
    @State private var isCompletingLongPress = false

    private let syncService: WatchTrainingSyncServiceProtocol
    private let longPressTransitionDuration = 0.5
    private let returnTransitionDuration = 0.18

    @MainActor
    init(syncService: WatchTrainingSyncServiceProtocol? = nil) {
        self.syncService = syncService ?? WatchTrainingSyncService()
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
        }
        .padding()
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
