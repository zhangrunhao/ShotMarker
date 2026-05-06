# Watch 到 iPhone 训练记录同步 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 Watch 端长按结束训练后，将本次训练的开始时间、结束时间和打点时间同步到 iPhone 端，并持久化为手机首页可展示的训练记录。

**Architecture:** 使用 `WatchConnectivity` 的 `WCSession.transferUserInfo(_:)` 传输“已完成训练记录”和“导入确认 ACK”。Watch 端负责生成可编码 payload、写入本地 outbox、发起传输、在收到 iPhone 导入成功 ACK 后删除本地记录；iPhone 端负责接收 payload、幂等导入本地 `TrainingSessionStore`、通知首页刷新，并回传 ACK。

**Tech Stack:** SwiftUI, Foundation, WatchConnectivity, XCTest, JSONEncoder/JSONDecoder, NotificationCenter.

## 完成情况

截至 2026-05-06，Watch 到 iPhone 训练记录同步相关工作已完成。当前 `main` 分支包含跨端 payload、Watch outbox 与 ACK 重试、iPhone 导入与 ACK 回传、首页自动刷新、同步诊断入口、companion 配置和手表图标补充等实现。

本地验证结果：

- iOS 测试：`xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'id=4590B1EB-982B-4CF8-AAAE-FA6FCAECB242'`
- Watch 测试：`xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'id=7AD71B7D-B377-4ADA-AAF4-1980BD270BA8'`
- iOS build：`xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'id=4590B1EB-982B-4CF8-AAAE-FA6FCAECB242'`
- Watch build：`xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'id=7AD71B7D-B377-4ADA-AAF4-1980BD270BA8'`

## 计划制定时确认的起点

计划制定时，长按结束训练后还不能向手机端同步数据。

当时已确认的事实：

- 当时代码中没有 `WatchConnectivity`、`WCSession`、`transferUserInfo`、`sendMessage` 或 `updateApplicationContext` 的实现。
- 当时 Watch 端 `WatchTrainingViewModel` 只维护 `startedAt`、`endedAt`、`markers`，结束训练时只切换状态，没有生成 `TrainingSession` 或同步 payload。
- 当时 iPhone 端有 `TrainingSessionStore`，但没有 Watch 接收服务，也没有导入训练记录的幂等逻辑。
- 早期计划文档中已经把 Watch-to-iPhone sync 列为 Milestone 3，但当时代码还没有实现该里程碑。

## 推荐方案

采用 `WCSession.transferUserInfo(_:)` 作为 P0 同步通道。

原因：

- 训练记录只需要在训练结束后同步，不要求实时到达。
- `transferUserInfo` 是后台排队式传输，适合“完成后传一条记录”的场景。
- 比 `sendMessage` 更适合手机不在附近、iPhone App 未打开、网络状态不稳定的情况。
- 比 `updateApplicationContext` 更适合多条历史训练记录，因为 application context 只保留最新状态。

数据流：

1. 用户在 Watch 上长按开始训练。
2. 用户训练中双击打点，Watch 记录每次打点绝对时间。
3. 用户再次长按结束训练。
4. Watch ViewModel 生成 `TrainingSessionSyncPayload`。
5. Watch Sync Service 将 payload 写入本地 outbox，并调用 `WCSession.transferUserInfo`。
6. iPhone Sync Service 收到 userInfo 后解码 payload。
7. iPhone Importer 将 payload 转成 `TrainingSession`，按 `id` 幂等写入 `TrainingSessionStore`。
8. iPhone 导入成功后发送训练记录变更通知。
9. iPhone Sync Service 生成 `TrainingSessionSyncAckPayload`，通过 `WCSession.transferUserInfo` 回传给 Watch。
10. Watch Sync Service 收到 ACK 后，按 `trainingSessionId` 从 outbox 删除对应记录。
11. 首页 ViewModel 收到通知后重新 load，列表展示新训练记录。

## 失败语义与队列边界

本方案不是只依赖 WatchConnectivity 的系统队列，而是使用“两层队列”：

- **系统传输队列：** `WCSession.transferUserInfo(_:)` 创建的系统级后台传输任务，可通过 `outstandingUserInfoTransfers` 观察尚未完成的 user info transfers。它解决“什么时候把数据送到对端”的问题。
- **业务 outbox 队列：** Watch app 自己持久化的待确认训练记录队列。它解决“这条训练记录是否已经被 iPhone 成功保存”的问题。

失败处理规则：

- Watch 端生成 payload 后，必须先写入 outbox，再调用 `transferUserInfo`。
- 如果 `WCSession` 不可用、未激活或传输失败，payload 保留在 outbox，后续重试。
- 如果 `transferUserInfo` 的 `didFinish` 成功，只能说明系统层传输完成，不能说明 iPhone 已保存训练记录。此时 outbox 记录进入 `awaitingAck` 状态，不能删除。
- iPhone 只有在 `TrainingSessionImporter` 成功写入 `TrainingSessionStore` 后，才能回传 ACK。
- Watch 只有收到对应 `trainingSessionId` 的 ACK 后，才能删除 outbox 记录。
- 如果 ACK 丢失，Watch 会继续重发该 payload。iPhone importer 必须按 `TrainingSession.id` 幂等导入，重复 payload 不会产生重复训练记录，并且应再次发送 ACK。

## 方案妥协

这个方案有妥协，但妥协是有意的，符合 P0 范围。

- 不做实时同步。结束训练后才同步整条训练记录，训练中手机端不会实时显示打点。
- 不引入 Core Data 或 CloudKit。继续沿用当前 JSON 文件存储，降低实现成本。
- 不做复杂冲突解决。用训练记录 `id` 做幂等导入，同一个 `id` 重复到达时只保留一条。
- Watch 端只保留待同步 outbox，不做完整训练历史管理。历史展示仍以 iPhone 端为准。
- P0 不实现同步进度 UI。可以先提供失败待重试机制，后续再加“待同步/已同步”状态展示。
- P0 不追求 exactly-once 传输语义。实际语义是 at-least-once 传输，加上 iPhone 幂等导入和 ACK 确认，保证最终不会重复落库。
- 如果当前 Watch target 是独立 Watch App，需要验证 Xcode 工程是否具备与 iPhone App 通信的配对关系。若目标配置不满足 WatchConnectivity 的 companion 通信要求，需要先调整 target 配置。

## Task 1: 新增跨端同步 Payload

**Files:**

- Create: `Shared/TrainingSessionSyncPayload.swift`
- Modify: `ShotMarker.xcodeproj/project.pbxproj`
- Test: `ShotMarkerTests/TrainingSessionSyncPayloadTests.swift`
- Test: `ShotMarkerWatchAppTests/TrainingSessionSyncPayloadTests.swift`

**Steps:**

1. 创建 `Shared/TrainingSessionSyncPayload.swift`，并把文件加入 iOS target 和 Watch target。
2. 定义 `TrainingSessionSyncPayload` 和 `ShotMarkerEventSyncPayload`，字段使用 `id`、`startedAt`、`endedAt`、`events`。
3. 定义 `TrainingSessionSyncAckPayload`，字段使用 `trainingSessionId`、`importedAt`。
4. 让 payload 和 ACK 都遵守 `Codable`、`Equatable`。
5. 在 iOS 测试 target 写 payload 和 ACK 的 JSON 编解码测试。
6. 在 Watch 测试 target 写同样的编解码测试，证明 Watch 端也能使用共享模型。
7. 运行 iOS 和 Watch 对应测试。

**Acceptance:**

- 同一份 payload 类型可被 iOS 和 Watch 编译。
- payload 编码后能完整还原 id、开始时间、结束时间、事件 id 和事件时间。
- ACK 编码后能完整还原训练记录 id 和导入确认时间。

## Task 2: 让 Watch 结束训练时产出完成记录

**Files:**

- Modify: `ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift`
- Modify: `ShotMarkerWatchAppTests/WatchTrainingViewModelTests.swift`

**Steps:**

1. 先写失败测试：长按开始、双击一次、长按结束时，ViewModel 返回一个 `TrainingSessionSyncPayload`。
2. 断言 payload 的 `startedAt` 来自开始训练时间，`endedAt` 来自结束训练时间，events 来自所有双击打点。
3. 给 ViewModel 注入 `idFactory`，让测试可以断言固定 UUID。
4. 修改 `handleLongPress()`，让它在“训练中 -> 未训练”时返回完成 payload，在“未训练 -> 训练中”时返回 nil。
5. 确保结束后 UI 显示的打点数仍按当前需求回到 0。
6. 运行 Watch ViewModel 测试。

**Acceptance:**

- 结束训练时能拿到一条完整 payload。
- 开始训练时不会产生 payload。
- 未训练状态下双击仍不会打点。

## Task 3: Watch 端同步服务与本地 Outbox

**Files:**

- Create: `ShotMarkerWatchApp/Services/WatchTrainingSyncService.swift`
- Create: `ShotMarkerWatchApp/Services/WatchTrainingSyncOutbox.swift`
- Test: `ShotMarkerWatchAppTests/WatchTrainingSyncServiceTests.swift`
- Test: `ShotMarkerWatchAppTests/WatchTrainingSyncOutboxTests.swift`

**Steps:**

1. 定义 `WatchTrainingSyncServiceProtocol`，包含 `enqueueCompletedSession(_:)`。
2. 定义 `WatchConnectivitySessionProtocol`，包装 `WCSession` 需要的能力，方便测试替换。
3. 实现 `WatchTrainingSyncOutbox`，把待同步 payload 保存到 Application Support 下的 JSON 文件。
4. outbox 条目使用状态字段：`pendingTransfer`、`awaitingAck`。
5. 写失败测试：enqueue 后 outbox 中保存 payload，状态为 `pendingTransfer`。
6. 写失败测试：WCSession 可用时调用 `transferUserInfo`，userInfo 使用 `type` 和 `payload` 两个字段。
7. 写失败测试：WCSession 不可用时 payload 仍留在 outbox。
8. 写失败测试：系统传输成功后只把条目标记为 `awaitingAck`，不删除。
9. 实现 `WatchTrainingSyncService`。
10. 实现 `WCSession` 适配器，并在服务初始化时 activate session。
11. 运行 Watch sync 相关测试。

**Acceptance:**

- Watch 端不会因为手机不可用丢失训练记录。
- userInfo payload 是稳定可解码的 `Data`，不是散落字段。
- Watch 不会因为系统传输成功就提前删除业务 outbox。
- 服务逻辑可用 fake session 测试，不依赖真实模拟器配对。

## Task 4: Watch UI 在结束训练后触发同步

**Files:**

- Modify: `ShotMarkerWatchApp/Views/WatchTrainingView.swift`
- Modify: `ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift`
- Test: `ShotMarkerWatchAppTests/WatchTrainingViewModelTests.swift`

**Steps:**

1. 修改 ViewModel API，使结束训练时返回 payload。
2. 在 `WatchTrainingView` 中持有 `WatchTrainingSyncService`。
3. 长按动画缩小到 0.5 后调用 `handleLongPress()`。
4. 如果返回 payload，则调用 `syncService.enqueueCompletedSession(payload)`。
5. 同步触发后再恢复按钮大小。
6. 训练结束触发同步时播放轻量反馈；同步失败不阻断 UI 状态切换。
7. 运行 Watch 测试和 Watch build。

**Acceptance:**

- 训练结束路径会触发同步服务。
- 动画和状态切换顺序保持不变：缩小到 0.5 后才切换状态并发起同步。

## Task 5: iPhone 端训练记录导入器

**Files:**

- Create: `ShotMarker/Services/TrainingSessionImporter.swift`
- Modify: `ShotMarker/Services/TrainingSessionStore.swift`
- Test: `ShotMarkerTests/TrainingSessionImporterTests.swift`

**Steps:**

1. 写失败测试：导入一个 payload 后，store 中出现一条对应 `TrainingSession`。
2. 写失败测试：同一个 payload 导入两次，store 里仍只有一条记录。
3. 写失败测试：当本地已有同 id 记录时，导入逻辑可选择替换或忽略；P0 推荐替换，保证 Watch 重传修正数据。
4. 在 `TrainingSessionStoreProtocol` 添加一个更适合导入的 helper，或在 importer 内部 load 后 merge 再 save。
5. 实现 `TrainingSessionImporter`，负责 payload 到 domain model 的转换和幂等写入。
6. 运行 iOS importer 测试。

**Acceptance:**

- 手机端导入是幂等的。
- 导入逻辑不依赖 UI。
- 失败时抛出错误，供 sync service 记录日志或后续重试。

## Task 6: iPhone 端 WatchConnectivity 接收与 ACK 回传服务

**Files:**

- Create: `ShotMarker/Services/PhoneWatchSyncService.swift`
- Test: `ShotMarkerTests/PhoneWatchSyncServiceTests.swift`

**Steps:**

1. 定义 `PhoneWatchSyncService`，作为 `WCSessionDelegate`。
2. 在服务启动时检查 `WCSession.isSupported()`，支持时设置 delegate 并 activate。
3. 实现 `session(_:didReceiveUserInfo:)`。
4. userInfo `type` 不匹配时忽略。
5. userInfo payload 不能解码时忽略并记录错误。
6. payload 解码成功时调用 `TrainingSessionImporter.import(payload)`。
7. 导入成功后通过 `NotificationCenter` 发布 `trainingSessionsDidChange`。
8. 导入成功后生成 `TrainingSessionSyncAckPayload`，通过 `WCSession.transferUserInfo` 回传给 Watch。
9. 如果导入失败，不发送 ACK，让 Watch 保留 outbox 并后续重试。
10. 写测试覆盖成功导入、ACK 回传、错误 type、错误 payload、重复 payload。

**Acceptance:**

- iPhone app 启动后具备 Watch userInfo 接收能力。
- 收到重复数据不会污染本地训练列表。
- 只有本地 store 写入成功后才发送 ACK。
- ACK 丢失或发送失败不会破坏 iPhone 端幂等导入；Watch 后续重发时 iPhone 可再次 ACK。

## Task 7: iPhone App 启动并持有同步服务

**Files:**

- Modify: `ShotMarker/ShotMarkerApp.swift`
- Modify: `ShotMarker/Views/TrainingSessionListView.swift`

**Steps:**

1. 在 `ShotMarkerApp` 初始化 `TrainingSessionStore`。
2. 用同一个 store 初始化 `PhoneWatchSyncService` 和首页 ViewModel。
3. 确保 sync service 生命周期覆盖整个 app 生命周期，而不是列表页面生命周期。
4. App 启动时调用 sync service `start()`。
5. 删除首页内部重复创建 store 的路径，改成依赖注入，保留 Preview 专用初始化。
6. 运行 iOS build。

**Acceptance:**

- App 打开后无需进入特定页面也能接收 Watch 数据。
- 首页和同步服务写入同一个 store 文件。

## Task 8: 首页自动刷新

**Files:**

- Modify: `ShotMarker/ViewModels/TrainingSessionListViewModel.swift`
- Test: `ShotMarkerTests/TrainingSessionListViewModelTests.swift`

**Steps:**

1. 给 `TrainingSessionListViewModel` 注入 `NotificationCenter`。
2. 订阅 `trainingSessionsDidChange`。
3. 收到通知时调用 `load()`。
4. 写测试：初始为空，store 更新后发送通知，rows 自动刷新。
5. 注意在 `deinit` 里释放 observer，避免泄漏。
6. 运行 ViewModel 测试。

**Acceptance:**

- Watch 同步到达后，手机首页无需重启 app 即可展示新记录。

## Task 9: Watch 端 Outbox 重试与 ACK 删除

**Files:**

- Modify: `ShotMarkerWatchApp/Services/WatchTrainingSyncService.swift`
- Modify: `ShotMarkerWatchApp/Services/WatchTrainingSyncOutbox.swift`
- Test: `ShotMarkerWatchAppTests/WatchTrainingSyncServiceTests.swift`

**Steps:**

1. 实现 `retryPendingSessions()`。
2. Watch app 启动时调用一次重试。
3. `WCSessionDelegate` 收到 activation 完成后调用一次重试。
4. `retryPendingSessions()` 发送 `pendingTransfer` 条目，也发送超过重试间隔仍未收到 ACK 的 `awaitingAck` 条目。
5. transfer 成功回调后，把对应 outbox 条目标记为 `awaitingAck`，记录 `lastTransferFinishedAt`，但不删除。
6. transfer 失败回调后，把对应 outbox 条目标记为 `pendingTransfer`，等待下次启动或 activation 重试。
7. 实现 `session(_:didReceiveUserInfo:)` 处理 `TrainingSessionSyncAckPayload`。
8. 收到 ACK 后，按 `trainingSessionId` 删除对应 outbox 条目。
9. 收到未知 `trainingSessionId` 的 ACK 时忽略，不抛错。
10. 写测试覆盖 transfer 成功不删除、transfer 失败保留、ACK 成功删除、未知 ACK 忽略、ACK 丢失后重发。

**Acceptance:**

- Watch 端在手机暂不可用时不会丢训练记录。
- 后续打开 Watch app 或 session ready 时会重试。
- Watch 端只有收到 iPhone 导入成功 ACK 后才删除本地 outbox。
- iPhone 已导入但 ACK 丢失时，重复发送不会在 iPhone 端产生重复记录。

## Task 10: 工程配置核查

**Files:**

- Modify if needed: `ShotMarker.xcodeproj/project.pbxproj`

**Steps:**

1. 确认 iOS target 和 Watch target 都能 import `WatchConnectivity`。
2. 确认共享 payload 文件加入 iOS app、Watch app、对应测试 target。
3. 确认 Watch target 和 iOS target 的 bundle 配置满足 WatchConnectivity 配对通信要求。
4. 如果当前 Watch target 的 `WKWatchOnly = YES` 导致无法与 iPhone companion 通信，调整为支持 companion 通信的 Watch app 结构，或新建正确的 Watch App target。
5. 分别运行 iOS build 和 Watch build。

**Acceptance:**

- 两端都能编译并启动。
- 真机或成对模拟器上 `WCSession.isSupported()`、activation 状态符合预期。

## Task 11: 端到端手动验证

**Files:**

- No code changes expected.

**Steps:**

1. 启动 iPhone 模拟器和配对 Watch 模拟器，或使用真机加 Apple Watch。
2. 安装 iPhone app 和 Watch app。
3. 打开 iPhone app 首页，确认当前列表状态。
4. 打开 Watch app。
5. 长按开始训练。
6. 双击打点至少两次。
7. 长按结束训练。
8. 回到 iPhone app，确认新训练记录出现在首页，打点数正确。
9. 检查 Watch outbox，确认收到 ACK 后对应记录已删除。
10. 关闭 iPhone app 后重复一次训练，重新打开 iPhone app，确认 queued transfer 可到达并最终 ACK。
11. 断开手机或关闭蓝牙场景下结束训练，恢复连接后确认 outbox 重试。
12. 人为阻断 ACK 或模拟 ACK 丢失，确认 Watch 会重发，iPhone 不产生重复训练记录，并在再次 ACK 后删除 Watch outbox。

**Acceptance:**

- 长按结束后产生的训练记录最终能在 iPhone 首页出现。
- 重复接收不会产生重复记录。
- 手机不可用时不会丢失 Watch 端完成记录。
- Watch 收到 iPhone 成功导入 ACK 后，才删除本地待同步记录。

## Task 12: 最终验证与提交

**Files:**

- All modified files.

**Steps:**

1. 运行 iOS 测试：`xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17'`
2. 运行 Watch 测试：`xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)'`
3. 运行 iOS build。
4. 运行 Watch build。
5. 查看 `git diff --stat`，确认只包含同步功能相关文件。
6. 提交：`git commit -m "feat: 同步手表训练记录"`

**Acceptance:**

- 自动化测试通过。
- 两端 build 通过。
- 手动端到端验证通过或明确记录当前模拟器限制。

## 风险与处理

- **WatchConnectivity 模拟器配对不稳定：** 自动化测试用 fake session 覆盖核心逻辑，真实链路用手动验证补充。
- **App 未启动时接收时机不确定：** 使用 `transferUserInfo`，并在 iPhone app 启动后通过 WCSession delegate 接收排队数据。
- **重复传输：** iPhone importer 按 `TrainingSession.id` 幂等导入。
- **Watch 端传输失败：** Watch outbox 持久化 payload，并在启动和 session activation 后重试。
- **ACK 丢失：** Watch 不删除 outbox，后续重发 payload；iPhone 幂等导入后再次回 ACK。
- **系统传输成功但业务导入失败：** Watch 仍未收到 ACK，因此保留 outbox；iPhone 端修复或下次成功导入后再 ACK。
- **共享模型 target membership 易出错：** 在 Task 1 和 Task 10 单独验证 iOS、Watch、两套测试 target 都能编译。

## 不做事项

- P0 不做训练中实时同步。
- P0 不做同步状态 UI。
- P0 不做跨设备云同步。
- P0 不做复杂冲突合并。
- P0 不改手机端列表的数据展示结构，除非后续要展示“已同步/待剪辑/已剪辑”。
