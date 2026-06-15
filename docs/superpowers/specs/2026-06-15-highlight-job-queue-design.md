# Highlight Job Queue Design

日期：2026-06-15
状态：已确认

## 背景

当前 iPhone 集锦生成流程在 `TrainingSessionHighlightView` 页面内执行。用户点击“生成集锦”后，页面用 `isGenerating` 和 `generationProgress` 展示导出进度；页面退出时会取消准备任务，并在非生成状态下清理临时视频。生成成功后，输出视频保存到系统相册，页面清空当前视频选择并弹出完成提示。

这个模型适合一次性页面流程，但不适合长时间视频导出。用户无法回到首页继续查看训练记录，也无法从首页取消任务；如果 App 被系统终止或用户强制关闭，页面内状态会丢失。新需求是把集锦生成提升为首页可见的任务队列：创建剪切任务后回到首页，首页展示任务进度；任务可取消；完成后保留可播放视频入口；强关 App 后未完成任务显示“已中断，可重新开始”。

这会推翻旧 PRD 中“P0 不持久化 HighlightJob”的决策。训练记录本身仍不记录剪辑状态，新增的持久化只属于本地集锦任务队列。

## 产品决策

- 用户在集锦页面点击“生成集锦”后创建一个本地任务，并返回首页。
- 首页训练记录列表上方显示“集锦任务”区域。
- 任务运行时展示状态、进度和关闭按钮。
- 关闭运行中任务会取消导出，清理未完成输出，并从任务列表移除。
- 任务完成后一直保留在首页，直到用户手动清理。
- 已完成任务展示视频入口，点击后用系统播放器打开 App 本地保存的视频文件。
- 清理已完成任务只删除任务记录和 App 本地视频副本，不删除已经保存到系统相册的视频。
- App 被强制关闭或系统终止后，重开 App 时把未完成运行态任务显示为“已中断，可重新开始”。
- 已中断或失败任务可以重新开始，也可以手动清理。
- iOS 后台继续导出只能作为尽力而为增强，不能承诺强关后继续执行。

## 目标

1. 将集锦生成从页面内状态迁移到独立任务队列。
2. 首页展示所有未清理集锦任务的状态和进度。
3. 支持运行中任务取消，并真正取消 `AVAssetExportSession`。
4. 持久化任务列表和完成输出，支持 App 重启后的“已中断，可重新开始”。
5. 保留现有剪辑规划、导出、overlay、保存相册行为。
6. 不把集锦状态写回 `TrainingSession`。

## 非目标

- 不做云同步任务队列。
- 不让 Watch 端感知集锦任务。
- 不承诺 App 强关后继续剪辑。
- 不自动删除已完成任务。
- 不删除系统相册里的已保存视频。
- 不新增生成前视频预览或复杂任务批处理。
- 不改变 `VideoClipSegmentPlanner` 的算法。

## 架构

新增一个 iOS 本地 `HighlightJob` 系统。训练记录继续只表达训练事实，集锦任务作为独立本地队列持久化。

依赖方向：

```text
ShotMarkerApp
  -> HighlightJobStore
  -> HighlightJobManager

ContentView
  -> TrainingSessionListView
       -> HighlightJobListSection
       -> TrainingSessionHighlightView

TrainingSessionHighlightView
  -> HighlightJobManager.createJob(...)

HighlightJobManager
  -> HighlightJobStore
  -> HighlightJobRunner

HighlightJobRunner
  -> VideoClipSegmentPlanner
  -> VideoClipEditingService
  -> VideoClipPhotoLibrarySaver
  -> PhotoLibraryVideoAssetProvider
  -> HighlightJobFileStore
```

`HighlightJobManager` 是首页和集锦页面共享的 `@StateObject` / `ObservableObject`。它加载持久化任务，发布任务列表，创建任务，启动任务，取消任务，重新开始任务，清理任务，并协调单个 `HighlightJobRunner` 执行导出。

第一版同一时间只运行一个导出任务。新任务创建后进入 `.queued`；如果没有其他任务运行，立即开始；如果已有任务运行，则停留在 `.queued`，等待前一个任务完成、失败或取消后再开始。这样避免多个 `AVAssetExportSession` 同时抢占 CPU、磁盘和 Photos 资源。

## 数据模型

### HighlightJob

`HighlightJob` 使用 `Codable` 持久化。

字段：

- `id: UUID`
- `trainingSession: TrainingSession`
- `selectedVideos: [HighlightJobVideo]`
- `clipSettings: ClipSettings`
- `status: HighlightJobStatus`
- `progress: HighlightJobProgress`
- `outputVideoPath: String?`
- `errorMessage: String?`
- `createdAt: Date`
- `updatedAt: Date`

任务保存训练记录快照，而不是只保存 `trainingSessionID`。这样即使用户之后导入、合并或删除训练记录，已创建任务仍能重新开始。

### HighlightJobVideo

字段：

- `id: String`
- `recordedStartAt: Date`
- `duration: TimeInterval`
- `source: HighlightJobVideoSource`

`source`：

- `.photoLibraryAsset(localIdentifier: String)`
- `.jobInputFile(relativePath: String)`

对 Photos asset 视频，任务保存 `localIdentifier`。对 picker fallback 或临时文件视频，创建任务时复制到长期 job input 目录，任务保存相对路径。不能继续依赖 temporary directory，否则回首页或重启后源文件可能被清理。

### HighlightJobStatus

状态：

- `.queued`
- `.running`
- `.saving`
- `.completed`
- `.failed`
- `.interrupted`

取消后的任务不持久保留；用户取消运行中任务后，任务从列表移除。

App 启动加载任务时：

- `.queued` -> `.interrupted`
- `.running` -> `.interrupted`
- `.saving` -> `.interrupted`
- `.completed` 保持不变
- `.failed` 保持不变
- `.interrupted` 保持不变

这样不会错误承诺上次任务仍在后台执行。

### HighlightJobProgress

字段：

- `completedMarkerCount: Int`
- `totalMarkerCount: Int`

UI 用它展示 `正在生成 3/12` 和线性进度。状态为 `.saving` 时可以显示“正在保存到相册”。

## 文件存储

### HighlightJobStore

保存任务 JSON：

```text
Application Support/ShotMarker/highlight-jobs.json
```

职责：

- 加载任务列表。
- 保存完整任务列表。
- App 启动时恢复中断状态。
- 保持写入原子性。

### HighlightJobFileStore

管理任务输入和输出文件：

```text
Application Support/ShotMarker/HighlightJobs/
  Inputs/<job-id>/<video-id>.<ext>
  Outputs/<job-id>/highlight.mov
```

职责：

- 创建任务时复制 picker fallback 视频到 `Inputs`。
- 导出完成后把 temporary output 移动到 `Outputs`。
- 取消任务或手动删除任务时清理 input/output。
- 重新开始失败或中断任务前只清理旧 output，不删除 input。
- 为已完成任务返回可播放 URL。

## 首页 UI

`TrainingSessionListView` 在训练记录列表上方新增 `HighlightJobListSection`。

显示规则：

- 没有任务时不显示该区域。
- 有任务时显示标题“集锦任务”。
- 每个任务一行，展示训练日期、状态、进度或结果。
- `.queued / .running`：显示 `ProgressView` 和关闭按钮。
- `.saving`：显示“正在保存到相册”和关闭按钮。
- `.interrupted`：显示“已中断，可重新开始”，提供“重新开始”和清理按钮。
- `.failed`：显示失败原因，提供“重新开始”和清理按钮。
- `.completed`：显示“已完成”，提供播放入口和清理按钮。

关闭按钮使用系统图标 `xmark.circle.fill`，清理按钮使用 `trash`，播放入口使用 `play.circle`。按钮应有 accessibility label。

首页任务区域应该保持克制，不使用大卡片或营销式布局；它是工作队列，优先可扫描和可操作。

## 集锦页面流程

`TrainingSessionHighlightView` 保留视频选择、iCloud 准备、覆盖结果和剪辑范围设置。

点击“生成集锦”：

1. 使用当前 `plan` 验证有可生成片段。
2. 调用 `HighlightJobManager.createJob(session:selectedVideos:selectedItems:clipSettings:)`。
3. 对临时视频源，创建任务时复制到 job input 目录。
4. 持久化新任务，状态为 `.queued`。
5. 启动任务运行，状态变为 `.running`。
6. 关闭当前详情页返回首页。

页面不再持有导出进度，也不在生成中禁用导航。导出进度由首页任务列表展示。

## 任务运行流程

`HighlightJobRunner` 执行单个任务：

1. 将任务状态设为 `.running`，进度归零。
2. 使用 job 内的 `trainingSession`、`selectedVideos`、`clipSettings` 重新计算 `HighlightClipPlan`。
3. 如果没有可生成片段，任务转为 `.failed`。
4. 调用 `VideoClipEditingService.makeHighlightClip`。
5. asset provider 根据 `HighlightJobVideoSource` 返回 `AVAsset`：
   - Photos asset：通过 `PhotoLibraryVideoAssetProvider` 请求。
   - job input file：用 `AVURLAsset` 打开本地文件。
6. 每次进度回调更新 job progress 并持久化。
7. 导出完成后把 output 移动到 job output 目录。
8. 状态设为 `.saving` 并持久化。
9. 调用 `VideoClipPhotoLibrarySaver.saveVideo` 保存到系统相册。
10. 保存成功后状态设为 `.completed`，保留 `outputVideoPath`。

如果保存相册失败但本地 output 已存在，任务状态仍应转为 `.failed`，错误信息说明“视频已生成，但保存到相册失败”。后续可以增加“重新保存到相册”，本轮不做。

如果任务完成、失败或取消，manager 检查是否还有 `.queued` 任务；有的话自动启动下一个。

## 取消和中断

运行中任务取消：

1. `HighlightJobManager.cancel(jobID:)` 取消对应 Swift `Task`。
2. `VideoClipEditingService` 在任务取消时调用 `AVAssetExportSession.cancelExport()`。
3. runner 捕获 `CancellationError` 后清理未完成输出。
4. manager 从任务列表移除该 job。
5. store 持久化移除后的列表。

App 强关或系统终止：

- 运行中的 Swift task 无法继续。
- 下次启动 `HighlightJobStore` 把 `.queued / .running / .saving` 标记为 `.interrupted`。
- 首页展示“已中断，可重新开始”。
- 用户点重新开始后清理旧的未完成 output，重新跑同一个 job。

## 打开完成视频

已完成任务点击播放入口：

- 如果 `outputVideoPath` 存在且文件仍在，展示系统播放器播放本地文件。
- iOS 使用 `AVPlayerViewController` 或 Quick Look 风格的系统预览。
- 如果文件不存在，任务转为 `.failed`，错误为“本地视频文件不存在，请重新生成”。

这里不使用 Safari。Safari 不适合直接播放 App 沙盒内的本地视频；系统播放器更符合 iOS 行为和用户预期。

## 错误处理

用户可见错误：

- 无可生成片段：`所选视频没有覆盖任何打点。`
- 源视频不存在：`找不到任务使用的视频，请重新选择视频。`
- 相册读取权限不足：沿用现有相册权限错误文案。
- iCloud 视频无法读取：沿用现有 iCloud 网络错误文案。
- 导出失败：使用 `LocalizedError.errorDescription`，否则使用系统错误描述。
- 保存相册失败：`视频已生成，但保存到相册失败。`
- 本地输出丢失：`本地视频文件不存在，请重新生成。`

所有失败都保留任务，用户可以重新开始或清理。

## 后台行为

本轮核心语义是“App 活着时后台尽量继续，App 被强关后可恢复为中断状态”。可以在实现时申请短时间 background task，让用户切到其他 App 时导出尽量完成；但 UI 和文案不承诺后台一定成功。

如果后台时间耗尽或系统终止，任务按中断处理。

## 测试策略

单元测试：

1. `HighlightJobStoreTests`
   - 保存和加载任务。
   - App 启动恢复时 `.queued / .running / .saving` 转为 `.interrupted`。
   - `.completed / .failed / .interrupted` 保持状态。

2. `HighlightJobFileStoreTests`
   - job input 文件复制到长期目录。
   - output 文件移动到 job output 目录。
   - 清理任务时删除 input/output。

3. `HighlightJobManagerTests`
   - 创建任务后持久化并启动。
   - 取消运行中任务会移除任务。
   - 已完成任务清理会删除本地 output 并移除记录。
   - 失败和中断任务可以重新开始。

4. `VideoClipEditingServiceTests`
   - Swift task 取消时调用 export cancellation 注入点或可测试替身。

UI 或 ViewModel 测试：

- 首页没有任务时不显示任务区域。
- running/saving/completed/interrupted/failed 对应操作按钮正确。
- 完成任务点击播放时请求打开本地 URL。

集成验证：

- 创建任务后自动回首页，首页展示进度。
- 运行中取消后任务消失，未完成文件被清理。
- 完成后任务保留，点击可播放本地视频。
- 强行终止 App 后重开，原运行中任务显示“已中断，可重新开始”。
- 重新开始中断任务后可以完成。

## 风险与控制

- Photos localIdentifier 可能失效或用户删除原视频。重新开始时应失败并提示重新选择视频。
- picker fallback 临时文件不能用于持久任务。创建任务时必须复制到长期 input 目录。
- `AVAssetExportSession` 取消需要明确接入，否则 UI 取消可能只是取消 Swift task，底层导出仍继续跑。
- 同时运行多个视频导出会增加内存、磁盘和 Photos 访问风险。第一版采用串行队列，后续确有需求再评估并发。
- 保存相册失败和本地输出成功是两个阶段，状态和错误文案要区分。
- 首页任务列表会改变 `ContentView`/`TrainingSessionListView` 注入结构，应保持训练列表原有选择、导入导出、日志导出行为不变。
- 完成任务长期保留会占用 App 存储。用户手动清理时必须删除 App 本地副本。

## 验收标准

- 生成集锦后自动回到首页。
- 首页展示任务队列和运行进度。
- 运行中任务可以取消，取消后从列表移除。
- 完成任务一直保留到用户手动清理。
- 完成任务可用系统播放器打开本地视频。
- 完成视频仍保存到系统相册。
- App 强关后，未完成任务显示“已中断，可重新开始”。
- 重新开始中断任务可以重新导出。
- 训练记录模型不新增剪辑状态。
- iPhone scheme 测试通过，Watch scheme 不受影响。
