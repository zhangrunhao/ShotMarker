import SwiftUI

struct TrainingSessionRow: View {
    let row: TrainingSessionRowViewData
    let isSelectionMode: Bool
    let isSelected: Bool

    init(
        row: TrainingSessionRowViewData,
        isSelectionMode: Bool = false,
        isSelected: Bool = false,
    ) {
        self.row = row
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityLabel(isSelected ? "已选择" : "未选择")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(titleText)
                    .font(.headline)
                    .lineLimit(1)
                Text(descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    private var titleText: String {
        row.titleDate.formatted(.dateTime.year().month().day())
    }

    private var descriptionText: String {
        let startText = formattedRangeEndpoint(row.descriptionStartedAt, includeDate: shouldShowDateInDescription)
        let endText = formattedRangeEndpoint(row.descriptionEndedAt, includeDate: shouldShowDateInDescription)

        return "\(startText) -> \(endText)"
    }

    private var shouldShowDateInDescription: Bool {
        !Calendar.current.isDate(row.descriptionStartedAt, inSameDayAs: row.descriptionEndedAt)
    }

    private func formattedRangeEndpoint(_ date: Date, includeDate: Bool) -> String {
        if includeDate {
            return date.formatted(.dateTime.month().day().hour().minute())
        }

        return date.formatted(.dateTime.hour().minute())
    }
}

#if DEBUG
    #Preview {
        List {
            TrainingSessionRow(row: TrainingSessionRowViewData(session: TrainingSession.previewSessions[0]))
        }
    }
#endif
