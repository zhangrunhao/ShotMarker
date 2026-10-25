# 文档与代码维护验证

- 日期：2026-10-25。
- 起始基线：`3c06c26`；最终代码：`2fa8049`。
- 用户要求：检查文档与代码、合理优化、修改验证并提交。工作区开始时无未提交改动；本轮使用 `codex/maintenance-audit` 分支。
- 本轮没有访问或修改私有台账，也没有重新核验商店、真机、Analytics 或 GlitchTip 生产状态。

## 审计与处理

1. 播放器无效加载未失效旧来源、同来源定位完成乱序、旧观察回调与排队回首干扰新来源：统一来源和定位代次，发起及发布两端校验。独立复核发现的“边界回首未完成即重播”增加门控测试，显式保留待定位目标并在实际定位完成后播放。
2. Watch 授权迟到可启动已结束训练，前一训练保存期间的新开始会被忽略：按训练请求身份管理授权、运行与结束状态；具体 handle 持有自己的 HealthKit session/builder，保存完成后仅启动仍在等待的新训练。
3. 日志 14 天 / 30 MB 只在导出时清理，旧日志目录不受数据世代清理：正常 append 立即执行保留规则，默认根目录归入 ShotMarker/Logs；重置及默认日志实例清理 legacy Logs，自定义目录保持显式边界，epoch 仍为 1。
4. 启动加载期间丢失 background 事件：Bootstrap 保留最近 active/background 状态并在服务启动前应用；inactive 不覆盖，失败重试继续遵守该状态。
5. 配置页抽出纯展示视频卡片，删除无效旧状态；播放器平台适配与状态协调分文件，启动入口、加载协调及服务装配分文件。保留确有兼容契约回归用途的旧 Job 与组合审核类型，不改变产品流程、schema、视频导出算法或隐私契约。
6. current 和 README 精简重复历史，旧外部事实明确最后日期；补训练管理事实，修复活跃语音规格的旧任务集成引用和一处归档坏链接。原有效产品决定全部保留，历史材料见[文档整理记录](2026-10-25-documentation-audit.md)。

## 自动验证

工具链为 Xcode 27.1（27A9275）、Swift 6.4；工程仍使用 Swift 5 语言模式。

| 检查 | 环境与结果 | 证据 |
| --- | --- | --- |
| 修改前 iPhone 单元基线 | 475 项通过，0 失败/跳过 | baseline.xcresult |
| 播放/日志/启动 RED | 33 项中 10 项按预期失败；其余 23 项通过 | lifecycle-red.xcresult |
| 排队播放与旧观察者 RED | 3 项按预期失败 | playback-callback-red.xcresult |
| Watch 生命周期 RED | 9 项中 7 项按预期失败；拒绝/不可用保护 2 项通过 | watch-red.xcresult |
| 独立审查补充重播 RED | 真实播放器位置仍为 7 秒，未定位回 4 秒，1 项按预期失败 | replay-red.xcresult |
| 最终 iPhone 完整测试 | iPhone 17 Pro / iOS 26.5；491 单元 + 24 UI 共 515 项通过，0 失败/跳过 | iphone-full2.xcresult |
| 最终 Watch 完整测试 | Apple Watch Series 11 (46mm) / watchOS 26.5；40 项通过，0 失败/跳过 | watch-full2.xcresult |
| 全新 Release 构建 | generic iOS Simulator；独立 DerivedData；退出 0 | release.log |
| Release 产物边界 | App/Watch 均为 1.3（3），两种 Simulator 架构的 dSYM UUID 各自匹配；无 DEBUG 测试入口或 harness；Privacy Manifest 的 Tracking=false、五类数据、三类 Required Reason API 核对通过 | 本轮产物脚本断言 |
| 生产源码 SwiftLint | 153 项（124 warning / 29 error）降至 149 项（120 warning / 29 error）；没有文件规则计数增加，未放宽规则 | swiftlint-before.json / swiftlint-final.json |
| 文本与文档治理 | 72 份公开 Markdown 的本地路径无失效目标；current 均不超过 300 行，归档月份与扁平结构正确；文本检查通过 | git diff --check 与本地路径检查 |

所有结果包、原始日志和静态检查 JSON 位于本机 `/tmp/shotmarker-audit-20261025/`，临时结果包不进入 Git。Release 产物位于 `/tmp/ShotMarkerMaintenanceRelease/Build/Products/`；它是未签名的 Simulator 构建，不是分发 Archive。

## 复现入口

为避免把设备标识写入公开仓库，下列 destination 用名称表达。测试实际运行于同名、同版本 Simulator；`test-without-building` 使用本轮最终源码已完成的 Debug 测试构建。

```sh
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ShotMarkerFramingQA \
  -parallel-testing-enabled NO -collect-test-diagnostics never

xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' \
  -derivedDataPath /tmp/ShotMarkerMaintenanceWatch \
  -parallel-testing-enabled NO -collect-test-diagnostics never

xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarker \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ShotMarkerMaintenanceRelease CODE_SIGNING_ALLOWED=NO

swiftlint lint --quiet --reporter json ShotMarker Shared ShotMarkerWatchApp
git diff --check
```

## 修正过程与验证边界

- 第一轮日志 RED 构建撞到组件拆分中间态，未作为有效失败证据；随后以完整源码快照重新执行行为 RED，确认可重复的业务失败。
- Watch 首次 GREEN 构建使用了错误的异步参数标签，未计为通过；核对本机 SDK 后改为 `endCollection(at:)`，最终完整 40 项通过。
- iPhone 首轮完整验证遇到 Simulator `Busy / Application failed preflight checks`，主动中断，未计为通过。重启测试 Simulator、确认系统启动完成及应用可启动后，用同一最终 Debug 构建重新执行完整测试。
- 初始基线的 475 项断言通过后，系统诊断采集子进程挂起；停止该诊断子进程后 xcodebuild 正常退出 0，结果包为 Passed。后续使用 `-collect-test-diagnostics never`，保留正常 XCTest 结果与日志。
- 独立审查覆盖全部代码与文档改动；发现的重播 P2 已用真实定位门控回归修复并复核，最终无未处理的确认问题。
- 查看本轮 UI 测试生成的普通与最大辅助字号任务卡片截图，文字和操作无重叠或截断；未扩展为全页面视觉验收。
- 本轮新增 16 项 iPhone 与 9 项 Watch 回归。HealthKit 授权和保存采用可控平台适配，不代表已完成真机授权、抬腕、后台保活或健康数据保存验收。
- Release 编译仅记录 AppIntents metadata 提示；自动测试仍可出现系统媒体/QoS 和 Xcode 工具提示。测试辅助代码既有并发警告、149 项 SwiftLint 违规继续如实保留，不宣称仓库静态检查全绿。
- 未执行正式 Archive、设备签名安装、完整真机剪辑、iPad 全功能、VoiceOver 人工朗读、HDR/广色域或线上观测验收。
