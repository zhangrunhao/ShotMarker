import SwiftUI

struct TrainingSessionRowPresentation: Equatable {
    let titleText: String
    let timeRangeText: String
    let markerCountText: String
    let markerUnitText: String
    let includesDateInTimeRange: Bool

    init(row: TrainingSessionRowViewData, calendar: Calendar = .current) {
        includesDateInTimeRange = !calendar.isDate(
            row.descriptionStartedAt,
            inSameDayAs: row.descriptionEndedAt,
        )
        titleText = row.titleDate.formatted(.dateTime.year().month().day())
        timeRangeText = Self.timeRangeText(
            startedAt: row.descriptionStartedAt,
            endedAt: row.descriptionEndedAt,
            includesDate: includesDateInTimeRange,
        )
        markerCountText = "\(row.markerCount)"
        markerUnitText = "打点"
    }

    private static func timeRangeText(startedAt: Date, endedAt: Date, includesDate: Bool) -> String {
        let startText = formattedRangeEndpoint(startedAt, includeDate: includesDate)
        let endText = formattedRangeEndpoint(endedAt, includeDate: includesDate)

        return "\(startText) - \(endText)"
    }

    private static func formattedRangeEndpoint(_ date: Date, includeDate: Bool) -> String {
        if includeDate {
            return date.formatted(.dateTime.month().day().hour().minute())
        }

        return date.formatted(.dateTime.hour().minute())
    }
}

struct TrainingSessionRow: View {
    let row: TrainingSessionRowViewData
    let isSelectionMode: Bool
    let isSelected: Bool
    private let presentation: TrainingSessionRowPresentation

    init(
        row: TrainingSessionRowViewData,
        isSelectionMode: Bool = false,
        isSelected: Bool = false,
    ) {
        self.row = row
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        presentation = TrainingSessionRowPresentation(row: row)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityLabel(isSelected ? "已选择" : "未选择")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.titleText)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    Text(presentation.timeRangeText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 2) {
                Text(presentation.markerCountText)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .minimumScaleFactor(0.8)
                Text(presentation.markerUnitText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 54)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(isSelected ? 0.14 : 0.08))
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        List {
            TrainingSessionRow(row: TrainingSessionRowViewData(session: TrainingSession.previewSessions[0]))
        }
    }
#endif
