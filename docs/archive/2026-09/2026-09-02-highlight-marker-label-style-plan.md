# ShotMarker 1.3 片段序数标识样式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在集锦创建页提供基于首个已选视频完整缩略图的片段序数预览与全局样式设置，并保证相同的归一化样式被持久化、固化到任务和用于最终导出。

**Architecture:** 新增 `MarkerLabelStyle` 作为唯一可编码样式值，随 `ClipSettings` 从 `UserDefaults` 流入 `HighlightJob` 快照；新增无 UI 状态的 `MarkerLabelLayout`，让 SwiftUI 预览和 Core Image 导出共用同一套坐标、边界与原点转换。`MarkerLabelSettingsView` 只负责显示和交互，`HighlightJobRunner` 显式把任务内样式传给 `VideoClipEditingService`，服务不读取全局设置。

**Tech Stack:** Swift 5 language mode、SwiftUI、UIKit、Photos/PhotosUI、AVFoundation、Core Image、XCTest、Xcode 26.6 / Swift 6.3.3 toolchain

**Spec:** `docs/archive/2026-09/2026-09-02-highlight-marker-label-style-spec.md`

**执行结果（2026-09-02）：** Tasks 1–6 已按任务分别提交，Task 7 完成当前文档更新与归档；iPhone 189 项、Watch 30 项测试和 Release Simulator 构建通过。竖屏完整画幅、占位、拖动边界、三项调节、任务快照、导出和本地恢复已有人工或自动证据；VoiceOver 与独立横屏首项预览不记录为已通过，由用户继续人工验收。

## Global Constraints

- 所有开发直接在 `main` 进行；不得创建分支或 git worktree。每次编辑前执行 `git branch --show-current` 并确认输出为 `main`。
- 计划编写时工作区已有用户修改：`docs/README.md`、`docs/changes/2026-08-21-app-store-1-2-submission-plan.md`、本 spec。不得丢弃、覆盖或把无关修改混入中间提交。
- 一个集锦只使用一组全局序数样式；不得增加逐片段样式、显示开关、字体/颜色/圆角/内边距设置、Watch 设置、Analytics 事件或远端字段。
- `fontSizeRatio` 范围为 `0.04...0.16`、步长 `0.01`、默认 `0.10`；字号等于最终完整画面短边乘以该比例，不再叠加绝对最小或最大字号。
- `normalizedCenterX`、`normalizedCenterY` 范围均为 `0...1`，默认分别为 `0.15`、`0.10`；原点为完整画面左上角，向右和向下为正方向。
- `textOpacity`、`backgroundOpacity` 范围均为 `0...1`、步长 `0.05`，默认分别为 `1.00`、`0.60`，二者必须独立生效。
- 所有有限越界样式值夹取到最近边界，非有限值回退到对应默认值；加载、保存、任务创建、预览和导出必须调用同一个 `MarkerLabelStyle.normalized` 规则。
- 1.2 `ClipSettings` 和嵌套旧 `clipSettings` 的 `HighlightJob` 必须保留原有剪辑时长并补入默认样式；样式缺少单个字段时只回退该字段，错误字段类型继续抛出解码错误。
- 预览只使用选择阶段已有的 `selectedVideoItems.first?.thumbnailData`；不得额外请求视频、播放视频、下载完整资源或把缩略图请求的 `isNetworkAccessAllowed` 改为 `true`。
- 预览和导出保留现有白色粗体等宽数字、黑色圆角底、水平/垂直内边距和 `number/total`、`start-end/total` 文字规则。
- 样式只保存在本地 `UserDefaults` 和本地任务 JSON；不得上传缩略图、样式、位置、透明度或自由文本，也不得新增相关日志。
- iPhone App 和随包 Watch App 的 `MARKETING_VERSION` 从 `1.2` 更新到 `1.3`；计划编写时两个产品 target 的 `CURRENT_PROJECT_VERSION` 都是 `3`，本 Change 必须保持为 `3`。测试 target 的现有版本值不需要同步。
- 工程使用文件系统同步组；把新的 `.swift` 文件放入现有 `ShotMarker/` 或 `ShotMarkerTests/` 目录即可进入对应 target，不手工添加 PBX file reference。
- 实现完成后先更新 `docs/current/`，再把本 spec 和本 plan 移入 `docs/archive/2026-09/`；`docs/current/` 每个文件必须保持在 300 行以内。

## File Map

**Create**

- `ShotMarker/Models/MarkerLabelStyle.swift`：样式字段、默认值、范围、逐字段兼容解码、统一规范化与规范化编码。
- `ShotMarker/Services/MarkerLabelLayout.swift`：aspect-fit 画面矩形、归一化中心/预览坐标互转、边界限制和 Core Image 原点转换。
- `ShotMarker/Views/MarkerLabelSettingsView.swift`：真实缩略图或占位预览、拖动、三个调节项和 VoiceOver 自定义操作。
- `ShotMarkerTests/MarkerLabelStyleTests.swift`：默认值、范围、非有限值、逐字段解码和类型错误测试。
- `ShotMarkerTests/MarkerLabelLayoutTests.swift`：坐标、横竖屏、长短标签、字号尺寸和 Core Image 转换测试。
- `ShotMarkerTests/PhotoLibraryVideoAssetProviderTests.swift`：完整画幅、轻量和无网络缩略图请求契约。
- `ShotMarkerTests/Fixtures/HighlightJob-1.2.json`：不含 `markerLabelStyle` 的 1.2 任务 fixture。

**Modify**

- `ShotMarker/Models/ClipSettings.swift:3-41`：加入样式、1.2 兼容解码、规范化保存。
- `ShotMarker/Services/HighlightJobRunner.swift:4-92`：把任务快照样式显式传给导出闭包。
- `ShotMarker/ViewModels/HighlightJobManager.swift:38-75,94-130`：生产导出闭包接收样式，创建任务时固化规范化设置。
- `ShotMarker/Services/VideoClipEditingService.swift:45-65,99-114,201-315,479-576`：移除固定字号/位置/不透明度，按传入样式绘制和放置。
- `ShotMarker/Services/PhotoLibraryVideoAssetProvider.swift:46-63`：用 `.aspectFit` 取得完整画幅缩略图，保持禁止网络访问。
- `ShotMarker/Views/TrainingSessionHighlightView.swift:58-65,185-253`：在已选视频与覆盖结果之间组装新设置区。
- `ShotMarkerTests/ClipSettingsStoreTests.swift:20-37`：旧设置、新设置、规范化保存和恢复测试。
- `ShotMarkerTests/HighlightJobStoreTests.swift:24-31,83-117`：1.2 fixture 与新版样式往返。
- `ShotMarkerTests/HighlightJobRunnerTests.swift:19-46,78-112`：任务样式传递和重启快照测试。
- `ShotMarkerTests/HighlightJobManagerTests.swift:33-64,366-393`：任务创建快照及闭包签名更新。
- `ShotMarkerTests/VideoClipEditingServiceTests.swift:40-356`：自定义字号、独立不透明度、位置、全透明和现有回归。
- `ShotMarker.xcodeproj/project.pbxproj:438-479,679-747`：产品 target 的 `MARKETING_VERSION = 1.3`，构建号不变。
- `docs/README.md`、`docs/current/product.md`、`docs/current/architecture.md`、`docs/current/quality.md`、`docs/current/release.md`、`docs/current/status.md`：验证后更新当前事实和活动 Change 入口。

**Archive after verified completion**

- `docs/archive/2026-09/2026-09-02-highlight-marker-label-style-spec.md`
- `docs/archive/2026-09/2026-09-02-highlight-marker-label-style-plan.md`

---

### Task 1: 建立兼容的样式与剪辑设置模型

**Files:**

- Create: `ShotMarker/Models/MarkerLabelStyle.swift`
- Create: `ShotMarkerTests/MarkerLabelStyleTests.swift`
- Modify: `ShotMarker/Models/ClipSettings.swift:3-41`
- Modify: `ShotMarkerTests/ClipSettingsStoreTests.swift:20-37`

**Interfaces:**

- Produces: `MarkerLabelStyle.default`
- Produces: `MarkerLabelStyle.fontSizeRatioRange`, `opacityRange`, `normalizedCenterRange`
- Produces: `MarkerLabelStyle.normalized: MarkerLabelStyle`
- Produces: `ClipSettings.init(secondsBeforeMarker:secondsAfterMarker:markerLabelStyle:)`
- Produces: `ClipSettings.normalized: ClipSettings`
- Preserves: existing two-argument `ClipSettings(...)` call sites through `markerLabelStyle: MarkerLabelStyle = .default`

- [ ] **Step 1: Write failing model and compatibility tests**

Create `ShotMarkerTests/MarkerLabelStyleTests.swift` with these cases:

```swift
@testable import ShotMarker
import XCTest

final class MarkerLabelStyleTests: XCTestCase {
    func testDefaultMatchesProductSpecification() {
        XCTAssertEqual(
            MarkerLabelStyle.default,
            MarkerLabelStyle(
                fontSizeRatio: 0.10,
                normalizedCenterX: 0.15,
                normalizedCenterY: 0.10,
                textOpacity: 1.00,
                backgroundOpacity: 0.60,
            ),
        )
    }

    func testNormalizedClampsFiniteValuesAndDefaultsNonFiniteValues() {
        let style = MarkerLabelStyle(
            fontSizeRatio: -1,
            normalizedCenterX: 2,
            normalizedCenterY: .nan,
            textOpacity: -Double.infinity,
            backgroundOpacity: 4,
        )

        XCTAssertEqual(
            style.normalized,
            MarkerLabelStyle(
                fontSizeRatio: 0.04,
                normalizedCenterX: 1,
                normalizedCenterY: 0.10,
                textOpacity: 1,
                backgroundOpacity: 1,
            ),
        )
    }

    func testDecodingMissingStyleFieldFallsBackOnlyThatField() throws {
        let data = Data(
            #"{"fontSizeRatio":0.12,"normalizedCenterX":0.35,"textOpacity":0.75,"backgroundOpacity":0.25}"#.utf8,
        )

        let decoded = try JSONDecoder().decode(MarkerLabelStyle.self, from: data)

        XCTAssertEqual(decoded.fontSizeRatio, 0.12)
        XCTAssertEqual(decoded.normalizedCenterX, 0.35)
        XCTAssertEqual(decoded.normalizedCenterY, 0.10)
        XCTAssertEqual(decoded.textOpacity, 0.75)
        XCTAssertEqual(decoded.backgroundOpacity, 0.25)
    }

    func testDecodingWrongFieldTypeThrows() {
        let data = Data(#"{"fontSizeRatio":"large"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(MarkerLabelStyle.self, from: data))
    }

    func testEncodingWritesNormalizedFiniteValues() throws {
        let style = MarkerLabelStyle(
            fontSizeRatio: .infinity,
            normalizedCenterX: -1,
            normalizedCenterY: 2,
            textOpacity: 0.4,
            backgroundOpacity: 0.2,
        )

        let decoded = try JSONDecoder().decode(
            MarkerLabelStyle.self,
            from: JSONEncoder().encode(style),
        )

        XCTAssertEqual(
            decoded,
            MarkerLabelStyle(
                fontSizeRatio: 0.10,
                normalizedCenterX: 0,
                normalizedCenterY: 1,
                textOpacity: 0.4,
                backgroundOpacity: 0.2,
            ),
        )
    }
}
```

Extend `ShotMarkerTests/ClipSettingsStoreTests.swift` with:

```swift
func testLegacyClipSettingsKeepsDurationsAndAddsDefaultStyle() throws {
    let data = Data(#"{"secondsBeforeMarker":7,"secondsAfterMarker":3}"#.utf8)

    let decoded = try JSONDecoder().decode(ClipSettings.self, from: data)

    XCTAssertEqual(decoded.secondsBeforeMarker, 7)
    XCTAssertEqual(decoded.secondsAfterMarker, 3)
    XCTAssertEqual(decoded.markerLabelStyle, .default)
}

func testClipSettingsRoundTripKeepsMarkerLabelStyle() throws {
    let settings = ClipSettings(
        secondsBeforeMarker: 6,
        secondsAfterMarker: 2,
        markerLabelStyle: MarkerLabelStyle(
            fontSizeRatio: 0.14,
            normalizedCenterX: 0.7,
            normalizedCenterY: 0.8,
            textOpacity: 0.65,
            backgroundOpacity: 0.35,
        ),
    )

    let decoded = try JSONDecoder().decode(
        ClipSettings.self,
        from: JSONEncoder().encode(settings),
    )

    XCTAssertEqual(decoded, settings)
}

func testStoreSavesAndRestoresNormalizedStyle() {
    let store = ClipSettingsStore(userDefaults: userDefaults)
    let settings = ClipSettings(
        secondsBeforeMarker: 6,
        secondsAfterMarker: 1,
        markerLabelStyle: MarkerLabelStyle(
            fontSizeRatio: 2,
            normalizedCenterX: -1,
            normalizedCenterY: 0.5,
            textOpacity: .nan,
            backgroundOpacity: 0.25,
        ),
    )

    store.save(settings)

    XCTAssertEqual(
        store.load().markerLabelStyle,
        MarkerLabelStyle(
            fontSizeRatio: 0.16,
            normalizedCenterX: 0,
            normalizedCenterY: 0.5,
            textOpacity: 1,
            backgroundOpacity: 0.25,
        ),
    )
}
```

Update the existing default assertion to include `.default` style while retaining the two-argument initializer compatibility:

```swift
XCTAssertEqual(
    ClipSettings.default,
    ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4, markerLabelStyle: .default),
)
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/MarkerLabelStyleTests \
  -only-testing:ShotMarkerTests/ClipSettingsStoreTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build fails because `MarkerLabelStyle`, `ClipSettings.markerLabelStyle`, and `ClipSettings.normalized` do not exist.

- [ ] **Step 3: Implement the single normalization and Codable contract**

Create `ShotMarker/Models/MarkerLabelStyle.swift`:

```swift
import Foundation

struct MarkerLabelStyle: Codable, Equatable {
    var fontSizeRatio: Double
    var normalizedCenterX: Double
    var normalizedCenterY: Double
    var textOpacity: Double
    var backgroundOpacity: Double

    static let fontSizeRatioRange = 0.04 ... 0.16
    static let normalizedCenterRange = 0.0 ... 1.0
    static let opacityRange = 0.0 ... 1.0

    static let `default` = MarkerLabelStyle(
        fontSizeRatio: 0.10,
        normalizedCenterX: 0.15,
        normalizedCenterY: 0.10,
        textOpacity: 1.00,
        backgroundOpacity: 0.60,
    )

    private enum CodingKeys: String, CodingKey {
        case fontSizeRatio
        case normalizedCenterX
        case normalizedCenterY
        case textOpacity
        case backgroundOpacity
    }

    init(
        fontSizeRatio: Double,
        normalizedCenterX: Double,
        normalizedCenterY: Double,
        textOpacity: Double,
        backgroundOpacity: Double,
    ) {
        self.fontSizeRatio = fontSizeRatio
        self.normalizedCenterX = normalizedCenterX
        self.normalizedCenterY = normalizedCenterY
        self.textOpacity = textOpacity
        self.backgroundOpacity = backgroundOpacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default
        self.init(
            fontSizeRatio: try container.decodeIfPresent(Double.self, forKey: .fontSizeRatio)
                ?? defaults.fontSizeRatio,
            normalizedCenterX: try container.decodeIfPresent(Double.self, forKey: .normalizedCenterX)
                ?? defaults.normalizedCenterX,
            normalizedCenterY: try container.decodeIfPresent(Double.self, forKey: .normalizedCenterY)
                ?? defaults.normalizedCenterY,
            textOpacity: try container.decodeIfPresent(Double.self, forKey: .textOpacity)
                ?? defaults.textOpacity,
            backgroundOpacity: try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity)
                ?? defaults.backgroundOpacity,
        )
        self = normalized
    }

    func encode(to encoder: Encoder) throws {
        let value = normalized
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.fontSizeRatio, forKey: .fontSizeRatio)
        try container.encode(value.normalizedCenterX, forKey: .normalizedCenterX)
        try container.encode(value.normalizedCenterY, forKey: .normalizedCenterY)
        try container.encode(value.textOpacity, forKey: .textOpacity)
        try container.encode(value.backgroundOpacity, forKey: .backgroundOpacity)
    }

    var normalized: MarkerLabelStyle {
        let defaults = Self.default
        return MarkerLabelStyle(
            fontSizeRatio: Self.normalize(
                fontSizeRatio,
                in: Self.fontSizeRatioRange,
                fallback: defaults.fontSizeRatio,
            ),
            normalizedCenterX: Self.normalize(
                normalizedCenterX,
                in: Self.normalizedCenterRange,
                fallback: defaults.normalizedCenterX,
            ),
            normalizedCenterY: Self.normalize(
                normalizedCenterY,
                in: Self.normalizedCenterRange,
                fallback: defaults.normalizedCenterY,
            ),
            textOpacity: Self.normalize(
                textOpacity,
                in: Self.opacityRange,
                fallback: defaults.textOpacity,
            ),
            backgroundOpacity: Self.normalize(
                backgroundOpacity,
                in: Self.opacityRange,
                fallback: defaults.backgroundOpacity,
            ),
        )
    }

    private static func normalize(
        _ value: Double,
        in range: ClosedRange<Double>,
        fallback: Double,
    ) -> Double {
        guard value.isFinite else {
            return fallback
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
```

Replace the model portion of `ShotMarker/Models/ClipSettings.swift` with:

```swift
struct ClipSettings: Codable, Equatable {
    var secondsBeforeMarker: TimeInterval
    var secondsAfterMarker: TimeInterval
    var markerLabelStyle: MarkerLabelStyle

    static let `default` = ClipSettings(
        secondsBeforeMarker: 9,
        secondsAfterMarker: 4,
        markerLabelStyle: .default,
    )

    private enum CodingKeys: String, CodingKey {
        case secondsBeforeMarker
        case secondsAfterMarker
        case markerLabelStyle
    }

    init(
        secondsBeforeMarker: TimeInterval,
        secondsAfterMarker: TimeInterval,
        markerLabelStyle: MarkerLabelStyle = .default,
    ) {
        self.secondsBeforeMarker = secondsBeforeMarker
        self.secondsAfterMarker = secondsAfterMarker
        self.markerLabelStyle = markerLabelStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        secondsBeforeMarker = try container.decode(TimeInterval.self, forKey: .secondsBeforeMarker)
        secondsAfterMarker = try container.decode(TimeInterval.self, forKey: .secondsAfterMarker)
        markerLabelStyle = try container.decodeIfPresent(
            MarkerLabelStyle.self,
            forKey: .markerLabelStyle,
        ) ?? .default
        self = normalized
    }

    func encode(to encoder: Encoder) throws {
        let value = normalized
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.secondsBeforeMarker, forKey: .secondsBeforeMarker)
        try container.encode(value.secondsAfterMarker, forKey: .secondsAfterMarker)
        try container.encode(value.markerLabelStyle, forKey: .markerLabelStyle)
    }

    var normalized: ClipSettings {
        ClipSettings(
            secondsBeforeMarker: secondsBeforeMarker,
            secondsAfterMarker: secondsAfterMarker,
            markerLabelStyle: markerLabelStyle.normalized,
        )
    }
}
```

Change `ClipSettingsStore.save` to encode `settings.normalized`. Keep the existing behavior of returning `.default` when the whole stored payload cannot be decoded.

- [ ] **Step 4: Run focused tests and verify compatibility passes**

Run the Step 2 command again.

Expected: `MarkerLabelStyleTests` and `ClipSettingsStoreTests` pass; existing two-argument `ClipSettings` call sites still compile.

- [ ] **Step 5: Commit the model boundary**

```bash
git add \
  ShotMarker/Models/MarkerLabelStyle.swift \
  ShotMarker/Models/ClipSettings.swift \
  ShotMarkerTests/MarkerLabelStyleTests.swift \
  ShotMarkerTests/ClipSettingsStoreTests.swift
git commit -m "feat: 新增片段序数样式模型与兼容设置"
```

---

### Task 2: 建立预览与导出共享的几何语义

**Files:**

- Create: `ShotMarker/Services/MarkerLabelLayout.swift`
- Create: `ShotMarkerTests/MarkerLabelLayoutTests.swift`

**Interfaces:**

- Consumes: normalized center values from `MarkerLabelStyle`
- Produces: `MarkerLabelLayout.aspectFitRect(contentSize:in:)`
- Produces: `MarkerLabelLayout.clampedOrigin(for:labelSize:in:)`
- Produces: `MarkerLabelLayout.previewCenter(for:labelSize:in:)`
- Produces: `MarkerLabelLayout.normalizedCenter(forPreviewPoint:labelSize:in:)`
- Produces: `MarkerLabelLayout.coreImageOrigin(for:labelSize:in:)`

- [ ] **Step 1: Write failing geometry tests**

Create `ShotMarkerTests/MarkerLabelLayoutTests.swift`:

```swift
@testable import ShotMarker
import XCTest

final class MarkerLabelLayoutTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
    private let labelSize = CGSize(width: 20, height: 10)

    func testAspectFitRectPreservesVerticalImageInsideLandscapePreview() {
        let result = MarkerLabelLayout.aspectFitRect(
            contentSize: CGSize(width: 1080, height: 1920),
            in: CGRect(x: 0, y: 0, width: 320, height: 180),
        )

        XCTAssertEqual(result.minX, 109.375, accuracy: 0.001)
        XCTAssertEqual(result.minY, 0, accuracy: 0.001)
        XCTAssertEqual(result.width, 101.25, accuracy: 0.001)
        XCTAssertEqual(result.height, 180, accuracy: 0.001)
    }

    func testTopLeftCenterAndBottomRightStayInsideFrame() {
        XCTAssertEqual(
            MarkerLabelLayout.previewCenter(
                for: CGPoint(x: 0, y: 0),
                labelSize: labelSize,
                in: frame,
            ),
            CGPoint(x: 10, y: 5),
        )
        XCTAssertEqual(
            MarkerLabelLayout.previewCenter(
                for: CGPoint(x: 0.5, y: 0.5),
                labelSize: labelSize,
                in: frame,
            ),
            CGPoint(x: 100, y: 50),
        )
        XCTAssertEqual(
            MarkerLabelLayout.previewCenter(
                for: CGPoint(x: 1, y: 1),
                labelSize: labelSize,
                in: frame,
            ),
            CGPoint(x: 190, y: 95),
        )
    }

    func testDraggedPointReturnsClampedNormalizedCenter() {
        let result = MarkerLabelLayout.normalizedCenter(
            forPreviewPoint: CGPoint(x: 220, y: 120),
            labelSize: labelSize,
            in: frame,
        )

        XCTAssertEqual(result.x, 0.95, accuracy: 0.0001)
        XCTAssertEqual(result.y, 0.95, accuracy: 0.0001)
    }

    func testLongLabelMovesFartherInsideAtSameNormalizedCenter() {
        let center = CGPoint(x: 0.98, y: 0.5)
        let shortOrigin = MarkerLabelLayout.clampedOrigin(
            for: center,
            labelSize: CGSize(width: 20, height: 10),
            in: frame,
        )
        let longOrigin = MarkerLabelLayout.clampedOrigin(
            for: center,
            labelSize: CGSize(width: 100, height: 10),
            in: frame,
        )

        XCTAssertEqual(shortOrigin.x, 180)
        XCTAssertEqual(longOrigin.x, 100)
    }

    func testLandscapeAndPortraitUseSameNormalizedSemantics() {
        let normalized = CGPoint(x: 0.25, y: 0.75)
        let landscape = MarkerLabelLayout.previewCenter(
            for: normalized,
            labelSize: .zero,
            in: CGRect(x: 0, y: 0, width: 200, height: 100),
        )
        let portrait = MarkerLabelLayout.previewCenter(
            for: normalized,
            labelSize: .zero,
            in: CGRect(x: 0, y: 0, width: 100, height: 200),
        )

        XCTAssertEqual(landscape, CGPoint(x: 50, y: 75))
        XCTAssertEqual(portrait, CGPoint(x: 25, y: 150))
    }

    func testDifferentLabelSizesUseTheirActualBounds() {
        let normalized = CGPoint(x: 0.02, y: 0.02)
        let small = MarkerLabelLayout.clampedOrigin(
            for: normalized,
            labelSize: CGSize(width: 20, height: 10),
            in: frame,
        )
        let large = MarkerLabelLayout.clampedOrigin(
            for: normalized,
            labelSize: CGSize(width: 80, height: 40),
            in: frame,
        )

        XCTAssertEqual(small, CGPoint(x: 0, y: 0))
        XCTAssertEqual(large, CGPoint(x: 0, y: 0))
        XCTAssertEqual(
            MarkerLabelLayout.previewCenter(
                for: normalized,
                labelSize: CGSize(width: 80, height: 40),
                in: frame,
            ),
            CGPoint(x: 40, y: 20),
        )
    }

    func testCoreImageOriginFlipsTopLeftYIntoBottomLeftCoordinates() {
        let result = MarkerLabelLayout.coreImageOrigin(
            for: CGPoint(x: 0.25, y: 0.25),
            labelSize: labelSize,
            in: CGRect(x: 10, y: 20, width: 200, height: 100),
        )

        XCTAssertEqual(result.x, 50, accuracy: 0.0001)
        XCTAssertEqual(result.y, 90, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/MarkerLabelLayoutTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build fails because `MarkerLabelLayout` does not exist.

- [ ] **Step 3: Implement the stateless layout API**

Create `ShotMarker/Services/MarkerLabelLayout.swift`:

```swift
import CoreGraphics
import Foundation

enum MarkerLabelLayout {
    static func aspectFitRect(contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard isValid(contentSize), isValid(bounds.size) else {
            return bounds
        }

        let scale = min(
            bounds.width / contentSize.width,
            bounds.height / contentSize.height,
        )
        let fittedSize = CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale,
        )
        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height,
        )
    }

    static func clampedOrigin(
        for normalizedCenter: CGPoint,
        labelSize: CGSize,
        in frame: CGRect,
    ) -> CGPoint {
        guard isValid(frame.size) else {
            return frame.origin
        }

        let center = CGPoint(
            x: frame.minX + clampedUnit(normalizedCenter.x) * frame.width,
            y: frame.minY + clampedUnit(normalizedCenter.y) * frame.height,
        )
        return CGPoint(
            x: clampedOrigin(
                center: center.x,
                labelLength: max(labelSize.width, 0),
                minimum: frame.minX,
                maximum: frame.maxX,
            ),
            y: clampedOrigin(
                center: center.y,
                labelLength: max(labelSize.height, 0),
                minimum: frame.minY,
                maximum: frame.maxY,
            ),
        )
    }

    static func previewCenter(
        for normalizedCenter: CGPoint,
        labelSize: CGSize,
        in frame: CGRect,
    ) -> CGPoint {
        let origin = clampedOrigin(
            for: normalizedCenter,
            labelSize: labelSize,
            in: frame,
        )
        return CGPoint(
            x: origin.x + max(labelSize.width, 0) / 2,
            y: origin.y + max(labelSize.height, 0) / 2,
        )
    }

    static func normalizedCenter(
        forPreviewPoint point: CGPoint,
        labelSize: CGSize,
        in frame: CGRect,
    ) -> CGPoint {
        guard isValid(frame.size) else {
            return CGPoint(
                x: CGFloat(MarkerLabelStyle.default.normalizedCenterX),
                y: CGFloat(MarkerLabelStyle.default.normalizedCenterY),
            )
        }

        let proposed = CGPoint(
            x: (point.x - frame.minX) / frame.width,
            y: (point.y - frame.minY) / frame.height,
        )
        let clampedCenter = previewCenter(
            for: proposed,
            labelSize: labelSize,
            in: frame,
        )
        return CGPoint(
            x: (clampedCenter.x - frame.minX) / frame.width,
            y: (clampedCenter.y - frame.minY) / frame.height,
        )
    }

    static func coreImageOrigin(
        for normalizedCenter: CGPoint,
        labelSize: CGSize,
        in imageExtent: CGRect,
    ) -> CGPoint {
        let localFrame = CGRect(origin: .zero, size: imageExtent.size)
        let topLeftOrigin = clampedOrigin(
            for: normalizedCenter,
            labelSize: labelSize,
            in: localFrame,
        )
        return CGPoint(
            x: imageExtent.minX + topLeftOrigin.x,
            y: imageExtent.maxY - topLeftOrigin.y - max(labelSize.height, 0),
        )
    }

    private static func clampedOrigin(
        center: CGFloat,
        labelLength: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
    ) -> CGFloat {
        guard labelLength < maximum - minimum else {
            return (minimum + maximum - labelLength) / 2
        }
        return min(max(center - labelLength / 2, minimum), maximum - labelLength)
    }

    private static func clampedUnit(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }

    private static func isValid(_ size: CGSize) -> Bool {
        size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height > 0
    }
}
```

Do not add a second layout formula in the view or editor. Later tasks must call these functions.

- [ ] **Step 4: Run the geometry tests and verify they pass**

Run the Step 2 command again.

Expected: all `MarkerLabelLayoutTests` pass.

- [ ] **Step 5: Commit the shared geometry**

```bash
git add \
  ShotMarker/Services/MarkerLabelLayout.swift \
  ShotMarkerTests/MarkerLabelLayoutTests.swift
git commit -m "feat: 新增片段序数共享布局计算"
```

---

### Task 3: 把任务快照样式传到导出并按样式渲染

**Files:**

- Create: `ShotMarkerTests/Fixtures/HighlightJob-1.2.json`
- Modify: `ShotMarker/Services/HighlightJobRunner.swift:4-92`
- Modify: `ShotMarker/ViewModels/HighlightJobManager.swift:38-75,94-130`
- Modify: `ShotMarker/Services/VideoClipEditingService.swift:45-65,99-114,201-315,479-576`
- Modify: `ShotMarkerTests/HighlightJobStoreTests.swift:24-31,83-117`
- Modify: `ShotMarkerTests/HighlightJobRunnerTests.swift:19-46,78-112`
- Modify: `ShotMarkerTests/HighlightJobManagerTests.swift:33-64,366-393`
- Modify: `ShotMarkerTests/VideoClipEditingServiceTests.swift:40-356`

**Interfaces:**

- Consumes: `MarkerLabelStyle.normalized`
- Consumes: `MarkerLabelLayout.coreImageOrigin(for:labelSize:in:)`
- Produces: `VideoClipEditingService.makeHighlightClip(from:markerLabelStyle:progressHandler:_:)`
- Produces: `HighlightJobRunner.MakeHighlightClip` with style as its second argument
- Produces: internal testable `HighlightClipMarkerLabelOverlayMetrics.make(renderSize:style:)`
- Preserves: segment planning, label text, asset grouping, audio, progress, cancellation and output timeline

- [ ] **Step 1: Add failing legacy job, snapshot and renderer tests**

Create `ShotMarkerTests/Fixtures/HighlightJob-1.2.json`:

```json
[
  {
    "id": "00000000-0000-0000-0000-000000010000",
    "trainingSession": {
      "id": "00000000-0000-0000-0000-000000010100",
      "startedAt": 0,
      "endedAt": 600,
      "events": [
        {
          "id": "00000000-0000-0000-0000-000000010101",
          "markedAt": 120
        }
      ]
    },
    "selectedVideos": [
      {
        "id": "photo-asset-id",
        "recordedStartAt": 0,
        "duration": 900,
        "source": {
          "photoLibraryAsset": {
            "localIdentifier": "photo-asset-id"
          }
        }
      }
    ],
    "clipSettings": {
      "secondsBeforeMarker": 7,
      "secondsAfterMarker": 3
    },
    "status": "interrupted",
    "progress": {
      "completedMarkerCount": 0,
      "totalMarkerCount": 1
    },
    "outputVideoPath": null,
    "photoLibrarySavedAt": null,
    "photoLibrarySaveErrorMessage": null,
    "errorMessage": null,
    "createdAt": 1000,
    "updatedAt": 1000
  }
]
```

Add to `HighlightJobStoreTests`:

```swift
func testLoadVersion12JobAddsDefaultNestedMarkerStyle() throws {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/HighlightJob-1.2.json")
    let jobs = try HighlightJobStore(fileURL: fixtureURL).loadJobs()
    let job = try XCTUnwrap(jobs.first)

    XCTAssertEqual(job.clipSettings.secondsBeforeMarker, 7)
    XCTAssertEqual(job.clipSettings.secondsAfterMarker, 3)
    XCTAssertEqual(job.clipSettings.markerLabelStyle, .default)
}
```

Change the round-trip job fixture to use a non-default style and assert it survives `HighlightJobStore`:

```swift
let markerLabelStyle = MarkerLabelStyle(
    fontSizeRatio: 0.13,
    normalizedCenterX: 0.7,
    normalizedCenterY: 0.25,
    textOpacity: 0.85,
    backgroundOpacity: 0.4,
)
let job = try makeJob(status: .completed, markerLabelStyle: markerLabelStyle)

try store.saveJobs([job])

XCTAssertEqual(try store.loadJobs().first?.clipSettings.markerLabelStyle, markerLabelStyle)
```

Extend the test helper signature and use the supplied value in its `ClipSettings`:

```swift
private func makeJob(
    id: String = "00000000-0000-0000-0000-000000010000",
    status: HighlightJobStatus,
    markerLabelStyle: MarkerLabelStyle = .default,
) throws -> HighlightJob {
    HighlightJob(
        id: try XCTUnwrap(UUID(uuidString: id)),
        trainingSession: TrainingSession(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000010100")),
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 2_600),
            events: [
                ShotMarkerEvent(
                    id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000010101")),
                    markedAt: Date(timeIntervalSince1970: 2_120),
                ),
            ],
        ),
        selectedVideos: [
            HighlightJobVideo(
                id: "photo-asset-id",
                recordedStartAt: Date(timeIntervalSince1970: 2_000),
                duration: 900,
                source: .photoLibraryAsset(localIdentifier: "photo-asset-id"),
            ),
        ],
        clipSettings: ClipSettings(
            secondsBeforeMarker: 9,
            secondsAfterMarker: 4,
            markerLabelStyle: markerLabelStyle,
        ),
        status: status,
        progress: HighlightJobProgress(completedMarkerCount: 1, totalMarkerCount: 3),
        outputVideoPath: status == .completed ? "HighlightJobs/Outputs/job/highlight.mov" : nil,
        errorMessage: status == .failed ? "导出失败" : nil,
        createdAt: Date(timeIntervalSince1970: 3_000),
        updatedAt: Date(timeIntervalSince1970: 3_100),
    )
}
```

Change `HighlightJobRunnerTests.testRunCompletesJobAndReportsProgressWithoutSavingToPhotos` to capture the style:

```swift
var receivedStyle: MarkerLabelStyle?
let runner = HighlightJobRunner(
    fileStore: fileStore,
    makeHighlightClip: { _, markerLabelStyle, progressHandler, _ in
        receivedStyle = markerLabelStyle
        progressHandler(HighlightClipGenerationProgress(completedMarkerCount: 0, totalMarkerCount: 1))
        progressHandler(HighlightClipGenerationProgress(completedMarkerCount: 1, totalMarkerCount: 1))
        return exportedURL
    },
    assetForJobVideo: { _, _ in
        AVURLAsset(url: URL(fileURLWithPath: "/tmp/unused.mov"))
    },
)
```

Give `makeJob` a `markerLabelStyle` parameter, pass a non-default style, and assert:

```swift
XCTAssertEqual(receivedStyle, job.clipSettings.markerLabelStyle)
```

Add this manager snapshot test:

```swift
func testCreateJobKeepsCapturedStyleAfterDefaultsChange() async throws {
    let suiteName = "ShotMarker.HighlightJobManagerTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settingsStore = ClipSettingsStore(userDefaults: defaults)
    let capturedStyle = MarkerLabelStyle(
        fontSizeRatio: 0.14,
        normalizedCenterX: 0.8,
        normalizedCenterY: 0.3,
        textOpacity: 0.7,
        backgroundOpacity: 0.2,
    )
    let manager = HighlightJobManager(
        store: InMemoryHighlightJobStore(),
        fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
        runnerFactory: { _ in .immediateCompleted },
    )

    let job = try await manager.createJob(
        session: makeSession(),
        selectedVideos: [makeSelectedVideo()],
        clipSettings: ClipSettings(
            secondsBeforeMarker: 9,
            secondsAfterMarker: 4,
            markerLabelStyle: capturedStyle,
        ),
    )
    settingsStore.save(
        ClipSettings(
            secondsBeforeMarker: 9,
            secondsAfterMarker: 4,
            markerLabelStyle: .default,
        ),
    )

    XCTAssertEqual(job.clipSettings.markerLabelStyle, capturedStyle)
    XCTAssertEqual(manager.jobs.first?.clipSettings.markerLabelStyle, capturedStyle)
}
```

Add this interrupted-restart assertion:

```swift
func testRestartUsesPersistedMarkerStyle() async throws {
    let style = MarkerLabelStyle(
        fontSizeRatio: 0.16,
        normalizedCenterX: 0.25,
        normalizedCenterY: 0.75,
        textOpacity: 0.55,
        backgroundOpacity: 0.45,
    )
    let interruptedJob = try makeJob(status: .interrupted, markerLabelStyle: style)
    var runnerStyle: MarkerLabelStyle?
    let manager = HighlightJobManager(
        store: InMemoryHighlightJobStore(jobs: [interruptedJob]),
        fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
        runnerFactory: { job in
            runnerStyle = job.clipSettings.markerLabelStyle
            return .immediateCompleted
        },
    )
    manager.load()

    await manager.restart(jobID: interruptedJob.id)
    await Task.yield()

    XCTAssertEqual(runnerStyle, style)
}
```

Update the existing manager test helper so the new call is defined:

```swift
private func makeJob(
    id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000040001")!,
    status: HighlightJobStatus,
    markerLabelStyle: MarkerLabelStyle = .default,
) throws -> HighlightJob {
    HighlightJob(
        id: id,
        trainingSession: try makeSession(),
        selectedVideos: [
            HighlightJobVideo(
                id: "photo-asset-id",
                recordedStartAt: Date(timeIntervalSince1970: 2_000),
                duration: 900,
                source: .photoLibraryAsset(localIdentifier: "photo-asset-id"),
            ),
        ],
        clipSettings: ClipSettings(
            secondsBeforeMarker: 9,
            secondsAfterMarker: 4,
            markerLabelStyle: markerLabelStyle,
        ),
        status: status,
        progress: .zero,
        outputVideoPath: nil,
        errorMessage: nil,
        createdAt: Date(timeIntervalSince1970: 3_000),
        updatedAt: Date(timeIntervalSince1970: 3_000),
    )
}
```

Replace the old fixed-style assertion in `VideoClipEditingServiceTests` with deterministic metric tests:

```swift
func testMarkerLabelMetricsUseConfiguredRatioWithoutAbsoluteClamp() throws {
    let style = MarkerLabelStyle(
        fontSizeRatio: 0.12,
        normalizedCenterX: 0.5,
        normalizedCenterY: 0.5,
        textOpacity: 0.8,
        backgroundOpacity: 0.3,
    )

    let metrics = try HighlightClipMarkerLabelOverlayMetrics.make(
        renderSize: CGSize(width: 1080, height: 1920),
        style: style,
    )

    XCTAssertEqual(metrics.fontSize, 129.6, accuracy: 0.001)
    XCTAssertEqual(metrics.textOpacity, 0.8, accuracy: 0.001)
    XCTAssertEqual(metrics.backgroundOpacity, 0.3, accuracy: 0.001)
}

func testMarkerLabelMetricsRejectInvalidRenderSize() {
    XCTAssertThrowsError(
        try HighlightClipMarkerLabelOverlayMetrics.make(
            renderSize: CGSize(width: .nan, height: 1080),
            style: .default,
        ),
    )
    XCTAssertThrowsError(
        try HighlightClipMarkerLabelOverlayMetrics.make(
            renderSize: CGSize(width: 0, height: 1080),
            style: .default,
        ),
    )
}
```

Add the full-transparent export test:

```swift
func testMakeHighlightClipWithFullyTransparentMarkerKeepsTimeline() async throws {
    let sourceURL = temporaryDirectory.appendingPathComponent("transparent-marker.mov")
    try await makeSilentVideo(at: sourceURL, duration: 4)
    let logger = SpyAppLogger()
    let segment = HighlightClipSegment(
        markerID: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000002701")),
        videoID: "video",
        markerAt: Date(timeIntervalSince1970: 1_000),
        start: 1,
        duration: 2,
    )
    let style = MarkerLabelStyle(
        fontSizeRatio: 0.10,
        normalizedCenterX: 0.5,
        normalizedCenterY: 0.5,
        textOpacity: 0,
        backgroundOpacity: 0,
    )

    let outputURL = try await VideoClipEditingService(logger: logger).makeHighlightClip(
        from: [segment],
        markerLabelStyle: style,
    ) { _ in
        AVURLAsset(url: sourceURL)
    }

    XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    let outputDuration = try await AVURLAsset(url: outputURL).load(.duration)
    XCTAssertEqual(outputDuration.seconds, 2, accuracy: 0.2)
    XCTAssertEqual(
        logger.entry(named: "video.export.started")?.context["usesVideoComposition"],
        "false",
    )
}
```

Add the renderer-origin test:

```swift
func testMarkerLabelOriginUsesConfiguredTopLeftNormalizedPosition() {
    let overlaySize = CGSize(width: 20, height: 10)
    let extent = CGRect(x: 0, y: 0, width: 200, height: 100)
    let first = VideoClipEditingService.markerLabelCoreImageOrigin(
        style: MarkerLabelStyle(
            fontSizeRatio: 0.10,
            normalizedCenterX: 0.25,
            normalizedCenterY: 0.25,
            textOpacity: 1,
            backgroundOpacity: 0.6,
        ),
        overlaySize: overlaySize,
        imageExtent: extent,
    )
    let second = VideoClipEditingService.markerLabelCoreImageOrigin(
        style: MarkerLabelStyle(
            fontSizeRatio: 0.10,
            normalizedCenterX: 0.75,
            normalizedCenterY: 0.75,
            textOpacity: 1,
            backgroundOpacity: 0.6,
        ),
        overlaySize: overlaySize,
        imageExtent: extent,
    )

    XCTAssertEqual(first, CGPoint(x: 40, y: 70))
    XCTAssertEqual(second, CGPoint(x: 140, y: 20))
}
```

Keep the existing export, progress and cancellation tests and update every `makeHighlightClip` call with an explicit style.

- [ ] **Step 2: Run focused tests and verify the new interface is missing**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightJobStoreTests \
  -only-testing:ShotMarkerTests/HighlightJobRunnerTests \
  -only-testing:ShotMarkerTests/HighlightJobManagerTests \
  -only-testing:ShotMarkerTests/VideoClipEditingServiceTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build fails because the runner/export closure has no style parameter and the overlay metrics/origin helpers do not exist.

- [ ] **Step 3: Change the runner and editor signatures end to end**

Change `HighlightJobRunner.MakeHighlightClip` to:

```swift
typealias MakeHighlightClip = (
    [HighlightClipSegment],
    MarkerLabelStyle,
    @MainActor @escaping (HighlightClipGenerationProgress) -> Void,
    @escaping (HighlightClipAssetRequest) async throws -> AVAsset
) async throws -> URL
```

In `run(job:onChange:)`, pass the task snapshot unchanged:

```swift
let temporaryOutputURL = try await makeHighlightClip(
    plan.segments,
    job.clipSettings.markerLabelStyle,
    { progress in
        job.progress = HighlightJobProgress(
            completedMarkerCount: progress.completedMarkerCount,
            totalMarkerCount: progress.totalMarkerCount,
        )
        job.updatedAt = Date()
        onChange(job)
    },
    { request in
        guard let video = videosByID[request.videoID] else {
            throw HighlightJobRunnerError.sourceVideoMissing
        }
        return try await assetForJobVideo(video, request)
    },
)
```

Change the editor API to require the concrete style:

```swift
func makeHighlightClip(
    from segments: [HighlightClipSegment],
    markerLabelStyle: MarkerLabelStyle,
    progressHandler: (@MainActor (HighlightClipGenerationProgress) -> Void)? = nil,
    _ assetProvider: (HighlightClipAssetRequest) async throws -> AVAsset,
) async throws -> URL
```

At the start of `makeHighlightClip`, compute `let normalizedMarkerLabelStyle = markerLabelStyle.normalized`, then thread that value through the private `exportClip` and `markerLabelVideoComposition` calls. This keeps `HighlightJobRunner` responsible for exact snapshot delivery and the editor responsible for the required last defensive normalization. Do not read `ClipSettingsStore` from the editor.

Update `HighlightJobManager.live`:

```swift
makeHighlightClip: { segments, markerLabelStyle, progressHandler, assetProvider in
    try await editingService.makeHighlightClip(
        from: segments,
        markerLabelStyle: markerLabelStyle,
        progressHandler: progressHandler,
        assetProvider,
    )
},
```

In `createJob`, store `clipSettings.normalized` so malformed in-memory values cannot enter a new task snapshot.

Update all runner test doubles from `{ _, _, _ in ... }` to `{ _, _, _, _ in ... }` and all direct editor calls to pass `markerLabelStyle: .default` or the test’s explicit custom value.

- [ ] **Step 4: Replace fixed rendering values with normalized metrics**

Replace `HighlightClipMarkerLabelOverlayStyle` with:

```swift
struct HighlightClipMarkerLabelOverlayMetrics: Equatable {
    let fontSize: CGFloat
    let textOpacity: CGFloat
    let backgroundOpacity: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat

    static func make(
        renderSize: CGSize,
        style: MarkerLabelStyle,
    ) throws -> HighlightClipMarkerLabelOverlayMetrics {
        guard renderSize.width.isFinite,
              renderSize.height.isFinite,
              renderSize.width > 0,
              renderSize.height > 0
        else {
            throw VideoClipEditingError.missingVideoTrack
        }

        let normalized = style.normalized
        let fontSize = min(renderSize.width, renderSize.height)
            * CGFloat(normalized.fontSizeRatio)
        return HighlightClipMarkerLabelOverlayMetrics(
            fontSize: fontSize,
            textOpacity: CGFloat(normalized.textOpacity),
            backgroundOpacity: CGFloat(normalized.backgroundOpacity),
            horizontalPadding: fontSize * 0.55,
            verticalPadding: fontSize * 0.28,
            cornerRadius: fontSize * 0.25,
        )
    }
}
```

Use `UIColor.white.withAlphaComponent(metrics.textOpacity)` for the attributed text and `UIColor.black.withAlphaComponent(metrics.backgroundOpacity)` for the rounded background. Continue using `UIFont.monospacedDigitSystemFont(ofSize:weight: .black)`.

Make `markerLabelRenderSize(for:)` throw `VideoClipEditingError.missingVideoTrack` when the track is absent or the transformed natural size is non-finite/non-positive; remove the `1080×1920` fallback:

```swift
private static func markerLabelRenderSize(for asset: AVAsset) async throws -> CGSize {
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    guard let videoTrack = videoTracks.first else {
        throw VideoClipEditingError.missingVideoTrack
    }

    let naturalSize = try await videoTrack.load(.naturalSize)
    let preferredTransform = try await videoTrack.load(.preferredTransform)
    let transformedRect = CGRect(origin: .zero, size: naturalSize)
        .applying(preferredTransform)
    let renderSize = CGSize(
        width: abs(transformedRect.width),
        height: abs(transformedRect.height),
    )
    guard renderSize.width.isFinite,
          renderSize.height.isFinite,
          renderSize.width > 0,
          renderSize.height > 0
    else {
        throw VideoClipEditingError.missingVideoTrack
    }
    return renderSize
}
```

After creating each distinct label image, place it with the shared layout:

```swift
static func markerLabelCoreImageOrigin(
    style: MarkerLabelStyle,
    overlaySize: CGSize,
    imageExtent: CGRect,
) -> CGPoint {
    let normalized = style.normalized
    return MarkerLabelLayout.coreImageOrigin(
        for: CGPoint(
            x: CGFloat(normalized.normalizedCenterX),
            y: CGFloat(normalized.normalizedCenterY),
        ),
        labelSize: overlaySize,
        in: imageExtent,
    )
}
```

The filter callback must translate each label using its own image size:

```swift
let sourceImage = parameters.sourceImage
let origin = markerLabelCoreImageOrigin(
    style: normalizedStyle,
    overlaySize: overlayImage.extent.size,
    imageExtent: sourceImage.extent,
)
let translatedOverlay = overlayImage.transformed(
    by: CGAffineTransform(
        translationX: origin.x - overlayImage.extent.minX,
        y: origin.y - overlayImage.extent.minY,
    ),
)
let outputImage = translatedOverlay
    .composited(over: sourceImage)
    .cropped(to: sourceImage.extent)
```

This is what moves a longer merged label farther inward near an edge.

When both normalized opacities are zero, return `nil` from `markerLabelVideoComposition` before creating images. The normal composition export still runs, so video/audio duration, progress and cancellation behavior stay intact.

- [ ] **Step 5: Run the data-flow and renderer tests**

Run the Step 2 command again.

Expected: all four focused suites pass; the 1.2 fixture loads; the exact task style reaches the export closure; the custom metrics and full-transparent export assertions pass.

- [ ] **Step 6: Commit the snapshot-to-render pipeline**

```bash
git add \
  ShotMarker/Services/HighlightJobRunner.swift \
  ShotMarker/ViewModels/HighlightJobManager.swift \
  ShotMarker/Services/VideoClipEditingService.swift \
  ShotMarkerTests/Fixtures/HighlightJob-1.2.json \
  ShotMarkerTests/HighlightJobStoreTests.swift \
  ShotMarkerTests/HighlightJobRunnerTests.swift \
  ShotMarkerTests/HighlightJobManagerTests.swift \
  ShotMarkerTests/VideoClipEditingServiceTests.swift
git commit -m "feat: 将片段序数样式固化到任务并用于导出"
```

---

### Task 4: 保留完整画幅的轻量缩略图

**Files:**

- Create: `ShotMarkerTests/PhotoLibraryVideoAssetProviderTests.swift`
- Modify: `ShotMarker/Services/PhotoLibraryVideoAssetProvider.swift:46-63`

**Interfaces:**

- Produces: `PhotoLibraryVideoAssetProvider.thumbnailTargetSize`
- Produces: `PhotoLibraryVideoAssetProvider.thumbnailContentMode`
- Produces: `PhotoLibraryVideoAssetProvider.makeThumbnailRequestOptions()`
- Preserves: `thumbnailData(from:) async -> Data?`

- [ ] **Step 1: Write the failing thumbnail request contract test**

Create `ShotMarkerTests/PhotoLibraryVideoAssetProviderTests.swift`:

```swift
#if os(iOS)
    @testable import ShotMarker
    import Photos
    import XCTest

    final class PhotoLibraryVideoAssetProviderTests: XCTestCase {
        func testThumbnailRequestPreservesFullFrameWithoutNetworkAccess() {
            let options = PhotoLibraryVideoAssetProvider.makeThumbnailRequestOptions()

            XCTAssertEqual(
                PhotoLibraryVideoAssetProvider.thumbnailTargetSize,
                CGSize(width: 320, height: 320),
            )
            XCTAssertEqual(PhotoLibraryVideoAssetProvider.thumbnailContentMode, .aspectFit)
            XCTAssertEqual(options.deliveryMode, .fastFormat)
            XCTAssertEqual(options.resizeMode, .fast)
            XCTAssertFalse(options.isNetworkAccessAllowed)
            XCTAssertTrue(options.isSynchronous)
        }
    }
#endif
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/PhotoLibraryVideoAssetProviderTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build fails because the thumbnail request contract members do not exist.

- [ ] **Step 3: Centralize and use the full-frame request configuration**

Add inside `PhotoLibraryVideoAssetProvider`:

```swift
static let thumbnailTargetSize = CGSize(width: 320, height: 320)
static let thumbnailContentMode: PHImageContentMode = .aspectFit

static func makeThumbnailRequestOptions() -> PHImageRequestOptions {
    let options = PHImageRequestOptions()
    options.deliveryMode = .fastFormat
    options.resizeMode = .fast
    options.isNetworkAccessAllowed = false
    options.isSynchronous = true
    return options
}
```

Change `thumbnailData(from:)` to call this helper and pass the two static request values to `PHImageManager.requestImage`. Keep JPEG compression quality `0.72`.

Do not change `TrainingVideoTemporaryFileStore`: it already sets `appliesPreferredTrackTransform = true`, and `maximumSize` scales without cropping. Do not change selected-video cards: `TrainingSessionHighlightView.selectedVideoThumbnail` continues using `scaledToFill`; only the new marker preview uses `scaledToFit`.

- [ ] **Step 4: Run thumbnail and loading tests**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/PhotoLibraryVideoAssetProviderTests \
  -only-testing:ShotMarkerTests/TrainingVideoLoadingServiceTests \
  -only-testing:ShotMarkerTests/TrainingVideoTemporaryFileStoreTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all selected tests pass and no preview request enables network access.

- [ ] **Step 5: Commit the thumbnail contract**

```bash
git add \
  ShotMarker/Services/PhotoLibraryVideoAssetProvider.swift \
  ShotMarkerTests/PhotoLibraryVideoAssetProviderTests.swift
git commit -m "fix: 保留片段序数预览缩略图完整画幅"
```

---

### Task 5: 构建片段序数 SwiftUI 设置区与辅助功能

**Files:**

- Create: `ShotMarker/Views/MarkerLabelSettingsView.swift`
- Modify: `ShotMarker/Views/TrainingSessionHighlightView.swift:58-65,185-253`

**Interfaces:**

- Consumes: `Binding<MarkerLabelStyle>`
- Consumes: `thumbnailData: Data?`, `previewLabel: String`, `isDisabled: Bool`
- Consumes: all `MarkerLabelLayout` APIs
- Produces: drag updates and 5-point VoiceOver movement through the same clamped normalized coordinates
- Preserves: parent video loading, preparation, coverage calculation and job creation

- [ ] **Step 1: Add the standalone component with real preview geometry**

Create `ShotMarker/Views/MarkerLabelSettingsView.swift` under `#if os(iOS)`.

The component declaration must be:

```swift
struct MarkerLabelSettingsView: View {
    let thumbnailData: Data?
    let previewLabel: String
    let isDisabled: Bool
    @Binding var style: MarkerLabelStyle

    @State private var labelSize: CGSize = .zero
}
```

Add these file-private support types:

```swift
private enum MarkerLabelPreviewCoordinateSpace {
    static let name = "MarkerLabelPreview"
}

private struct MarkerLabelSizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
```

Use this body structure so the image frame, drag coordinate space, measured label and controls are connected explicitly:

```swift
private var previewImage: UIImage? {
    thumbnailData.flatMap(UIImage.init(data:))
}

var body: some View {
    VStack(alignment: .leading, spacing: 16) {
        GeometryReader { proxy in
            let previewBounds = CGRect(origin: .zero, size: proxy.size)
            let videoFrame = if let previewImage {
                MarkerLabelLayout.aspectFitRect(
                    contentSize: previewImage.size,
                    in: previewBounds,
                )
            } else {
                previewBounds
            }
            let normalized = style.normalized
            let fontSize = min(videoFrame.width, videoFrame.height)
                * CGFloat(normalized.fontSizeRatio)

            ZStack(alignment: .topLeading) {
                Color.black

                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: previewBounds.width,
                            height: previewBounds.height,
                        )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                        Text("暂时无法显示视频预览")
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                    .frame(
                        width: previewBounds.width,
                        height: previewBounds.height,
                    )
                    .background(Color.secondary.opacity(0.18))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("暂时无法显示视频预览")
                }

                markerLabel(fontSize: fontSize, videoFrame: videoFrame)
                    .position(
                        MarkerLabelLayout.previewCenter(
                            for: CGPoint(
                                x: CGFloat(normalized.normalizedCenterX),
                                y: CGFloat(normalized.normalizedCenterY),
                            ),
                            labelSize: labelSize,
                            in: videoFrame,
                        ),
                    )
            }
            .coordinateSpace(name: MarkerLabelPreviewCoordinateSpace.name)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onPreferenceChange(MarkerLabelSizePreferenceKey.self) { size in
                labelSize = size
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)

        sliderRow(
            title: "文字大小",
            keyPath: \.fontSizeRatio,
            range: MarkerLabelStyle.fontSizeRatioRange,
            step: 0.01,
            hint: "相对于完整视频画面短边，范围百分之四到百分之十六",
        )
        sliderRow(
            title: "文字不透明度",
            keyPath: \.textOpacity,
            range: MarkerLabelStyle.opacityRange,
            step: 0.05,
            hint: "百分之零完全透明，百分之一百完全不透明",
        )
        sliderRow(
            title: "黑底不透明度",
            keyPath: \.backgroundOpacity,
            range: MarkerLabelStyle.opacityRange,
            step: 0.05,
            hint: "百分之零完全透明，百分之一百完全不透明",
        )
    }
    .disabled(isDisabled)
}
```

Add the marker, drag and VoiceOver helpers:

```swift
private func markerLabel(fontSize: CGFloat, videoFrame: CGRect) -> some View {
    let normalized = style.normalized
    return Text(previewLabel)
        .font(.system(size: fontSize, weight: .black))
        .monospacedDigit()
        .foregroundStyle(Color.white.opacity(normalized.textOpacity))
        .padding(.horizontal, fontSize * 0.55)
        .padding(.vertical, fontSize * 0.28)
        .background(
            Color.black.opacity(normalized.backgroundOpacity),
            in: RoundedRectangle(cornerRadius: fontSize * 0.25),
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MarkerLabelSizePreferenceKey.self,
                    value: proxy.size,
                )
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(MarkerLabelPreviewCoordinateSpace.name),
            )
            .onChanged { value in
                updateStyle(for: value.location, in: videoFrame)
            },
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("片段序数位置")
        .accessibilityValue(
            "横向 \(percentage(normalized.normalizedCenterX))%，纵向 \(percentage(normalized.normalizedCenterY))%",
        )
        .accessibilityHint("调整所有片段共用的序数位置")
        .accessibilityAction(named: Text("向左移动")) {
            moveBy(x: -0.05, y: 0, in: videoFrame)
        }
        .accessibilityAction(named: Text("向右移动")) {
            moveBy(x: 0.05, y: 0, in: videoFrame)
        }
        .accessibilityAction(named: Text("向上移动")) {
            moveBy(x: 0, y: -0.05, in: videoFrame)
        }
        .accessibilityAction(named: Text("向下移动")) {
            moveBy(x: 0, y: 0.05, in: videoFrame)
        }
}

private func updateStyle(for location: CGPoint, in videoFrame: CGRect) {
    let center = MarkerLabelLayout.normalizedCenter(
        forPreviewPoint: location,
        labelSize: labelSize,
        in: videoFrame,
    )
    var updated = style
    updated.normalizedCenterX = Double(center.x)
    updated.normalizedCenterY = Double(center.y)
    style = updated.normalized
}

private func moveBy(x deltaX: Double, y deltaY: Double, in videoFrame: CGRect) {
    let normalized = style.normalized
    let requestedPoint = CGPoint(
        x: videoFrame.minX
            + CGFloat(normalized.normalizedCenterX + deltaX) * videoFrame.width,
        y: videoFrame.minY
            + CGFloat(normalized.normalizedCenterY + deltaY) * videoFrame.height,
    )
    updateStyle(for: requestedPoint, in: videoFrame)
}
```

Add the concrete slider row and percent helper:

```swift
private func sliderRow(
    title: String,
    keyPath: WritableKeyPath<MarkerLabelStyle, Double>,
    range: ClosedRange<Double>,
    step: Double,
    hint: String,
) -> some View {
    let value = style[keyPath: keyPath]
    return VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text(title)
            Spacer()
            Text("\(percentage(value))%")
                .foregroundStyle(.secondary)
        }

        Slider(
            value: styleBinding(keyPath),
            in: range,
            step: step,
        )
        .accessibilityLabel(title)
        .accessibilityValue("\(percentage(value))%")
        .accessibilityHint(hint)
    }
}

private func percentage(_ value: Double) -> Int {
    Int((value * 100).rounded())
}
```

The code above must remain a pure display/edit component: it decodes only the supplied `thumbnailData`, uses the real fitted image rect for geometry, and never calls a video or Photos loader. The displayed clamping of an unchanged default must not write back automatically; only drag, VoiceOver movement or slider interaction updates the binding.

- [ ] **Step 2: Add exact sliders and accessibility semantics**

Each row must show `文字大小`、`文字不透明度`、`黑底不透明度` and `Int((value * 100).rounded())%`. The slider accessibility labels use those exact names. Accessibility values must include the current percentage; the size hint says it is relative to the complete video frame’s short side, and opacity hints say `0% 完全透明，100% 完全不透明`.

Implement `styleBinding` as a real normalized binding:

```swift
private func styleBinding(
    _ keyPath: WritableKeyPath<MarkerLabelStyle, Double>,
) -> Binding<Double> {
    Binding(
        get: { style[keyPath: keyPath] },
        set: { value in
            var updated = style
            updated[keyPath: keyPath] = value
            style = updated.normalized
        },
    )
}
```

The marker is one accessibility element with label `片段序数位置` and hint `调整所有片段共用的序数位置`. The four custom actions in Step 1 change the requested normalized axis by `0.05`, then call `MarkerLabelLayout.normalizedCenter(forPreviewPoint:labelSize:in:)`; do not replace them with unclamped direct assignments.

Apply `.disabled(isDisabled)` to the whole section content.

- [ ] **Step 3: Integrate the component without moving parent responsibilities**

`MarkerLabelSettingsView` 只返回预览与调节控件，不创建 `Section`。在 `TrainingSessionHighlightView.body` 中，把 `markerLabelSettingsSection` 插在 `selectedVideoItemsSection` 之后、`coverageAndGenerationSections` 之前。

Define:

```swift
@ViewBuilder
private var markerLabelSettingsSection: some View {
    if let firstSelectedItem = selectedVideoItems.first {
        Section("片段序数") {
            MarkerLabelSettingsView(
                thumbnailData: firstSelectedItem.thumbnailData,
                previewLabel: plan.segments.first?.markerLabel ?? "1/1",
                isDisabled: isCreatingHighlightJob,
                style: $clipSettings.markerLabelStyle,
            )
        }
    }
}
```

Use `selectedVideoItems.first`, not `selectedVideos.first`, so selection/reordering changes the preview according to the user-visible first item even when later availability filtering differs. Keep the existing `onChange(of: clipSettings)` autosave and existing `createJob(... clipSettings: clipSettings)` call; Task 3 already guarantees normalization and task snapshotting.

- [ ] **Step 4: Build the app and run the related model/layout tests**

Run:

```bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

Then run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/MarkerLabelStyleTests \
  -only-testing:ShotMarkerTests/MarkerLabelLayoutTests \
  -only-testing:ShotMarkerTests/ClipSettingsStoreTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: Debug build and all selected tests pass. There is no UI Test target, so interaction behavior is completed by the manual acceptance in Task 6.

- [ ] **Step 5: Commit the user interface**

```bash
git add \
  ShotMarker/Views/MarkerLabelSettingsView.swift \
  ShotMarker/Views/TrainingSessionHighlightView.swift
git commit -m "feat: 新增片段序数预览与样式设置"
```

---

### Task 6: 更新产品版本并完成自动与人工验收

**Files:**

- Modify: `ShotMarker.xcodeproj/project.pbxproj:438-479,679-747`
- Verify only: all production and test files changed by Tasks 1-5

**Interfaces:**

- Produces: iPhone App `MARKETING_VERSION = 1.3`, `CURRENT_PROJECT_VERSION = 3`
- Produces: Watch App `MARKETING_VERSION = 1.3`, `CURRENT_PROJECT_VERSION = 3`
- Preserves: test-target version settings

- [ ] **Step 1: Change only the two product targets’ marketing version**

In both Debug and Release configurations for `com.heji.ShotMarker` and `com.heji.ShotMarker.watchkitapp`, change:

```text
MARKETING_VERSION = 1.2;
```

to:

```text
MARKETING_VERSION = 1.3;
```

Leave every `CURRENT_PROJECT_VERSION` unchanged. Do not change `ShotMarkerTests` or `ShotMarkerWatchAppTests` marketing versions.

- [ ] **Step 2: Verify exact build settings**

Run:

```bash
xcodebuild \
  -project ShotMarker.xcodeproj \
  -target ShotMarker \
  -configuration Release \
  -showBuildSettings | rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|PRODUCT_BUNDLE_IDENTIFIER'
```

Expected for `com.heji.ShotMarker`: `MARKETING_VERSION = 1.3` and `CURRENT_PROJECT_VERSION = 3`.

Run:

```bash
xcodebuild \
  -project ShotMarker.xcodeproj \
  -target ShotMarkerWatchApp \
  -configuration Release \
  -showBuildSettings | rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|PRODUCT_BUNDLE_IDENTIFIER'
```

Expected for `com.heji.ShotMarker.watchkitapp`: `MARKETING_VERSION = 1.3` and `CURRENT_PROJECT_VERSION = 3`.

- [ ] **Step 3: Run the complete iPhone test suite**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all `ShotMarkerTests` pass. Record the exact passed/failed/skipped counts from this run; do not copy the historical 164-test result.

- [ ] **Step 4: Run the complete Watch test suite**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarkerWatchApp \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all `ShotMarkerWatchAppTests` pass. Record the exact counts from this run; the Change adds no Watch behavior.

- [ ] **Step 5: Build Release for a generic iOS Simulator**

Run:

```bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Perform and record the seven Simulator acceptance flows**

Use an iPhone simulator at or above the iOS 26.4 deployment target and record its exact device model and OS version. Complete all seven flows:

1. Select a landscape video; verify the section appears after `已选视频`, uses that first item’s real full-frame thumbnail, and does not start playback.
2. Select a portrait video; verify the whole portrait frame is visible with black fill rather than cropped to 16:9.
3. Drag the marker to all four corners and the center; verify the complete marker remains inside the actual video frame.
4. Move all three controls through their ranges; verify size, white text opacity and black background opacity update immediately and independently.
5. Create a task with a distinctive style, then change the saved defaults; verify the created task’s export still uses its captured style.
6. Export a highlight containing a short label and a merged longer label near an edge; verify both remain complete and vertical movement matches the preview’s downward direction.
7. Leave and reopen the generation page; verify the saved global style is restored.

Also turn on VoiceOver once, focus the marker, execute all four custom movement actions, and verify each moves by five percentage points subject to the same edge clamp. With no thumbnail, verify the placeholder is announced as unavailable preview rather than an app error and generation remains possible.

If any flow fails, stop the documentation closure, add a failing automated test at the lowest testable model/layout/service boundary, fix the implementation, rerun the relevant focused suite, and repeat Steps 3-6.

- [ ] **Step 7: Run repository checks**

Run:

```bash
git diff --check
```

Expected: exit status 0.

Run:

```bash
rg -n 'MARKETING_VERSION =|CURRENT_PROJECT_VERSION =' ShotMarker.xcodeproj/project.pbxproj
```

Expected: both product targets are 1.3 / 3; test target values remain unchanged.

Run:

```bash
rg -n 'ClipSettingsStore|isNetworkAccessAllowed = true|Analytics' \
  ShotMarker/Services/VideoClipEditingService.swift \
  ShotMarker/Views/MarkerLabelSettingsView.swift \
  ShotMarker/Services/PhotoLibraryVideoAssetProvider.swift
```

Expected: the editor/view do not read `ClipSettingsStore`; thumbnail options do not enable network access; no marker-style Analytics code exists. The existing full-video asset request may still use network access for the separate, user-confirmed video preparation/export flow.

- [ ] **Step 8: Commit the verified version change**

```bash
git add ShotMarker.xcodeproj/project.pbxproj
git commit -m "chore: 更新产品版本为1.3"
```

---

### Task 7: 更新当前事实并归档完成的 Change

**Files:**

- Modify: `docs/README.md`
- Modify: `docs/current/product.md`
- Modify: `docs/current/architecture.md`
- Modify: `docs/current/quality.md`
- Modify: `docs/current/release.md`
- Modify: `docs/current/status.md`
- Move: `docs/changes/2026-09-02-highlight-marker-label-style-spec.md`
- Move: `docs/changes/2026-09-02-highlight-marker-label-style-plan.md`

**Interfaces:**

- Consumes: actual Task 6 command outputs and manual acceptance evidence
- Produces: concise current facts with implementation facts separated from effective decisions
- Produces: completed spec and plan in `docs/archive/2026-09/`
- Preserves: 1.2 historical Archive/Validate facts and unrelated active Changes

- [ ] **Step 1: Update current product and architecture facts**

In `docs/current/product.md`, update the review date and add only verified 1.3 behavior:

- the first selected video supplies a static full-frame preview;
- one global style controls size, normalized position, text opacity and background opacity;
- defaults are 10%, `(0.15, 0.10)`, 100% and 60%;
- settings auto-save and each job captures a snapshot;
- 1.2 settings/jobs remain readable.

In `docs/current/architecture.md`, update the review date/code baseline and describe the verified chain:

```text
selectedVideoItems.first.thumbnailData
→ MarkerLabelSettingsView
→ ClipSettings.markerLabelStyle
→ HighlightJob.clipSettings
→ HighlightJobRunner
→ VideoClipEditingService
```

Record that `MarkerLabelLayout` owns top-left normalized coordinates, boundary clamping and Core Image Y-axis conversion, and that the editor never reads `ClipSettingsStore`.

- [ ] **Step 2: Update quality, release and status from fresh evidence**

In `docs/current/quality.md`:

- record the actual date, commit/baseline, simulator names/OS versions and exact test counts from Task 6;
- record the Release Simulator build result and `git diff --check`;
- record the seven manual flows and VoiceOver check only if actually completed;
- retain “没有 UI Test target” as an explicit limitation;
- do not rewrite historical device, Archive, TestFlight or online-service results as current Change verification.

In `docs/current/release.md`:

- set the repository product version to `1.3（Build 3）`;
- retain 1.2 signed Archive/Organizer facts as dated historical release evidence;
- state that this Change did not create a new signed Archive, TestFlight build or App Store verification unless those actions were separately performed and evidenced.

In `docs/current/status.md`:

- set the code baseline and product version to the verified 1.3 state;
- include the marker style capability among implemented facts;
- keep unresolved TestFlight, device, GlitchTip and Analytics release work separate from this Change.

- [ ] **Step 3: Check current-document limits and internal consistency**

Run:

```bash
wc -l docs/current/*.md
```

Expected: every file is at or below 300 lines.

Run:

```bash
rg -n '1\.2|1\.3|片段序数|markerLabelStyle|MarkerLabelLayout' \
  docs/current docs/README.md
```

Expected: 1.3 describes the current repository implementation; 1.2 references are explicitly dated historical release facts; no current document says this Change produced unperformed Archive/TestFlight/external validation.

- [ ] **Step 4: Update the documentation entry and archive both change artifacts**

Remove the completed marker-style item from `docs/README.md` 的“正在进行的变更” while preserving the unrelated App Store and voice-command entries.

Move both artifacts:

```bash
mkdir -p docs/archive/2026-09
mv \
  docs/changes/2026-09-02-highlight-marker-label-style-spec.md \
  docs/archive/2026-09/2026-09-02-highlight-marker-label-style-spec.md
mv \
  docs/changes/2026-09-02-highlight-marker-label-style-plan.md \
  docs/archive/2026-09/2026-09-02-highlight-marker-label-style-plan.md
```

Verify:

```bash
rg --files docs/archive/2026-09 docs/changes | sort
```

Expected: both dated files exist directly under `docs/archive/2026-09/`, neither remains in `docs/changes/`, and no deeper topic directory was created.

- [ ] **Step 5: Review the final diff and commit documentation closure**

Run:

```bash
git diff --check
git status --short
git diff -- docs/README.md docs/current docs/archive/2026-09
```

Expected: no whitespace errors; current facts match fresh evidence; unrelated pre-existing user changes are preserved and identifiable.

Commit only the intended documentation paths:

```bash
git add \
  docs/README.md \
  docs/current/product.md \
  docs/current/architecture.md \
  docs/current/quality.md \
  docs/current/release.md \
  docs/current/status.md \
  docs/archive/2026-09/2026-09-02-highlight-marker-label-style-spec.md \
  docs/archive/2026-09/2026-09-02-highlight-marker-label-style-plan.md
git commit -m "docs: 更新片段序数样式当前事实并归档变更"
```

---

## Final Verification Gate

Before declaring the Change complete, run this exact final gate from `main`:

```bash
git branch --show-current
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarkerWatchApp \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
git diff --check
git status --short
```

Completion requires:

- branch output is `main`;
- both complete test suites pass with freshly recorded counts;
- Release Simulator build succeeds;
- all manual acceptance and VoiceOver checks are recorded with device/system;
- product targets report 1.3 / Build 3;
- legacy fixtures, task snapshot and custom render tests pass;
- `docs/current/` reflects verified current facts and remains within line limits;
- spec and plan are archived in `docs/archive/2026-09/`;
- no unrelated user change was discarded or silently folded into an implementation commit.
