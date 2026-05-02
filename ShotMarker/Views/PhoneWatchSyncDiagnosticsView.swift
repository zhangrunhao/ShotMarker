import SwiftUI

struct PhoneWatchSyncDiagnosticsView: View {
    let snapshotProvider: () -> PhoneWatchSyncDiagnosticsSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let snapshot = snapshotProvider()

            List {
                Section("Session") {
                    diagnosticsRow("Supported", value: boolText(snapshot.isSupported))
                    diagnosticsRow("Paired", value: boolText(snapshot.isPaired))
                    diagnosticsRow("Watch app", value: boolText(snapshot.isWatchAppInstalled))
                    diagnosticsRow("Activation", value: snapshot.activationState)
                }

                Section("Receive") {
                    diagnosticsRow("Last payload", value: dateText(snapshot.lastReceivedPayloadAt))
                    diagnosticsRow("Payload ID", value: idText(snapshot.lastReceivedTrainingSessionId))
                    diagnosticsRow("Import error", value: snapshot.lastImportErrorDescription ?? "none")
                }

                Section("ACK") {
                    diagnosticsRow("Last ACK", value: dateText(snapshot.lastAckSentAt))
                    diagnosticsRow("ACK ID", value: idText(snapshot.lastAckTrainingSessionId))
                    diagnosticsRow("ACK error", value: snapshot.lastAckErrorDescription ?? "none")
                }

                Section("Activation") {
                    diagnosticsRow("Completed", value: dateText(snapshot.lastActivationCompletedAt))
                    diagnosticsRow("Error", value: snapshot.lastActivationErrorDescription ?? "none")
                }
            }
            .navigationTitle("同步诊断")
        }
    }

    private func diagnosticsRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func boolText(_ value: Bool) -> String {
        value ? "yes" : "no"
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
