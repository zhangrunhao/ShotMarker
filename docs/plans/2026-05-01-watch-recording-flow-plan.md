# Watch 训练打点流程实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**目标：** 构建第一个 Apple Watch 训练打点界面：一个大按钮，长按切换训练开始/结束状态，双击记录打点时间戳。

**架构：** Watch UI 保持很薄，把状态切换逻辑放到可测试的 `WatchTrainingViewModel`。View 负责 Watch 专属副作用，例如震动反馈；ViewModel 负责当前状态、开始时间、结束时间、打点时间戳和按钮展示数据。本计划不做手机同步、持久化、视频剪辑。

**技术栈：** SwiftUI、WatchKit、Foundation、XCTest、Xcode Watch App target。

## 范围

只实现以下行为：

1. Watch 上显示一个主要的大按钮。
2. 按钮有两个状态：已结束、已开始。
3. 按钮支持长按和双击。
4. 初始状态是已结束。已结束状态下长按进入已开始状态；已开始状态下长按回到已结束状态。
5. 两种状态的按钮文案和颜色不同。
6. 已开始状态下双击按钮，记录当前时间戳，并触发震动反馈。

不在本计划中实现：

- Watch 到 iPhone 的同步。
- 把完成的训练记录保存到手机端 store。
- 后台 workout session。
- 心率、HealthKit 或 GPS。
- 编辑或删除打点。

## 状态模型

使用明确的状态名，不使用动作名：

```swift
enum WatchTrainingState: Equatable {
    case ended
    case started
}
```

展示映射：

```swift
extension WatchTrainingState {
    var buttonTitle: String {
        switch self {
        case .ended:
            return "开始"
        case .started:
            return "结束"
        }
    }
}
```

说明：训练处于已结束状态时，长按可执行的动作是“开始”；训练处于已开始状态时，长按可执行的动作是“结束”。

## 任务 1：添加 Watch Target 骨架

**文件：**
- 修改：`ShotMarker.xcodeproj/project.pbxproj`
- 新建：`ShotMarkerWatchApp/ShotMarkerWatchApp.swift`
- 新建：`ShotMarkerWatchApp/Views/WatchTrainingView.swift`

**步骤 1：添加 Watch app target**

使用 Xcode，或谨慎编辑 project 文件，添加一个名为 `ShotMarkerWatchApp` 的 Watch App target。

期望目录结构：

```text
ShotMarkerWatchApp/
  ShotMarkerWatchApp.swift
  Views/
    WatchTrainingView.swift
```

**步骤 2：添加最小 app 入口**

```swift
import SwiftUI

@main
struct ShotMarkerWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchTrainingView()
        }
    }
}
```

**步骤 3：添加占位 View**

```swift
import SwiftUI

struct WatchTrainingView: View {
    var body: some View {
        Text("开始")
    }
}
```

**步骤 4：验证构建**

运行：

```bash
xcodebuild -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build
```

期望结果：iOS app 仍然能构建。如果已经有 Watch scheme，也用可用的 Watch simulator 构建一次。

**步骤 5：提交**

```bash
git add ShotMarker.xcodeproj ShotMarkerWatchApp
git commit -m "feat: 添加手表应用入口"
```

## 任务 2：创建可测试的 Watch ViewModel

**文件：**
- 新建：`ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift`
- 测试：`ShotMarkerTests/WatchTrainingViewModelTests.swift`

**步骤 1：先写失败测试**

```swift
import XCTest
@testable import ShotMarkerWatchApp

final class WatchTrainingViewModelTests: XCTestCase {
    func testInitialStateIsEnded() {
        let viewModel = WatchTrainingViewModel()

        XCTAssertEqual(viewModel.state, .ended)
        XCTAssertEqual(viewModel.buttonTitle, "开始")
        XCTAssertEqual(viewModel.markerCount, 0)
    }

    func testLongPressStartsTrainingFromEndedState() {
        let viewModel = WatchTrainingViewModel(now: { Date(timeIntervalSince1970: 1_000) })

        viewModel.handleLongPress()

        XCTAssertEqual(viewModel.state, .started)
        XCTAssertEqual(viewModel.startedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(viewModel.buttonTitle, "结束")
    }

    func testLongPressEndsTrainingFromStartedState() {
        var dates = [
            Date(timeIntervalSince1970: 1_000),
            Date(timeIntervalSince1970: 1_600)
        ]
        let viewModel = WatchTrainingViewModel(now: { dates.removeFirst() })

        viewModel.handleLongPress()
        viewModel.handleLongPress()

        XCTAssertEqual(viewModel.state, .ended)
        XCTAssertEqual(viewModel.endedAt, Date(timeIntervalSince1970: 1_600))
    }
}
```

**步骤 2：运行测试，确认失败**

运行：

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ShotMarkerTests/WatchTrainingViewModelTests
```

期望结果：失败，原因是 `WatchTrainingViewModel` 不存在或尚未实现。

**步骤 3：实现最小 ViewModel**

```swift
import Foundation

enum WatchTrainingState: Equatable {
    case ended
    case started
}

@MainActor
final class WatchTrainingViewModel: ObservableObject {
    @Published private(set) var state: WatchTrainingState = .ended
    @Published private(set) var startedAt: Date?
    @Published private(set) var endedAt: Date?
    @Published private(set) var markers: [Date] = []

    private let now: () -> Date

    var buttonTitle: String {
        switch state {
        case .ended:
            return "开始"
        case .started:
            return "结束"
        }
    }

    var markerCount: Int {
        markers.count
    }

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func handleLongPress() {
        switch state {
        case .ended:
            startedAt = now()
            endedAt = nil
            markers = []
            state = .started
        case .started:
            endedAt = now()
            state = .ended
        }
    }
}
```

**步骤 4：运行测试**

运行同一个 `xcodebuild test` 命令。

期望结果：测试通过。

**步骤 5：提交**

```bash
git add ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift ShotMarkerTests/WatchTrainingViewModelTests.swift
git commit -m "feat: 添加手表训练状态模型"
```

## 任务 3：双击记录时间戳

**文件：**
- 修改：`ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift`
- 修改：`ShotMarkerTests/WatchTrainingViewModelTests.swift`

**步骤 1：先写失败测试**

```swift
func testDoubleTapDoesNothingWhenEnded() {
    let viewModel = WatchTrainingViewModel(now: { Date(timeIntervalSince1970: 2_000) })

    let didRecord = viewModel.handleDoubleTap()

    XCTAssertFalse(didRecord)
    XCTAssertEqual(viewModel.markers, [])
}

func testDoubleTapRecordsMarkerWhenStarted() {
    var dates = [
        Date(timeIntervalSince1970: 1_000),
        Date(timeIntervalSince1970: 1_120)
    ]
    let viewModel = WatchTrainingViewModel(now: { dates.removeFirst() })

    viewModel.handleLongPress()
    let didRecord = viewModel.handleDoubleTap()

    XCTAssertTrue(didRecord)
    XCTAssertEqual(viewModel.markers, [Date(timeIntervalSince1970: 1_120)])
    XCTAssertEqual(viewModel.markerCount, 1)
}
```

**步骤 2：运行测试，确认失败**

运行：

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ShotMarkerTests/WatchTrainingViewModelTests
```

期望结果：失败，原因是 `handleDoubleTap()` 不存在。

**步骤 3：实现最小方法**

```swift
@discardableResult
func handleDoubleTap() -> Bool {
    guard state == .started else {
        return false
    }

    markers.append(now())
    return true
}
```

**步骤 4：运行测试**

运行同一个 `xcodebuild test` 命令。

期望结果：全部 `WatchTrainingViewModelTests` 通过。

**步骤 5：提交**

```bash
git add ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift ShotMarkerTests/WatchTrainingViewModelTests.swift
git commit -m "feat: 添加手表双击打点"
```

## 任务 4：构建单按钮 Watch UI

**文件：**
- 修改：`ShotMarkerWatchApp/Views/WatchTrainingView.swift`
- 修改：`ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift`

**步骤 1：给 ViewModel 增加展示颜色**

```swift
import SwiftUI

var buttonColor: Color {
    switch state {
    case .ended:
        return .green
    case .started:
        return .red
    }
}
```

使用绿色表示“开始”动作，红色表示“结束”动作。

**步骤 2：实现按钮 UI**

```swift
import SwiftUI
import WatchKit

struct WatchTrainingView: View {
    @StateObject private var viewModel = WatchTrainingViewModel()

    var body: some View {
        VStack(spacing: 12) {
            Button {
            } label: {
                Text(viewModel.buttonTitle)
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 96)
            }
            .buttonStyle(.plain)
            .background(viewModel.buttonColor)
            .clipShape(Circle())
            .onLongPressGesture {
                viewModel.handleLongPress()
            }
            .onTapGesture(count: 2) {
                if viewModel.handleDoubleTap() {
                    WKInterfaceDevice.current().play(.success)
                }
            }

            Text("\(viewModel.markerCount) 个打点")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
```

**步骤 3：手动检查 Watch UI**

在 Watch simulator 或真机中打开 Watch app。

期望结果：

- 初始按钮文案是 `开始`。
- 初始按钮是绿色。
- 长按后文案变成 `结束`。
- 已开始状态按钮是红色。
- 已开始状态下双击会增加打点数量，并触发震动。
- 再次长按后回到 `开始`。

**步骤 4：提交**

```bash
git add ShotMarkerWatchApp
git commit -m "feat: 添加手表训练按钮界面"
```

## 任务 5：最终验证

**文件：**
- 预期不需要修改代码。

**步骤 1：运行全部单元测试**

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17'
```

期望结果：全部测试通过。

**步骤 2：构建 Watch app**

使用一个可用的 Watch simulator destination：

```bash
xcodebuild -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' CODE_SIGNING_ALLOWED=NO build
```

期望结果：Watch target 构建成功。如果本机没有这个 simulator 名称，先运行 `xcrun simctl list devices available`，选择已安装的 watchOS simulator。

**步骤 3：手动行为检查清单**

- 只显示一个大按钮。
- 初始视觉状态是已结束：绿色 `开始`。
- 长按进入已开始状态：红色 `结束`。
- 再次长按回到已结束状态。
- 已结束状态下双击不记录时间戳。
- 已开始状态下双击记录一个时间戳。
- 成功双击打点后触发 Watch 震动反馈。

**步骤 4：如验证发现小问题，再提交修复**

只有在验证中做了小修复时才需要提交：

```bash
git add ShotMarkerWatchApp ShotMarkerTests ShotMarker.xcodeproj
git commit -m "fix: 修复手表训练按钮验证问题"
```
