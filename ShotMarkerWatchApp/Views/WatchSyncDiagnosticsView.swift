import SwiftUI

struct WatchSyncDiagnosticsView: View {
    let snapshotProvider: () -> WatchTrainingSyncDiagnosticsSnapshot

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let snapshot = snapshotProvider()

                List {
                    Section("Session") {
                        diagnosticsRow("Activation", value: snapshot.activationState)
                        diagnosticsRow("Last activation", value: dateText(snapshot.lastActivationCompletedAt))
                        diagnosticsRow("Last retry", value: dateText(snapshot.lastRetryAt))
                    }

                    Section("Outbox") {
                        diagnosticsRow("Total", value: String(snapshot.outboxCount))
                        diagnosticsRow("Pending", value: String(snapshot.pendingTransferCount))
                        diagnosticsRow("Awaiting ACK", value: String(snapshot.awaitingAckCount))
                        diagnosticsRow("Error", value: snapshot.lastOutboxErrorDescription ?? "none")
                    }

                    Section("Transfer") {
                        diagnosticsRow("Enqueued", value: dateText(snapshot.lastEnqueuedAt))
                        diagnosticsRow("Enqueued ID", value: idText(snapshot.lastEnqueuedTrainingSessionId))
                        diagnosticsRow("Requested", value: dateText(snapshot.lastTransferRequestedAt))
                        diagnosticsRow("Requested ID", value: idText(snapshot.lastTransferRequestedTrainingSessionId))
                        diagnosticsRow("Finished", value: dateText(snapshot.lastTransferFinishedAt))
                        diagnosticsRow("Finished ID", value: idText(snapshot.lastTransferFinishedTrainingSessionId))
                        diagnosticsRow("Error", value: snapshot.lastTransferErrorDescription ?? "none")
                    }

                    Section("ACK") {
                        diagnosticsRow("Received", value: dateText(snapshot.lastAckReceivedAt))
                        diagnosticsRow("ACK ID", value: idText(snapshot.lastAckTrainingSessionId))
                    }
                }
            }
            .navigationTitle("同步诊断")
        }
    }

    private func diagnosticsRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else {
            return "none"
        }

        return Self.dateFormatter.string(from: date)
    }

    private func idText(_ id: UUID?) -> String {
        guard let id else {
            return "none"
        }

        return String(id.uuidString.prefix(8))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}
