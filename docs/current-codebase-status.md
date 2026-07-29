# ShotMarker 当前项目进度说明

生成日期：2026-06-16
分析分支：`main`
当前提交：`2eaa62a docs: 更新 App Store 截图和公开页面地址`
工作区状态：生成本文档前 `git status -sb` 输出 `## main...origin/main`，当前本地 `main` 与 `origin/main` 对齐。
文档性质：这是基于当前仓库 HEAD 的项目进度报告，不是未来开发计划。

## 1. 总体结论

ShotMarker 当前已经推进到 App Store 1.1 提交流程。代码、截图、公开支持页面和隐私政策页面已经按 `ShotMarker` 口径整理完成；根据 App Store Connect 页面状态，`iOS App Version 1.1` 已进入 `Waiting for Review`。

相比旧文档记录的 `115322d docs: 补充日志导出P0验收结果`，当前仓库已经完成了集锦任务队列、视频准备和不可用视频处理、集锦任务列表、手动保存到相册、Apple Watch 数码表冠打点、App Store 截图和公开页面地址更新等工作。旧文档中的生成日期和提交号是历史快照，不代表当前项目状态。

## 2. 当前 Git 基准

- 当前分支：`main`
- 当前提交：`2eaa62a docs: 更新 App Store 截图和公开页面地址`
- 远端对齐：`HEAD -> main, origin/main, origin/HEAD`
- 对比旧文档提交 `115322d`：累计 `67 files changed, 12398 insertions(+), 665 deletions(-)`

`115322d..HEAD` 之间的主要提交方向包括：

- `docs`：补充代码现状说明、PRD、App Review 说明、公开页面地址、App Store 截图记录。
- `feat`：训练记录导入导出、不可用视频过滤、视频准备流程、集锦任务队列、集锦任务播放和保存、Watch 数码表冠打点。
- `fix`：相册视频读取超时、导出进度、不可用视频提示、生成进度跳转、视频导出取消、并发警告等问题。
- `test`：补充视频加载、片段规划、集锦任务、JSON 传输、Watch 表冠打点等测试。
- `chore`：发布 1.1.0 TestFlight 版本。

## 3. App Store 与公开页面

当前 App Store Connect 使用的 App 名称为 `ShotMarker`，不是 `ShotMaker`。

当前公开页面：

- 支持页面：`https://zhangrh.shop/shotmarker/support`
- 隐私政策：`https://zhangrh.shop/shotmarker/privacy`

已确认旧路径不可用：

- `https://zhangrh.shop/shotmaker/` -> 404
- `https://zhangrh.shop/shotmaker/support` -> 404

App Store 1.1 当前状态：

- 版本：`iOS App Version 1.1`
- 状态：`Waiting for Review`
- 处理建议：等待 Apple 审核；除非需要修改构建或元数据，否则不需要撤回版本。

## 4. App Store 截图

当前仓库新增 4 张 iPhone 6.5 英寸截图：

- `AppStoreScreenshots/2026-06-16-iphone-65/01-training-records.png`
- `AppStoreScreenshots/2026-06-16-iphone-65/02-highlight-setup.png`
- `AppStoreScreenshots/2026-06-16-iphone-65/03-highlight-ready.png`
- `AppStoreScreenshots/2026-06-16-iphone-65/04-highlight-generate.png`

截图尺寸均为 `1284 x 2778`，符合 App Store Connect 对 6.5 英寸 iPhone 截图的上传规格。

同时仓库中还保留了其他上架素材：

- `app-store-screenshots/apple-watch-46mm.png`
- `app-store-screenshots/apple-watch-49mm.png`
- `app-store-screenshots/ipad-13-inch.png`
- `app-store-screenshots/upload-ready/*.jpg`

## 5. 核心功能进度

### 5.1 训练记录与同步

项目仍以 SwiftUI 为主，包含 iPhone App、Apple Watch App、共享同步 payload、iPhone 单元测试和 Watch 单元测试。

当前主链路是：

1. 用户在 Apple Watch 上开始训练。
2. 训练过程中通过交互记录打点。
3. 训练结束后 Watch 端生成同步 payload。
4. iPhone 端接收并导入训练记录。
5. 用户在 iPhone 上为训练记录选择视频并生成集锦。

Watch 端原有双击打点能力仍保留，同时新增了数码表冠阈值打点能力。

### 5.2 Watch 数码表冠打点

新增 `CrownMarkerThresholdTracker` 相关测试和 Watch 端交互。训练中旋转 Apple Watch 数码表冠，累计变化达到阈值后会触发现有打点流程，并配合成功触觉反馈。

相关提交：

- `4e6dc47 docs: 设计手表旋钮打点交互`
- `a5e85d5 docs: 制定手表旋钮打点实现计划`
- `fc45a68 test: 添加手表旋钮打点阈值测试`
- `bd72c8d feat: 支持手表旋钮阈值打点`

### 5.3 集锦任务队列

当前已经不只是同步生成视频，而是引入了集锦任务模型和队列：

- `HighlightJob`
- `HighlightJobStore`
- `HighlightJobFileStore`
- `HighlightJobRunner`
- `HighlightJobManager`
- `HighlightJobListSection`
- `HighlightJobVideoPlayerView`

任务状态包括：

- `queued`
- `running`
- `saving`
- `completed`
- `failed`
- `interrupted`

这使首页可以展示集锦任务，用户可以查看任务进度、播放已完成集锦，并对完成结果进行保存或删除。

### 5.4 视频准备与不可用视频处理

当前视频选择和准备流程已拆分出多个服务和模型：

- `TrainingVideoLoadingService`
- `TrainingVideoTemporaryFileStore`
- `PhotoLibraryVideoAssetProvider`
- `SelectedTrainingVideoSelectionItem`
- `SelectedTrainingVideoReadinessChecker`

现有能力包括：

- 过滤不可用训练视频。
- 展示已选视频封面。
- 展示视频不可用原因。
- 支持手动准备未下载视频。
- 支持视频准备暂停和取消。
- 处理相册视频读取超时。

### 5.5 集锦生成与保存

当前集锦生成流程已经支持：

- 多视频片段规划。
- 保留音频。
- 生成进度反馈。
- 导出取消。
- 后台任务式生成。
- 已完成任务播放。
- 手动保存集锦到相册。
- 保存和删除前确认。

默认剪辑窗口目前为：

- 打点前：`9` 秒
- 打点后：`4` 秒

## 6. 测试与验证

当前仓库新增了多组测试，覆盖范围相比 `115322d` 明显扩大，包括：

- `HighlightJobFileStoreTests`
- `HighlightJobManagerTests`
- `HighlightJobRowViewDataTests`
- `HighlightJobRunnerTests`
- `HighlightJobStoreTests`
- `SelectedTrainingVideoReadinessCheckerTests`
- `SelectedTrainingVideoSelectionItemTests`
- `TrainingSessionJSONTransferServiceTests`
- `TrainingVideoLoadingServiceTests`
- `TrainingVideoTemporaryFileStoreTests`
- `VideoClipEditingServiceTests`
- `VideoClipSegmentPlannerTests`
- `WatchTrainingViewModelTests`

最近一次针对当前代码状态执行过 Debug build，结果为：

```text
** BUILD SUCCEEDED **
```

本报告生成时没有重新运行完整测试套件，因此不能把“完整测试套件通过”作为本报告结论。

## 7. 当前风险与注意事项

当前最重要的事项不是继续开发，而是等待 App Store 审核结果。审核期间需要注意：

- 不要随意撤回 `Waiting for Review` 的 1.1 版本。
- 如需修改构建、截图或元数据，可能需要从审核中移除当前版本后重新提交。
- 隐私政策页面计划后续修改时，要确保 App Store Connect 中填写的 URL 仍然可访问并返回 200。
- 如果 Apple 审核提出问题，应优先根据审核反馈补充 App Review 说明或修复对应行为。

## 8. 下一步建议

1. 等待 App Store 1.1 审核结果。
2. 审核通过后，记录上线版本、审核时间和最终公开页面。
3. 审核被拒时，先保存完整拒审原因，再针对性更新代码、文档或元数据。
4. 隐私政策正式修改后，重新确认 `https://zhangrh.shop/shotmarker/privacy` 返回 200 且内容和 App Store 填写一致。
