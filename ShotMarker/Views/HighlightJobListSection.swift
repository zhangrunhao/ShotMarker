import SwiftUI

struct HighlightJobListSection: View {
    let jobs: [HighlightJob]
    let photoLibrarySavingJobIDs: Set<UUID>
    let onCancel: (UUID) -> Void
    let onRestart: (UUID) -> Void
    let onPlay: (UUID) -> Void
    let onSave: (UUID) -> Void
    let onClear: (UUID) -> Void

    var body: some View {
        if !jobs.isEmpty {
            Section("集锦任务") {
                ForEach(jobs) { job in
                    row(
                        HighlightJobRowViewData(
                            job: job,
                            isSavingToPhotoLibrary: photoLibrarySavingJobIDs.contains(job.id),
                        ),
                    )
                }
            }
        }
    }

    private func row(_ row: HighlightJobRowViewData) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.headline)
                Text(row.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let progressFraction = row.progressFraction {
                    ProgressView(value: progressFraction)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if row.showsPlay {
                    iconButton("播放集锦", systemImage: "play.circle") {
                        onPlay(row.id)
                    }
                }

                if row.showsSave {
                    iconButton("保存到相册", systemImage: "square.and.arrow.down") {
                        onSave(row.id)
                    }
                }

                if row.showsRestart {
                    iconButton("重新开始", systemImage: "arrow.clockwise") {
                        onRestart(row.id)
                    }
                }

                if row.showsCancel {
                    iconButton("取消任务", systemImage: "xmark.circle.fill") {
                        onCancel(row.id)
                    }
                }

                if row.showsClear {
                    iconButton("清理任务", systemImage: "trash") {
                        onClear(row.id)
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func iconButton(
        _ accessibilityLabel: String,
        systemImage: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.large)
        }
        .foregroundStyle(systemImage == "xmark.circle.fill" || systemImage == "trash" ? Color.red : Color.accentColor)
        .accessibilityLabel(accessibilityLabel)
    }
}
