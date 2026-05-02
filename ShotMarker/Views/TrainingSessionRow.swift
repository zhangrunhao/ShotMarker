import SwiftUI

struct TrainingSessionRow: View {
    let row: TrainingSessionRowViewData

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.startedAt, format: .dateTime.year().month().day())
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
        }
        .padding(.vertical, 6)
    }
}

#if DEBUG
    #Preview {
        List {
            TrainingSessionRow(row: TrainingSessionRowViewData(session: TrainingSession.previewSessions[0]))
        }
    }
#endif
