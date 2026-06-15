# Highlight Flow Refactor Design

日期：2026-06-15
状态：已确认

## 背景

ShotMarker 的 iPhone 集锦生成流程已经具备 P0 主链路：选择训练记录、选择视频、校验视频、计算打点片段、导出集锦并保存到相册。当前实现中，`TrainingSessionHighlightView.swift` 同时承担 UI、Photos 权限、PHAsset/AVAsset 读取、缩略图生成、iCloud 视频准备、picker fallback 临时文件、生成流程和错误映射，文件体量已经超过 1200 行。

本轮目标是整理这条流程的代码边界，同时把 PRD 调整为当前已确认的产品决策。除已确认的 PRD 文档修正外，后续实现应保持现有用户可见行为不变。

## 已确认产品决策

- 训练记录只表达一次训练和打点事实，不展示、也不持久化“已剪辑/待剪辑”状态。
- 集锦保存成功后提示用户并清空当前选择，不回写训练记录状态。
- iPhone 本地训练记录不承载同步状态；Watch outbox 才是待同步/待 ACK 状态来源。
- 默认剪辑窗口是打点前 9 秒、打点后 4 秒。
- 用户修改剪辑范围后，本地保留该设置，后续生成集锦继续使用。
- 同一视频内多个打点片段重叠，或片段间隔不超过 1 秒时，继续按当前实现合并。
- 合并片段显示打点范围格式，例如 `1-2/10`；单个片段显示 `1/10`。
- P0 不持久化 `HighlightJob`。集锦生成是基于训练记录、所选视频和剪辑设置的一次性运行时操作。

## 目标

1. 让 `TrainingSessionHighlightView` 回到 SwiftUI View 的职责：展示 UI、响应用户动作、维护页面状态、调用服务。
2. 抽出视频选择和准备相关的 Photos/AVFoundation/Transferable 逻辑，形成可测试服务。
3. 保留现有剪辑规划行为，包括重叠片段合并、`1-2/10` 标签、本地保留剪辑范围。
4. 保持训练记录模型不变，不新增 `isClipped` 或同步状态字段。
5. 让 PRD 与当前产品决策和实现方向一致。

## 非目标

- 不重做集锦生成 UI。
- 不新增生成前预览。
- 不新增持久化的 `HighlightJob`、视频库或视频选择历史。
- 不拆 Watch 同步服务。
- 不改变 `VideoClipEditingService` 的导出算法、overlay 样式或进度语义。
- 不把 iCloud 下载状态持久化到训练记录。

## 架构

本轮采用“小步拆分、行为等价”的方式。`TrainingSessionHighlightView` 继续作为页面入口，但把视频读取与准备能力委托给 iOS-only service。剪辑规划仍由 `VideoClipSegmentPlanner` 负责，视频导出仍由 `VideoClipEditingService` 负责，相册保存仍由 `VideoClipPhotoLibrarySaver` 负责。

拆分后的依赖方向：

```text
TrainingSessionHighlightView
  -> TrainingVideoLoadingService
  -> PhotoLibraryVideoAssetProvider
  -> TrainingVideoTemporaryFileStore
  -> VideoClipSegmentPlanner
  -> VideoClipEditingService
  -> VideoClipPhotoLibrarySaver
```

`TrainingSessionHighlightView` 不再直接调用 `PHImageManager`、`PHPhotoLibrary`、`AVAssetImageGenerator` 或 `PhotosPickerItem.loadTransferable`。这些平台细节进入服务层。

## 文件边界

### TrainingSessionHighlightView.swift

保留：

- SwiftUI 布局。
- `@State` 页面状态。
- selected item 卡片展示。
- generate button 和 progress 展示。
- alert 与 confirmation。
- 调用 service 的流程编排。
- 页面级日志上下文。

移出：

- PHAsset 查找。
- 相册读权限请求。
- `PHImageManager.requestAVAsset`。
- `PHImageManager.requestImage`。
- `AVAssetImageGenerator` 缩略图生成。
- `PhotosPickerItem` Transferable 文件读取。
- fallback 临时文件复制。
- 临时文件识别和清理。
- 视频 metadata 读取。

### TrainingVideoLoadingService.swift

职责：

- 从 `PhotosPickerItem` 加载一个 `SelectedTrainingVideoSelectionItem`。
- 优先使用 `PhotosPickerItem.itemIdentifier` 对应的 Photos asset。
- Photos asset 读取失败时，按现有逻辑 fallback 到 picker 提供的临时文件。
- 生成缩略图数据。
- 读取 `recordedStartAt` 和 `duration`。
- 映射加载失败为 `SelectedTrainingVideoUnavailableReason`。
- 结合 `VideoClipSegmentPlanner.canUseVideo` 过滤不覆盖当前训练的所选视频。
- 调用 readiness checker 判断本地可用性，未准备好时返回 `.notReady` item。

建议接口：

```swift
#if os(iOS)
struct TrainingVideoLoadingService {
    func loadSelectionItem(
        from item: PhotosPickerItem,
        title: String,
        fallbackID: String,
        session: TrainingSession
    ) async -> SelectedTrainingVideoSelectionItem
}
#endif
```

### PhotoLibraryVideoAssetProvider.swift

职责：

- 请求相册读取权限。
- 根据 localIdentifier 获取 `PHAsset`。
- 从 `PHAsset` 读取 metadata。
- 从 `PHAsset` 请求 AVAsset，支持 delivery quality 和 progress handler。
- 请求本地 AVAsset，用于判断 iCloud 视频是否已经可用。
- 从 `PHAsset` 生成缩略图。
- 支持取消进行中的 `PHImageManager` 请求。

建议接口：

```swift
#if os(iOS)
struct PhotoLibraryVideoAssetProvider {
    func ensureReadAccess() async throws
    func photoAsset(with localIdentifier: String) throws -> PHAsset
    func metadata(from asset: PHAsset) throws -> TrainingVideoMetadata
    func thumbnailData(from asset: PHAsset) async -> Data?
    func requestAVAsset(
        for asset: PHAsset,
        deliveryQuality: HighlightClipPhotoLibraryDeliveryQuality,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> AVAsset
    func requestLocalAVAsset(for asset: PHAsset) async throws
}
#endif
```

### TrainingVideoTemporaryFileStore.swift

职责：

- 从 picker Transferable 复制安全作用域视频到 temporary directory。
- 识别 `SelectedTrainingVideo.id` 是否为本地临时文件 URL。
- 删除单个或多个临时视频。
- 从本地文件读取 metadata。
- 从本地文件生成缩略图。

建议接口：

```swift
#if os(iOS)
struct TrainingVideoTemporaryFileStore {
    func loadPickedTrainingVideo(from item: PhotosPickerItem) async throws -> PickedTrainingVideo
    func temporaryVideoURL(from videoID: String) -> URL?
    func removeTemporaryVideoIfNeeded(_ video: SelectedTrainingVideo)
    func cleanupTemporaryVideos(_ videos: [SelectedTrainingVideo])
    func metadata(from url: URL) async throws -> TrainingVideoMetadata
    func thumbnailData(from url: URL) async -> Data?
}
#endif
```

`PickedTrainingVideo` 和 Transferable representation 可以跟随这个文件，继续只在 iOS 编译。

## 数据流

### 选择视频

1. View 收到 `selectedItems` 变化。
2. View 计算 retained item IDs，保留正在准备或暂停准备的 item 状态。
3. View 取消不再保留的准备任务，并清理旧临时文件。
4. View 逐个调用 `TrainingVideoLoadingService.loadSelectionItem(...)`。
5. Service 优先读取 Photos asset metadata 和 thumbnail。
6. 如果 Photos asset 不可读，Service fallback 到 picker 临时文件。
7. Service 检查视频是否覆盖当前训练打点。
8. Service 检查视频是否本地可用。
9. View 接收 selection items，更新 `selectedVideoItems` 和 `selectedVideos`，并记录日志。

### 准备 iCloud 视频

1. 用户点击未准备好的视频 item。
2. View 弹确认。
3. 用户确认后，View 创建 task 并记录 runID。
4. View 调用 `PhotoLibraryVideoAssetProvider.requestAVAsset(..., deliveryQuality: .high, progressHandler:)`。
5. provider 汇报进度。
6. View 根据 runID 更新 item 的准备进度，支持暂停和恢复。
7. 准备成功后，item 转为 available，`selectedVideos` 更新。
8. 准备失败时，item 保持 `.notReady`，显示现有 alert。

### 生成集锦

1. View 使用 `VideoClipSegmentPlanner.highlightPlan` 计算当前 plan。
2. planner 保留当前合并逻辑：同视频重叠或间隔不超过 1 秒的片段合并。
3. View 调用 `VideoClipEditingService.makeHighlightClip`。
4. asset provider 优先使用临时文件 URL；否则通过 Photos asset 请求 AVAsset。
5. Photos network error 可 fallback 到 picker 临时文件。
6. 导出成功后，`VideoClipPhotoLibrarySaver` 保存到相册。
7. 保存成功后删除输出临时文件、取消准备任务、清理临时视频、清空当前选择并提示用户。
8. 不修改 `TrainingSession`。

## 错误处理

用户可见错误文案保持现状：

- 无法读取视频 -> `.failedToLoad`
- 相册读取权限不足 -> `.photoLibraryAccessDenied`
- 缺少拍摄时间 -> `.missingRecordedStartAt`
- 视频时长无效 -> `.invalidDuration`
- iCloud 视频未准备好 -> `.notReady`
- 不覆盖当前训练 -> `.noMarkerCoverage`

Service 层可以定义内部错误类型，但 View 层继续消费 `SelectedTrainingVideoSelectionItem` 和 `SelectedTrainingVideoUnavailableReason`，避免 UI 关注平台错误细节。

## 测试策略

1. 调整 PRD 后不需要代码测试，但提交前检查文档中没有旧决策残留。
2. 修改 `ClipSettingsStoreTests`，确认默认值为前 9 秒、后 4 秒，并确认用户保存值可被下次加载。
3. 调整 `VideoClipSegmentPlannerTests` 测试命名，明确合并片段和 `1-2/10` 标签是预期行为。
4. 为新 service 增加 focused 单元测试：
   - metadata 缺失时返回 `.missingRecordedStartAt`。
   - duration 无效时返回 `.invalidDuration`。
   - 视频不覆盖训练打点时返回 `.noMarkerCoverage`。
   - readiness checker 失败时返回 `.notReady`。
   - 本地临时文件视频跳过 Photos readiness。
5. 全量验证：
   - `xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`
   - `xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5'`

## 风险与控制

- Photos/AVFoundation API 依赖系统框架，单元测试不应强依赖真实相册。通过协议或 closure 注入关键行为，测试 service 的决策逻辑。
- `TrainingSessionHighlightView` 拆分时容易改变清理时机。实现计划必须明确 onDisappear、生成成功、重新选择视频三处清理行为。
- iCloud 准备流程有并发任务和 runID 防串扰逻辑。拆分时保留 View 对 task 生命周期的控制，service 只执行一次准备请求。
- 片段合并逻辑已经有测试，应保留并改名强化语义，不在本轮改算法。
- Xcode project 使用文件系统同步分组，新增 Swift 文件应自动进入 target；提交前仍需要通过 scheme 测试验证。

## 验收标准

- PRD 与已确认产品决策一致。
- `TrainingSessionHighlightView.swift` 明显变薄，平台读取细节进入 service。
- 默认剪辑窗口为前 9 秒、后 4 秒。
- 用户修改剪辑范围后继续本地保留。
- 重叠或近邻片段继续合并，合并标签继续显示为 `1-2/10`。
- 训练记录模型不新增剪辑状态或同步状态。
- iPhone 和 Watch scheme 测试通过。
