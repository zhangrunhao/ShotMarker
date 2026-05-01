import SwiftUI

struct TrainingSessionRow: View {
    let row: TrainingSessionRowViewData

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.trainingDate, format: .dateTime.year().month().day())
                    .font(.headline)
                Text(row.startedAt, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(row.markerCount)")
                    .font(.headline.monospacedDigit())
                Text("打点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .trailing, spacing: 6) {
                Text(row.highlightStatus.displayName)
                    .font(.subheadline)
                Text(row.syncStatus.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    List {
        TrainingSessionRow(row: TrainingSessionRowViewData(session: TrainingSession.previewSessions[0]))
    }
}
