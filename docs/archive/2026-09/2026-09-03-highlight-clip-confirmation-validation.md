# ShotMarker 片段确认持久化与连续审核验证记录

- 验证日期：2026-09-03
- 实现分支：`codex/highlight-clip-confirmation`
- 实现代码基线：`babebb0`
- 产品版本：1.3（Build 3，未修改）
- 环境：macOS 26.6.2（25G83）、Xcode 26.6（17F113）、Swift 6.3.3；工程 Swift 语言模式为 5

## 自动测试

### 直接受影响范围

执行：

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewIdentityBuilderTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewContentHasherTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewStoreTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewRestorationTests \
  -only-testing:ShotMarkerTests/HighlightClipEditorViewModelTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewPlannerTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewViewModelTests \
  -only-testing:ShotMarkerTests/TrainingVideoLoadingServiceTests \
  -only-testing:ShotMarkerTests/TrainingSessionImporterTests \
  -only-testing:ShotMarkerTests/TrainingSessionJSONTransferServiceTests \
  -only-testing:ShotMarkerTests/TrainingSessionListViewModelTests \
  -only-testing:ShotMarkerTests/PhoneWatchSyncServiceTests \
  -only-testing:ShotMarkerTests/HighlightJobManagerTests \
  -only-testing:ShotMarkerTests/HighlightJobRunnerTests \
  -only-testing:ShotMarkerUITests/HighlightClipConfirmationUITests \
  CODE_SIGNING_ALLOWED=NO
~~~

结果：186 通过，0 失败，0 跳过。结果包：`~/Library/Developer/Xcode/DerivedData/ShotMarker-dxicglurqchmrcghefnuxcxjhfkr/Logs/Test/Test-ShotMarker-2026.09.03_15-51-35-+0800.xcresult`。

### 完整 iPhone

执行：

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
~~~

结果：342 通过，0 失败，0 跳过；其中包括 5 项片段确认 UI 回归与 4 项时间轴真实拖动 UI 回归。结果包：`~/Library/Developer/Xcode/DerivedData/ShotMarker-dxicglurqchmrcghefnuxcxjhfkr/Logs/Test/Test-ShotMarker-2026.09.03_15-56-10-+0800.xcresult`。

### 完整 Watch

计划中的名称目标首次解析时，Xcode 把同一个已配对 Watch 同时列为两个候选，测试尚未启动即以 destination 歧义退出。随后锁定列表中的单一 Apple Watch Series 11（46mm）/ watchOS 26.5 Simulator 目标重试；公开记录省略本机设备标识符：

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarkerWatchApp \
  -destination 'platform=watchOS Simulator,id=<本机设备标识省略>' \
  CODE_SIGNING_ALLOWED=NO
~~~

结果：30 通过，0 失败，0 跳过。结果包：`~/Library/Developer/Xcode/DerivedData/ShotMarker-dxicglurqchmrcghefnuxcxjhfkr/Logs/Test/Test-ShotMarkerWatchApp-2026.09.03_15-59-41-+0800.xcresult`。首次 destination 解析失败不属于产品测试失败。

## Release 构建与静态检查

执行：

~~~bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ShotMarker-ClipConfirmation-Release \
  CODE_SIGNING_ALLOWED=NO
~~~

结果为 `BUILD SUCCEEDED`。`ShotMarker.app`、`ShotMarker.app.dSYM` 和 App 内 `PrivacyInfo.xcprivacy` 均存在；发布二进制不含 `SHOTMARKER_UI_TEST_TIMELINE` 或 `SHOTMARKER_UI_TEST_CLIP_CONFIRMATION` 字符串。

`git diff --check` 与 `plutil -lint ShotMarker/PrivacyInfo.xcprivacy` 通过。对 `reviewSourceIdentity`、`combinationDigest`、`fileSHA256`、`photoLibraryAsset` 的静态扫描只发现内部模型/API、预览或 DEBUG 测试夹具引用；日志、Analytics、用户文本和错误信息没有插入 PhotoKit 标识、内容摘要、训练或打点 UUID、临时路径。本 Change 没有新增 Analytics 事件、GlitchTip metadata 或远端字段。

## Simulator 验收

环境为 iPhone 17 Pro / iOS 26.5 Simulator。真实媒体流程使用两段 640×360、H.264、无音轨、各 40 秒的纯色 MOV；创建时间依次为 `2026-09-03T07:15:00Z` 与 `2026-09-03T07:15:40Z`。训练样本有 4 个打点：首个形成普通卡片，中间两个形成合并卡片，最后一个落在第二段视频；首次规划得到 9 秒、17 秒、13 秒三张默认卡片。

真实媒体持久化与导航驱动通过，结果包为 `~/Library/Developer/Xcode/DerivedData/ShotMarker-dxicglurqchmrcghefnuxcxjhfkr/Logs/Test/Test-ShotMarker-2026.09.03_15-24-30-+0800.xcresult`。该临时验收驱动在执行后移除，不属于产品或已提交测试入口。生成后清理任务的独立流程也通过，结果包为 `~/Library/Developer/Xcode/DerivedData/ShotMarker-dxicglurqchmrcghefnuxcxjhfkr/Logs/Test/Test-ShotMarker-2026.09.03_15-29-18-+0800.xcresult`。

| # | 验收结果 | 证据 |
| --- | --- | --- |
| 1 | 通过 | 首次进入三张卡片均显示“默认”，可直接“确认并生成”。 |
| 2 | 通过 | 调整首卡并确认后显示“已确认 · 保留”，自动打开中间合并卡片。 |
| 3 | 通过 | 中间卡片已确认后重新确认首卡，导航跳过中间卡片并打开最后一张默认卡片。 |
| 4 | 通过 | 确认最后一个后续默认卡片后返回图集，没有从头循环。 |
| 5 | 通过 | 终止并重新启动 App、按原顺序重选两段视频后，确认范围与状态恢复。 |
| 6 | 通过 | 部分确认组合恢复已确认卡片，其余仍为默认，并可直接生成。 |
| 7 | 通过 | 全局前置时长从 9 秒改为 8 秒后，两个已确认卡片保持 8 秒与 17 秒，默认末卡从 13 秒重算为 12 秒。 |
| 8 | 通过 | 反转两段视频顺序不恢复原记录；恢复原顺序后再次命中。 |
| 9 | 通过 | 编辑已确认卡片后状态变为“默认”；放弃改动恢复旧确认值。 |
| 10 | 通过 | 再次确认首卡后存储仍为三项，没有增加重复项，并以新范围替换旧值。 |
| 11 | 通过 | 末卡“排除并确认片段”在重启后恢复为排除，关联打点没有重新生成默认卡片。 |
| 12 | 通过（自动） | Store 写入失败测试证明编辑工作副本、图集、汇总与导航不变，随后可重试。 |
| 13 | 通过 | 已提交 XCUITest 验证“精确范围调整”初始收起、展开后六个 0.5 秒控件可用、重新进入后再次收起。 |
| 14 | 通过（自动） | 删除、JSON/Watch 内容替换、合并与列表 reconciliation 测试覆盖失效记录清理；清理失败不回滚训练保存。 |
| 15 | 通过 | 实际创建后清理 HighlightJob，任务数变为 0，组合记录和三项确认仍存在。 |
| 16 | 通过（自动 UI） | 最大 Dynamic Type XCUITest 验证状态文本可换行且底部确认动作可见、可命中；脏编辑返回提示由独立 UI 用例验证。未执行 VoiceOver。 |

验收结束时只记录非敏感结构证据：Store 为 schema 1、1 条组合记录、2 个有序视频身份和 3 个确认项；普通首卡为调整后的保留项，中间为双打点合并保留项，末卡为排除项。生成任务清理后记录数量不变。未记录组合摘要、来源标识、训练/打点 UUID、临时文件路径或模拟器设备标识符。

## 未执行与已知警告

- 未执行 VoiceOver、真机、正式 Archive、TestFlight、App Store Connect、真实 Release Analytics、GlitchTip 生产符号化或告警验收；这些项目不记为通过。
- Release 构建仍报告既有 `HighlightClipPlaybackController` 观察者闭包 Sendable 警告，以及没有 AppIntents 依赖时跳过 metadata 提取的警告；两者没有导致构建或测试失败。
- 仓库既有 SwiftLint 基线未在本 Change 中重新执行或修复；不得据本记录把它表述为绿色。
