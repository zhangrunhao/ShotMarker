# Watch Digital Crown 打点设计

日期：2026-06-16

## 背景

当前 Watch 端训练打点依赖一个圆形主按钮：

- 未训练时长按开始训练。
- 训练中双击主按钮记录打点。
- 训练中长按结束训练并同步训练记录。

实际打球时，双击触控区域容易点不到。新增交互需要保留现有方式，并提供更适合运动中的备选输入。

## 目标

- 训练中支持通过 Apple Watch Digital Crown 旋转打点。
- Crown 打点必须有明显阈值，避免轻微误触或系统焦点变化造成误打点。
- Crown 成功打点时播放和双击打点一致的成功震动。
- 保留现有长按开始、双击打点、长按结束流程。
- 不改变训练 payload、同步 outbox、iPhone 导入和集锦生成逻辑。

## 不做

- 不增加设置页或可调阈值。
- 不实现单击打点。
- 不改变训练开始和结束方式。
- 不在训练结束后补录或编辑打点。
- 不修改 iPhone 端训练记录展示和同步状态。

## 推荐方案

在 `WatchTrainingView` 中接入 `digitalCrownRotation`，用一个本地 `Double` 状态记录 Crown 当前值，并在训练中累计与上一次触发基准的差值。差值达到阈值时，调用现有 `viewModel.handleDoubleTap()` 记录打点，成功后播放 `.success` 震动，并把基准值重置到当前 Crown 值。

阈值使用一个固定常量，例如 `8.0`。这个值足够要求一次明确旋转，又不会要求用户大幅转动。后续如果真机反馈过于灵敏或迟钝，再调整常量，不先引入用户设置。

## 交互

### 未训练

- 主按钮仍显示开始训练文案。
- 长按主按钮开始训练。
- 双击不打点。
- Crown 旋转不打点。

### 训练中

- 主按钮显示“可双击或旋钮打点，长按结束”的含义。
- 双击主按钮仍记录一次打点并播放 `.success`。
- Crown 累计旋转达到阈值时记录一次打点并播放 `.success`。
- 记录一次 Crown 打点后立即重置 Crown 基准，避免一次大幅旋转连续产生多个打点。
- 长按主按钮仍结束训练、生成 payload 并触发同步。

## 架构

### ViewModel

`WatchTrainingViewModel` 继续作为唯一训练状态机：

- `handleLongPress(syncService:)` 负责开始或结束训练。
- `handleDoubleTap()` 负责训练中新增一个 marker。

Crown 打点不新增单独的 ViewModel 方法。原因是业务语义与双击完全一致，差别只在 Watch UI 输入设备。复用 `handleDoubleTap()` 能避免出现两套打点逻辑。

### View

`WatchTrainingView` 负责输入设备和 Watch 专属副作用：

- 保存 Crown 当前值和上次触发基准。
- 通过 `.focusable(true)` 让视图接收 Crown 输入。
- 通过 `.digitalCrownRotation(...)` 监听 Crown 变化。
- 在 Crown 变化时判断当前是否训练中、累计差值是否达到阈值。
- 成功打点后播放 `WKInterfaceDevice.current().play(.success)`。

### 同步

同步链路不变。Crown 打点和双击打点都进入同一个 `markers` 数组，训练结束时现有 payload 会自然包含这些打点。

## 数据流

1. 用户长按主按钮开始训练。
2. `WatchTrainingViewModel` 进入 `.training` 并清空旧打点。
3. 用户训练中旋转 Crown。
4. `WatchTrainingView` 累计 Crown 差值。
5. 差值达到阈值时，`WatchTrainingView` 调用 `viewModel.handleDoubleTap()`。
6. ViewModel 写入当前时间到 `markers`。
7. View 播放成功震动并重置 Crown 基准。
8. 用户长按结束训练。
9. 现有同步服务发送包含所有打点的训练记录。

## 错误处理

- 未训练状态下 Crown 变化直接忽略，不播放震动。
- 如果 `handleDoubleTap()` 返回 `false`，不播放震动。
- 同步失败处理保持现状：结束训练路径会把 payload 交给现有 outbox，同步失败不阻塞 UI。
- Crown 输入不可用时，原有双击和长按方式仍可用。

## 测试

### 单元测试

`WatchTrainingViewModel` 已有双击打点测试。由于 Crown 打点复用同一方法，不需要为 ViewModel 增加新的状态机分支测试。

可增加一个小的纯函数或私有辅助类型测试 Crown 阈值逻辑，覆盖：

- 未达到阈值不触发。
- 达到正向阈值触发一次。
- 达到反向阈值触发一次。
- 触发后重置基准，避免连续误触发。

如果实现直接放在 View 私有方法中，至少运行现有 Watch ViewModel 和 Watch scheme 测试，确认状态机和编译未破坏。

### 手动验证

- 打开 Watch app，长按开始训练。
- 双击主按钮，确认打点数加 1 且有震动。
- 明确旋转 Crown，确认打点数加 1 且有震动。
- 轻微旋转 Crown，确认不打点。
- 长按结束训练，确认训练记录仍能同步到手机端。

## 验收标准

- 现有长按和双击流程保持可用。
- 训练中 Crown 达到明显阈值后能记录打点。
- Crown 打点成功时有震动提醒。
- 未训练状态下 Crown 不会产生打点。
- 训练结束 payload 包含双击和 Crown 产生的所有打点。
