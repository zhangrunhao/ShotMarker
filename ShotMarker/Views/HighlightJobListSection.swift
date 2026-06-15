import SwiftUI

struct HighlightJobListSection: View {
    let jobs: [HighlightJob]
    let photoLibrarySavingJobIDs: Set<UUID>
    let onCancel: (UUID) -> Void
    let onRestart: (UUID) -> Void
    let onPlay: (UUID) -> Void
    let onSave: (UUID) -> Void
    let onClear: (UUID) -> Void
    @State private var actionConfirmation: HighlightJobActionConfirmation?

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
            .alert(actionConfirmation?.title ?? "", isPresented: actionConfirmationBinding) {
                Button("取消", role: .cancel) {}
                if let actionConfirmation {
                    Button(
                        actionConfirmation.confirmButtonTitle,
                        role: actionConfirmation.isDestructive ? .destructive : nil,
                    ) {
                        confirm(actionConfirmation)
                    }
                }
            } message: {
                Text(actionConfirmation?.message ?? "")
            }
        }
    }

    @ViewBuilder
    private func row(_ row: HighlightJobRowViewData) -> some View {
        switch row.actionLayout {
        case .completedActionBar:
            completedActionBarRow(row)
        case .compact:
            compactRow(row)
        }
    }

    private func completedActionBarRow(_ row: HighlightJobRowViewData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            rowTextContent(row)

            HStack(spacing: 8) {
                actionBarButton("播放", systemImage: "play.circle.fill", accessibilityLabel: "播放集锦") {
                    onPlay(row.id)
                }

                actionBarButton("保存", systemImage: "square.and.arrow.down.fill", accessibilityLabel: "保存到相册") {
                    actionConfirmation = .save(jobID: row.id)
                }

                actionBarButton("删除", systemImage: "trash.fill", tint: .red, accessibilityLabel: "删除任务") {
                    actionConfirmation = .clear(jobID: row.id)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private func compactRow(_ row: HighlightJobRowViewData) -> some View {
        HStack(spacing: 12) {
            rowTextContent(row)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if row.showsPlay {
                    iconButton("播放集锦", systemImage: "play.circle") {
                        onPlay(row.id)
                    }
                }

                if row.showsSave {
                    iconButton("保存到相册", systemImage: "square.and.arrow.down") {
                        actionConfirmation = .save(jobID: row.id)
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
                    iconButton("删除任务", systemImage: "trash") {
                        actionConfirmation = .clear(jobID: row.id)
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func rowTextContent(_ row: HighlightJobRowViewData) -> some View {
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

    private func actionBarButton(
        _ title: String,
        systemImage: String,
        tint: Color = .accentColor,
        accessibilityLabel: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 8)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(tint)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var actionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { actionConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    actionConfirmation = nil
                }
            },
        )
    }

    private func confirm(_ confirmation: HighlightJobActionConfirmation) {
        actionConfirmation = nil
        switch confirmation.action {
        case let .save(jobID):
            onSave(jobID)
        case let .clear(jobID):
            onClear(jobID)
        }
    }
}
