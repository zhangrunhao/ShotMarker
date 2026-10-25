import Combine

@MainActor
final class ClipEditorOperations: ObservableObject {
    enum Mode: Equatable {
        case framing, number, none

        var title: String {
            switch self {
            case .framing: "取景"
            case .number: "序号"
            case .none: "操作关闭"
            }
        }
    }

    @Published private(set) var mode: Mode = .framing
    @Published var isExpanded = false

    func toggleFraming() { mode = mode == .framing ? .none : .framing }
    func toggleNumber() { mode = mode == .number ? .framing : .number }
}
