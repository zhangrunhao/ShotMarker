# 日志导出 P0 Implementation Plan

## 完成情况

- 完成日期：2026-05-11
- 实施分支：`main`
- 代码提交：
  - `fe2e02e` `feat: 添加结构化日志事件模型`
  - `d1f8147` `feat: 添加本地日志滚动存储`
  - `878806f` `feat: 添加应用日志写入入口`
  - `7534d67` `feat: 添加诊断日志导出服务`
  - `00744e0` `feat: 添加首页日志导出入口`
  - `6952198` `feat: 记录应用启动和手表同步日志`
  - `77f9639` `feat: 记录训练记录列表日志`
  - `f9ec228` `feat: 记录视频选择和集锦生成日志`
- 验证命令：
  - `xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'id=4590B1EB-982B-4CF8-AAAE-FA6FCAECB242'`
  - 结果：`** TEST SUCCEEDED **`
  - `git diff --check`
  - 结果：通过，无空白错误输出
- 已知限制：
  - P0 仍不包含 Watch 端本地日志文件，也不同步 Watch 端日志；导出文件中仅保留 `watchDiagnostics` 占位。
  - P0 导出格式是单个 JSON 文件，不包含 zip 或附件。
  - 本轮已完成自动化验证；真实分享面板的人工操作验收需要在模拟器或真机 UI 中补充确认。

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 iPhone App 内保存最近一段时间的关键运行日志，并把首页右上角“同步诊断”入口升级为“一键导出诊断日志”，方便上线后根据用户提供的文件定位问题。

**Architecture:** P0 只实现 iPhone 端日志中心：业务代码通过轻量 `AppLogger` 写结构化日志，日志以每日 JSONL 文件保存在 Application Support，导出时合并日志、当前同步诊断快照和基础 App 信息为一个 JSON 文件。手表端日志同步暂不进入 P0，但导出文件保留 `watch` 元信息字段，方便 P1 扩展。

**Tech Stack:** SwiftUI, Foundation, WatchConnectivity, XCTest, JSONEncoder/JSONDecoder, FileManager, Share Sheet.

## 项目约束

- 按项目规则直接在 `main` 实施，不创建 feature branch，不使用 git worktree。
- 每次编辑前确认当前分支是 `main`。
- 不覆盖用户未提交改动。
- 用 TDD 推进：每个日志基础能力先写失败测试，再写实现。

## P0 范围

### 做

- iPhone 端写本地文件日志。
- 保存最近 `14 天`日志。
- 总日志体积上限 `30 MB`，超过后从最旧日志文件开始删除。
- 日志使用结构化 JSON，方便后续由人或工具分析。
- 首页右上角按钮从“同步诊断”改为“导出日志”。
- 点按钮后生成一个完整诊断文件，并弹出系统分享面板。
- 导出文件包含：
  - App 版本、build、导出时间、系统版本。
  - 当前 `PhoneWatchSyncDiagnosticsSnapshot`。
  - 最近保留期内的手机日志。
  - P1 手表日志字段占位，明确当前 P0 未包含手表日志。
- 覆盖关键链路日志：
  - App 启动。
  - WatchConnectivity 激活、接收训练记录、导入、ACK、失败。
  - 训练记录首页读取和合并。
  - 视频选择、视频读取失败。
  - 集锦生成开始、剪辑计划、进度、成功、失败。
  - 相册保存成功、失败。

### 不做

- P0 不实现手表端日志文件。
- P0 不把手表日志同步到手机。
- P0 不引入第三方 zip 库。
- P0 不做远程上传。
- P0 不记录视频内容、完整本地文件路径、用户隐私文本。
- P0 不替换系统 `os.Logger`，可以后续并行接入，但问题排查以 App 自己的导出日志为准。

## 产品行为

首页右上角按钮文案和可访问性从“同步诊断”改成“导出日志”。

交互流程：

1. 用户点右上角日志按钮。
2. App 写入一条 `diagnostics.export.started` 日志。
3. App 执行日志清理。
4. App 生成临时导出文件：`ShotMarker-Diagnostics-YYYYMMDD-HHmmss.json`。
5. App 弹出系统分享面板。
6. 用户分享完成或取消后，临时文件可以保留到下一次导出前清理。
7. 如果导出失败，App 弹出错误提示，并写入 `diagnostics.export.failed` 日志。

P0 使用单个 JSON 文件，不使用 zip。原因是 iOS 原生没有直接的高层 zip API；为了 P0 稳定，单文件 JSON 更容易实现、测试和分析。P1 如果需要包含多份附件，再引入 zip 方案。

## 日志格式

本地存储使用 JSON Lines，每行一个 `AppLogEvent`。

示例：

```json
{"id":"C52A1B79-86C9-4C38-9D73-7F9979CE0E5F","timestamp":"2026-05-10T11:30:00Z","level":"info","category":"video","name":"highlight.generate.started","message":"开始生成集锦","context":{"trainingSessionId":"...","selectedVideoCount":"1","matchedMarkerCount":"9","secondsBeforeMarker":"5","secondsAfterMarker":"2"}}
```

模型建议：

```swift
enum AppLogLevel: String, Codable, Equatable {
    case debug
    case info
    case warning
    case error
}

enum AppLogCategory: String, Codable, Equatable {
    case app
    case training
    case sync
    case video
    case photos
    case diagnostics
}

struct AppLogEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: AppLogLevel
    let category: AppLogCategory
    let name: String
    let message: String
    let context: [String: String]
    let errorDomain: String?
    let errorCode: Int?
    let errorDescription: String?
}
```

字段规则：

- `name` 使用稳定机器可读命名，例如 `sync.training.import.failed`。
- `message` 使用简短中文，方便肉眼阅读。
- `context` 只放低敏信息，值统一转成字符串。
- `errorDomain`、`errorCode` 来自 `NSError`。
- `errorDescription` 可保存系统错误描述，但不要保存完整本地路径。
- 不记录用户视频文件名、原始文件路径、照片库完整资源信息。

## 导出文件格式

导出文件是一个 JSON 对象。

```json
{
  "manifest": {
    "schemaVersion": 1,
    "exportedAt": "2026-05-10T11:35:00Z",
    "appVersion": "1.0",
    "buildNumber": "1",
    "platform": "iOS",
    "systemVersion": "26.4",
    "deviceModel": "iPhone",
    "retentionDays": 14,
    "maxLogBytes": 31457280
  },
  "phoneDiagnostics": {
    "watchConnectivity": {
      "isSupported": true,
      "isPaired": true,
      "isWatchAppInstalled": true,
      "activationState": "activated"
    }
  },
  "watchDiagnostics": {
    "included": false,
    "reason": "watch logs are planned for P1"
  },
  "logs": []
}
```

Swift 模型建议：

```swift
struct AppLogExportBundle: Codable, Equatable {
    let manifest: AppLogExportManifest
    let phoneDiagnostics: PhoneDiagnosticsExport?
    let watchDiagnostics: WatchDiagnosticsExport
    let logs: [AppLogEvent]
}
```

`PhoneWatchSyncDiagnosticsSnapshot` 不一定要直接遵守 `Codable`。P0 推荐新增一个专门导出的 `PhoneWatchSyncDiagnosticsExport`，避免把 UI 诊断模型和文件格式绑死。

## 文件结构

建议新增：

- `ShotMarker/Services/AppLogging/AppLogEvent.swift`
- `ShotMarker/Services/AppLogging/AppLogStore.swift`
- `ShotMarker/Services/AppLogging/AppLogger.swift`
- `ShotMarker/Services/AppLogging/AppLogExportService.swift`
- `ShotMarker/Services/AppLogging/AppLogShareSheet.swift`
- `ShotMarkerTests/AppLogStoreTests.swift`
- `ShotMarkerTests/AppLoggerTests.swift`
- `ShotMarkerTests/AppLogExportServiceTests.swift`

建议修改：

- `ShotMarker/ShotMarkerApp.swift`
- `ShotMarker/ContentView.swift`
- `ShotMarker/Views/TrainingSessionListView.swift`
- `ShotMarker/ViewModels/TrainingSessionListViewModel.swift`
- `ShotMarker/Services/PhoneWatchSyncService.swift`
- `ShotMarker/Views/TrainingSessionHighlightView.swift`
- `ShotMarker/Views/VideoClipTestButton.swift`
- `ShotMarker/Services/VideoClipPhotoLibrarySaver.swift`
- `ShotMarker/Services/VideoClipEditingService.swift`

## Task 1: 新增日志事件模型

**Files:**

- Create: `ShotMarker/Services/AppLogging/AppLogEvent.swift`
- Test: `ShotMarkerTests/AppLogEventTests.swift`

**Step 1: 写失败测试**

测试内容：

- `AppLogEvent` 可以 JSON 编码和解码。
- `AppLogLevel`、`AppLogCategory` raw value 稳定。
- `NSError` 能被转换成 `errorDomain`、`errorCode`、`errorDescription`。

建议测试名：

```swift
func testAppLogEventJSONRoundTripsAllFields() throws
func testAppLogEventCapturesNSErrorMetadata() throws
```

**Step 2: 跑测试确认失败**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'id=4590B1EB-982B-4CF8-AAAE-FA6FCAECB242' -only-testing:ShotMarkerTests/AppLogEventTests
```

Expected: 编译失败或测试失败，因为类型还不存在。

**Step 3: 实现模型**

在 `AppLogEvent.swift` 中实现：

- `AppLogLevel`
- `AppLogCategory`
- `AppLogEvent`
- `AppLogEvent.make(...)`

`make` 方法负责注入 `UUID`、`Date` 和错误元信息，方便测试替换。

**Step 4: 跑测试确认通过**

Run 同 Step 2。

**Step 5: 提交**

```bash
git add ShotMarker/Services/AppLogging/AppLogEvent.swift ShotMarkerTests/AppLogEventTests.swift
git commit -m "feat: 添加结构化日志事件模型"
```

## Task 2: 新增本地日志存储

**Files:**

- Create: `ShotMarker/Services/AppLogging/AppLogStore.swift`
- Test: `ShotMarkerTests/AppLogStoreTests.swift`

**Storage 规则:**

- 根目录：`Application Support/Logs`
- 文件名：`phone-YYYY-MM-DD.jsonl`
- 每行一个 JSON 编码的 `AppLogEvent`
- 默认保留 `14` 天
- 默认最大体积 `30 * 1024 * 1024` bytes

**Step 1: 写失败测试**

测试内容：

- append 后当前日期日志文件出现一行 JSON。
- readAll 能按时间顺序读回事件。
- cleanup 删除早于保留期的日志文件。
- cleanup 在总体积超过上限时删除最旧文件。
- 损坏行不会导致整个读取失败，应该跳过并继续读其他行。

建议测试名：

```swift
func testAppendWritesOneJSONLineIntoDailyLogFile() async throws
func testReadAllReturnsEventsInTimestampOrder() async throws
func testCleanupDeletesFilesOlderThanRetentionWindow() async throws
func testCleanupDeletesOldestFilesWhenTotalSizeExceedsLimit() async throws
func testReadAllSkipsCorruptedLines() async throws
```

**Step 2: 跑测试确认失败**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'id=4590B1EB-982B-4CF8-AAAE-FA6FCAECB242' -only-testing:ShotMarkerTests/AppLogStoreTests
```

**Step 3: 实现 `AppLogStore`**

建议使用 `actor AppLogStore`，避免并发写文件互相打断。

核心 API：

```swift
actor AppLogStore {
    struct Configuration: Equatable {
        var retentionDays: Int = 14
        var maxTotalBytes: Int = 30 * 1024 * 1024
    }

    init(
        directoryURL: URL = AppLogStore.defaultDirectoryURL(),
        configuration: Configuration = Configuration(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    )

    func append(_ event: AppLogEvent) async
    func readAll() async -> [AppLogEvent]
    func cleanup() async
}
```

`append` 内部失败不向 UI 抛错。日志系统不能因为写日志失败影响核心业务。

**Step 4: 跑测试确认通过**

Run 同 Step 2。

**Step 5: 提交**

```bash
git add ShotMarker/Services/AppLogging/AppLogStore.swift ShotMarkerTests/AppLogStoreTests.swift
git commit -m "feat: 添加本地日志滚动存储"
```

## Task 3: 新增 AppLogger 门面

**Files:**

- Create: `ShotMarker/Services/AppLogging/AppLogger.swift`
- Test: `ShotMarkerTests/AppLoggerTests.swift`

**目的:**

业务代码不直接操作 `AppLogStore`，只调用 `logger.info(...)`、`logger.error(...)`。

**Step 1: 写失败测试**

测试内容：

- 调用 `info` 后会异步写入一条 info 日志。
- 调用 `error` 后会保存错误元信息。
- context 中的非隐私字段能保存。

**Step 2: 实现协议和默认实现**

建议协议：

```swift
protocol AppLogging {
    func debug(_ name: String, category: AppLogCategory, message: String, context: [String: String])
    func info(_ name: String, category: AppLogCategory, message: String, context: [String: String])
    func warning(_ name: String, category: AppLogCategory, message: String, context: [String: String])
    func error(_ name: String, category: AppLogCategory, message: String, error: Error?, context: [String: String])
}
```

默认实现：

```swift
final class AppLogger: AppLogging {
    static let shared = AppLogger(store: AppLogStore())

    private let store: AppLogStore

    init(store: AppLogStore) {
        self.store = store
    }
}
```

`AppLogger` 内部用 `Task { await store.append(event) }` 写日志，业务调用方不需要 `await`。

**Step 3: 提供测试用 Spy**

可以在测试文件里定义 `SpyAppLogger: AppLogging`，后续服务测试复用。

**Step 4: 跑测试确认通过**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'id=4590B1EB-982B-4CF8-AAAE-FA6FCAECB242' -only-testing:ShotMarkerTests/AppLoggerTests
```

**Step 5: 提交**

```bash
git add ShotMarker/Services/AppLogging/AppLogger.swift ShotMarkerTests/AppLoggerTests.swift
git commit -m "feat: 添加应用日志写入入口"
```

## Task 4: 新增日志导出服务

**Files:**

- Create: `ShotMarker/Services/AppLogging/AppLogExportService.swift`
- Test: `ShotMarkerTests/AppLogExportServiceTests.swift`

**Step 1: 写失败测试**

测试内容：

- 导出文件能被 JSONDecoder 解码成 `AppLogExportBundle`。
- 导出文件包含 manifest。
- 导出文件包含日志事件。
- 导出文件包含同步诊断快照。
- 导出前会触发 cleanup。

建议测试名：

```swift
func testExportWritesDecodableDiagnosticsFile() async throws
func testExportIncludesPhoneWatchSyncDiagnosticsSnapshot() async throws
func testExportRunsLogCleanupBeforeReadingEvents() async throws
```

**Step 2: 实现导出模型**

在 `AppLogExportService.swift` 中定义：

- `AppLogExportManifest`
- `PhoneWatchSyncDiagnosticsExport`
- `WatchDiagnosticsExport`
- `AppLogExportBundle`
- `AppLogExportService`

导出 API：

```swift
struct AppLogExportService {
    let store: AppLogStore
    let diagnosticsSnapshotProvider: (() -> PhoneWatchSyncDiagnosticsSnapshot)?

    func export() async throws -> URL
}
```

导出目录建议：

- `FileManager.default.temporaryDirectory`
- 文件名：`ShotMarker-Diagnostics-YYYYMMDD-HHmmss.json`

**Step 3: 实现 App 信息读取**

manifest 从 `Bundle.main.infoDictionary` 读取：

- `CFBundleShortVersionString`
- `CFBundleVersion`

系统信息从 `UIDevice.current.systemVersion` 读取。为测试方便，可以把 app info 和 device info 包成 provider 注入。

**Step 4: 跑测试确认通过**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'id=4590B1EB-982B-4CF8-AAAE-FA6FCAECB242' -only-testing:ShotMarkerTests/AppLogExportServiceTests
```

**Step 5: 提交**

```bash
git add ShotMarker/Services/AppLogging/AppLogExportService.swift ShotMarkerTests/AppLogExportServiceTests.swift
git commit -m "feat: 添加诊断日志导出服务"
```

## Task 5: 把首页右上角改成导出日志

**Files:**

- Create: `ShotMarker/Services/AppLogging/AppLogShareSheet.swift`
- Modify: `ShotMarker/Views/TrainingSessionListView.swift`
- Modify: `ShotMarker/ContentView.swift`
- Modify: `ShotMarker/ShotMarkerApp.swift`

**Step 1: 新增分享面板包装**

P0 推荐用 `UIActivityViewController` 包一层 SwiftUI sheet：

```swift
struct AppLogShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
}
```

**Step 2: 修改依赖注入**

`ShotMarkerApp` 初始化一个共享日志 store 和导出服务。

建议：

- `let logStore = AppLogStore()`
- `let logger = AppLogger.shared`
- `let logExportService = AppLogExportService(store: logStore, diagnosticsSnapshotProvider: syncService.diagnosticsSnapshot)`

如果 `AppLogger.shared` 内部自己创建 store，要避免导出服务和 logger 使用不同 store。P0 推荐让 `AppLogger.configure(store:)` 或直接在 `ShotMarkerApp` 中创建 logger 并注入。

**Step 3: 修改 `TrainingSessionListView`**

新增状态：

```swift
@State private var isExportingLogs = false
@State private var exportedLogURL: URL?
@State private var logExportErrorMessage: String?
```

右上角从 `NavigationLink` 改为按钮：

```swift
Button {
    Task { await exportLogs() }
} label: {
    Image(systemName: "square.and.arrow.up")
}
.accessibilityLabel("导出日志")
```

**Step 4: 实现导出动作**

`exportLogs()`：

1. 设置 `isExportingLogs = true`。
2. 写 `diagnostics.export.started`。
3. 调用 `logExportService.export()`。
4. 成功后设置 `exportedLogURL`，弹分享 sheet。
5. 失败后设置错误 alert，并写 `diagnostics.export.failed`。
6. 最后设置 `isExportingLogs = false`。

**Step 5: 保留旧诊断信息**

`PhoneWatchSyncDiagnosticsView` 可以暂时保留文件，不再作为首页入口。这样后续开发和 Debug 还能复用。

**Step 6: 手动验收**

- 点右上角按钮能弹出分享面板。
- 分享文件名包含 `ShotMarker-Diagnostics`。
- 文件能用文本编辑器打开。
- 文件中能看到 manifest、phone diagnostics、logs。

**Step 7: 提交**

```bash
git add ShotMarker/Services/AppLogging/AppLogShareSheet.swift ShotMarker/Views/TrainingSessionListView.swift ShotMarker/ContentView.swift ShotMarker/ShotMarkerApp.swift
git commit -m "feat: 添加首页日志导出入口"
```

## Task 6: 接入 App 启动和同步日志

**Files:**

- Modify: `ShotMarker/ShotMarkerApp.swift`
- Modify: `ShotMarker/Services/PhoneWatchSyncService.swift`
- Test: `ShotMarkerTests/PhoneWatchSyncServiceTests.swift`

**Step 1: 给 `PhoneWatchSyncService` 注入 logger**

构造函数新增：

```swift
logger: AppLogging = AppLogger.shared
```

测试使用 `SpyAppLogger`。

**Step 2: 写同步服务失败测试**

新增测试覆盖：

- `start()` 时记录 `sync.session.activate.requested`。
- `WCSession` 不支持时记录 `sync.session.unsupported`。
- 收到未知 userInfo type 时记录 warning。
- payload 解码失败时记录 error。
- 导入失败时记录 error。
- ACK 发送成功时记录 info。
- ACK 发送失败时记录 error。

**Step 3: 实现日志点**

建议事件名：

- `app.launch`
- `sync.session.activate.requested`
- `sync.session.activate.completed`
- `sync.session.activate.failed`
- `sync.session.unsupported`
- `sync.training.payload.received`
- `sync.training.payload.decode.failed`
- `sync.training.import.succeeded`
- `sync.training.import.failed`
- `sync.training.ack.sent`
- `sync.training.ack.failed`

context 示例：

- `trainingSessionId`
- `activationState`
- `isPaired`
- `isWatchAppInstalled`

**Step 4: 跑测试**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'id=4590B1EB-982B-4CF8-AAAE-FA6FCAECB242' -only-testing:ShotMarkerTests/PhoneWatchSyncServiceTests
```

**Step 5: 提交**

```bash
git add ShotMarker/ShotMarkerApp.swift ShotMarker/Services/PhoneWatchSyncService.swift ShotMarkerTests/PhoneWatchSyncServiceTests.swift
git commit -m "feat: 记录应用启动和手表同步日志"
```

## Task 7: 接入训练记录首页日志

**Files:**

- Modify: `ShotMarker/ViewModels/TrainingSessionListViewModel.swift`
- Test: `ShotMarkerTests/TrainingSessionListViewModelTests.swift`

**Step 1: 注入 logger**

`TrainingSessionListViewModel` 构造函数新增：

```swift
logger: AppLogging = AppLogger.shared
```

**Step 2: 写测试**

覆盖：

- `load()` 成功时记录训练记录数量。
- `load()` 失败时记录错误。
- 合并成功时记录被合并数量和新训练记录 id。
- 合并失败时记录错误。

**Step 3: 实现日志点**

建议事件名：

- `training.sessions.load.succeeded`
- `training.sessions.load.failed`
- `training.sessions.merge.succeeded`
- `training.sessions.merge.failed`

**Step 4: 跑测试**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'id=4590B1EB-982B-4CF8-AAAE-FA6FCAECB242' -only-testing:ShotMarkerTests/TrainingSessionListViewModelTests
```

**Step 5: 提交**

```bash
git add ShotMarker/ViewModels/TrainingSessionListViewModel.swift ShotMarkerTests/TrainingSessionListViewModelTests.swift
git commit -m "feat: 记录训练记录列表日志"
```

## Task 8: 接入视频选择和集锦生成日志

**Files:**

- Modify: `ShotMarker/Views/TrainingSessionHighlightView.swift`
- Modify: `ShotMarker/Services/VideoClipEditingService.swift`
- Modify: `ShotMarker/Services/VideoClipPhotoLibrarySaver.swift`
- Test: `ShotMarkerTests/VideoClipEditingServiceTests.swift`
- Test: `ShotMarkerTests/VideoClipPhotoLibrarySaverTests.swift`

**Step 1: 接入页面级日志**

`TrainingSessionHighlightView` 可以直接使用 `AppLogger.shared`。P0 不强行给 SwiftUI View 做复杂注入。

记录：

- 进入页面：`highlight.view.opened`
- 用户选择视频开始：`video.selection.started`
- 单个视频读取成功：`video.selection.item.loaded`
- 视频选择失败：`video.selection.failed`
- 覆盖结果变化：`highlight.plan.updated`
- 生成开始：`highlight.generate.started`
- 生成进度：`highlight.generate.progress`
- 生成成功：`highlight.generate.succeeded`
- 生成失败：`highlight.generate.failed`
- iCloud/PHAsset fallback：`video.asset.fallback_to_picker_file`

context 示例：

- `trainingSessionId`
- `totalMarkerCount`
- `matchedMarkerCount`
- `unmatchedMarkerCount`
- `selectedVideoCount`
- `segmentCount`
- `secondsBeforeMarker`
- `secondsAfterMarker`
- `completedMarkerCount`
- `totalMarkerCount`

**Step 2: 接入服务级日志**

`VideoClipEditingService` 新增可选 logger：

```swift
struct VideoClipEditingService {
    private let logger: AppLogging

    init(logger: AppLogging = AppLogger.shared) {
        self.logger = logger
    }
}
```

记录：

- `video.export.composition.started`
- `video.export.composition.segment_inserted`
- `video.export.completed`
- `video.export.failed`

注意：不要记录源视频完整 URL。

**Step 3: 接入相册保存日志**

`VideoClipPhotoLibrarySaver` 新增 logger，记录：

- `photos.save.authorization.requested`
- `photos.save.authorization.denied`
- `photos.save.succeeded`
- `photos.save.failed`

**Step 4: 写服务测试**

用 `SpyAppLogger` 验证：

- 导出成功记录 completed。
- 导出失败记录 failed。
- 相册权限拒绝记录 denied。
- 相册网络错误记录 error domain/code。

**Step 5: 跑测试**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'id=4590B1EB-982B-4CF8-AAAE-FA6FCAECB242' -only-testing:ShotMarkerTests/VideoClipEditingServiceTests -only-testing:ShotMarkerTests/VideoClipPhotoLibrarySaverTests
```

**Step 6: 提交**

```bash
git add ShotMarker/Views/TrainingSessionHighlightView.swift ShotMarker/Services/VideoClipEditingService.swift ShotMarker/Services/VideoClipPhotoLibrarySaver.swift ShotMarkerTests/VideoClipEditingServiceTests.swift ShotMarkerTests/VideoClipPhotoLibrarySaverTests.swift
git commit -m "feat: 记录视频选择和集锦生成日志"
```

## Task 9: 全量验证和人工验收

**Files:**

- Modify: `docs/plans/2026-05-10-log-export-p0-implementation-plan.md`

**Step 1: 跑完整测试**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'id=4590B1EB-982B-4CF8-AAAE-FA6FCAECB242'
```

Expected: `** TEST SUCCEEDED **`

**Step 2: 跑空白检查**

Run:

```bash
git diff --check
```

Expected: 无输出，exit code 0。

**Step 3: 手动验收**

在 iPhone 模拟器或真机上验证：

1. 打开 App。
2. 首页右上角显示导出图标。
3. 点导出按钮。
4. 系统分享面板出现。
5. 选择保存到文件或 AirDrop。
6. 打开导出的 JSON 文件。
7. 确认包含 `manifest`、`phoneDiagnostics`、`watchDiagnostics`、`logs`。
8. 执行一次视频选择失败或集锦生成失败路径，重新导出，确认能看到对应错误日志。

**Step 4: 更新完成情况**

在本文档顶部新增完成情况，记录：

- 完成日期。
- commit hash。
- 测试命令和结果。
- 已知限制。

**Step 5: 最终提交**

```bash
git add docs/plans/2026-05-10-log-export-p0-implementation-plan.md
git commit -m "docs: 补充日志导出P0验收结果"
```

## 验收标准

功能验收：

- 首页右上角不再进入旧同步诊断页，而是触发导出日志。
- 导出成功后能通过系统分享面板拿到一个 JSON 文件。
- JSON 文件可解码，包含 manifest、当前同步诊断和日志数组。
- App 启动、同步、视频选择、集锦生成、保存相册的关键成功和失败路径都有日志。
- 日志保留期和体积上限生效。

工程验收：

- 日志写入失败不影响主业务。
- 日志写入 API 足够轻，不要求调用方 await。
- 测试使用临时目录，不污染真实 Application Support。
- 不引入第三方依赖。
- 不记录完整本地路径和视频文件名。

## P1 预留

P1 可以继续做：

- Watch 端 `WatchAppLogger` 和 `WatchAppLogStore`。
- Watch 日志通过 `WCSession.transferUserInfo` 增量同步到 iPhone。
- iPhone 导出文件包含 `watchLogs`。
- 导出格式升级为 zip：
  - `manifest.json`
  - `phone.log.jsonl`
  - `watch.log.jsonl`
  - `diagnostics.json`
- 增加“复制诊断摘要”按钮，方便用户直接发文字版。
- 增加日志级别开关，Release 默认 info 以上，Debug 可打开 debug。

## 风险与处理

- **日志文件损坏：** readAll 跳过损坏行，并写一条 warning。
- **导出文件过大：** P0 通过 30MB 总量上限控制，导出前 cleanup。
- **分享面板失败：** UI 弹错误提示，并保留日志。
- **隐私风险：** context 只允许业务白名单字段，禁止直接 dump 系统对象和 URL。
- **并发写入：** `AppLogStore` 使用 actor 串行化写入。
- **手表问题仍缺少手表本地日志：** P0 至少包含手机接收端同步日志和当前 WatchConnectivity 诊断；手表本地日志作为 P1。
