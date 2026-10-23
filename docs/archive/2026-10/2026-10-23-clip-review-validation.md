# 片段审核交互验证

- 日期：2026-10-23
- 代码范围：`ea9516d` 加本次片段审核交互改动
- 环境：Xcode 27.1（27A9275）、Apple Swift 6.4、iPhone 17 Pro / iOS 26.5 Simulator
- 本地工作分支：`codex/clip-review-flow`

## 变更范围

用户确认改善保留/排除、切换定位和片段之间的关系，并明确要求移除未使用的精细调整区域。本次实现直接保留/排除后进入紧邻下一段、会话内单级撤销、稳定候选编号、前后导航及缩略图条、同源相邻范围参考和生成合并提示。移除独立精确范围调整面板，保留拖动预览、起止手柄、整体移动、恢复默认与 VoiceOver 步进。

候选编号不随排除或导出编号变化；原始打点编号单独显示。关系提示复用最终规划器的合并结果，包括前序合并范围桥接；排除和跨来源仍中断合并。最后一段保存后回到总览，不循环。

保留、排除和撤销均先完成版本校验与写盘，再发布界面状态。撤销恢复最近一次成功确认前的完整范围、保留状态及确认状态；失败保留入口供重试。撤销记录仅存在于当前会话，任务 schema 保持 1。

## 验证与修复记录

- 新工具链下，原有 `GatedTrainingSessionImporter` actor 无法满足 `@MainActor` 协议，导致基线测试编译失败。测试替身改为 `@MainActor final class`；相关 20 项同步测试在完整测试中通过，未修改生产同步逻辑。
- 新导航与确认测试先观察到预期失败，再验证直接决策、紧邻顺序和稳定编号。
- 首轮完整测试中 405 项单元测试通过，UI 出现两处失败：缩略图目标尚未滚入可视区域；固定撤销条占用空间后播放按钮被遮挡。前者修正测试滚动步骤，后者缩减普通字号时间读数布局并保留大字号网格，最终真实播放器交互通过。
- 代码审查发现同片段重新加载过程中撤销，迟到加载仍可能携带撤销前范围。使用显式可释放的加载门闩和真实 AVPlayer 复现：编辑器已恢复起点 1 秒，播放器却回到旧起点 4.5 秒。恢复播放器重置与加载标识递增后，旧结果被拒绝；恢复后的起点、终点、8 帧胶片、手柄位置和播放推进均通过。
- 最终 UI 附件确认正常字号下播放器、时间轴、播放按钮、固定前后导航和保留/排除/撤销操作可见。使用合成媒体，未将其视为用户真实视频验收。

## 最终结果

```sh
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker \
  -destination 'platform=iOS Simulator,id=098856ED-DC0A-4AC0-BCE7-419ABA6E359F' \
  -derivedDataPath /tmp/ShotMarkerClipReviewQA \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/ShotMarkerClipReviewFinal.xcresult
```

- 退出码 0，`TEST SUCCEEDED`。
- xcresult 汇总：420 项通过、0 项失败、0 项跳过；405 项单元测试和 15 项 UI 测试。
- UI 覆盖：4 项任务流程、5 项审核流程、2 项真实媒体导航/撤销、4 项时间轴拖动。
- 单元测试覆盖：关系计算与规划一致性、工作副本保存、撤销持久化/重载/失败重试、确认与撤销互斥及既有业务回归。
- 本地日志：`/tmp/shotmarker-clip-review-final.log`；结果包为上述路径，临时文件不纳入仓库。
- `git diff --check` 通过；受影响 current 文档均不超过 300 行。

## 范围限制

仅验证本地 Debug Simulator。没有新增 Watch 完整测试、Release/Archive、真机、完整 iPad 或 VoiceOver 人工验收，也没有重新核验分发和外部服务状态。构建仍有既有测试隔离/Sendable 警告及 AppIntents metadata 提示。

慢速播放档位、逐帧按钮和片段衔接预览不在本次实现范围。
