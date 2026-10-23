import SwiftUI
import UIKit

struct HighlightClipStateLabel: View {
    let item: HighlightClipReviewItem

    var body: some View {
        switch (item.confirmationState, item.isIncluded) {
        case (.defaultValue, _):
            Label("未看 · 默认保留", systemImage: "circle.dashed")
                .foregroundStyle(.orange)
                .accessibilityValue("未看，默认保留")
        case (.confirmed, true):
            Label("已保留", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityValue("已保留")
        case (.confirmed, false):
            Label("已排除", systemImage: "minus.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityValue("已排除")
        }
    }
}

struct HighlightClipNavigationStrip: View {
    @ObservedObject var viewModel: HighlightClipReviewViewModel
    let currentItemID: UUID
    let loadsMedia: Bool
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("全部片段")
                Spacer()
                if let next = viewModel.items.drop(while: { $0.id != currentItemID }).dropFirst()
                    .first(where: { $0.confirmationState == .defaultValue })
                {
                    Button("下一个未看") { onSelect(next.id) }
                        .frame(minHeight: 44)
                }
            }
            .font(.subheadline)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            Button { onSelect(item.id) } label: {
                                VStack(spacing: 4) {
                                    thumbnail(item)
                                        .frame(width: 88, height: 50)
                                        .clipped()
                                    Label("\(index + 1)", systemImage: stateSymbol(item))
                                        .font(.subheadline.monospacedDigit())
                                }
                                .padding(6)
                                .background(item.id == currentItemID ? Color.accentColor.opacity(0.12) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(item.id == currentItemID ? Color.accentColor : .clear, lineWidth: 2)
                                }
                                .opacity(item.isIncluded ? 1 : 0.55)
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                            .accessibilityLabel("跳到片段 \(index + 1)，\(stateDescription(item))")
                            .accessibilityAddTraits(item.id == currentItemID ? .isSelected : [])
                            .accessibilityIdentifier("ClipStrip-\(index + 1)")
                            .task {
                                if loadsMedia {
                                    await viewModel.loadThumbnail(itemID: item.id, targetSize: .init(width: 176, height: 100))
                                }
                            }
                        }
                    }
                    .padding(2)
                }
                .accessibilityIdentifier("ClipNavigationStrip")
                .onAppear { proxy.scrollTo(currentItemID, anchor: .center) }
                .onChange(of: currentItemID) { _, itemID in proxy.scrollTo(itemID, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ item: HighlightClipReviewItem) -> some View {
        if case let .loaded(data) = viewModel.thumbnailStates[item.id], let image = UIImage(data: data) {
            ClipFramingViewport(sourceSize: image.size, framing: item.framing ?? .original) {
                Image(uiImage: image).resizable().scaledToFit()
            }
            .background(.black)
        } else {
            Rectangle().fill(Color(uiColor: .secondarySystemFill))
                .overlay { Image(systemName: "film").foregroundStyle(.secondary) }
        }
    }

    private func stateSymbol(_ item: HighlightClipReviewItem) -> String {
        item.confirmationState == .defaultValue ? "circle.dashed"
            : (item.isIncluded ? "checkmark.circle.fill" : "minus.circle.fill")
    }

    private func stateDescription(_ item: HighlightClipReviewItem) -> String {
        item.confirmationState == .defaultValue ? "未看，默认保留"
            : (item.isIncluded ? "已保留" : "已排除")
    }
}
