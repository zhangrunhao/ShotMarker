# ShotMarker 技术架构

- 最后复核：2026-08-19
- 代码基线：main / 42c249a

## 当前结论

ShotMarker 当前由 iPhone App、Apple Watch App、两组测试 target 和共享同步载荷组成；训练、同步、集锦、日志与远端观测均按下述本地优先边界实现。

## 运行单元

- ShotMarker：SwiftUI 主 App；已验证产品范围为 iPhone，工程仍保留未验收的 iPad destination。
- ShotMarkerWatchApp：Apple Watch App，SwiftUI、HealthKit、WatchConnectivity。
- ShotMarkerTests：iPhone 单元与服务测试。
- ShotMarkerWatchAppTests：Watch 同步、outbox 和运行时测试。
- Shared：手机与手表共用的训练同步载荷。

工程使用 Xcode 26.6 和 Swift 6.3.3 工具链；工程语言模式为 Swift 5。部署下限为 iOS 26.4 和 watchOS 26.2；主 App 当前只声明 iOS/iOS Simulator 平台，不配置 macOS、Mac Catalyst 或 visionOS destination。

## 数据模型与持久化

- TrainingSession 保存训练 ID、开始时间、结束时间和时间打点。
- ShotMarkerEvent 当前只保存 ID 与 markedAt，不包含语音事件或技术统计字段。
- 训练记录以 JSON 保存在 Application Support/ShotMarker/training-sessions.json。
- 集锦任务以 JSON 保存在 Application Support/ShotMarker/highlight-jobs.json。
- 集锦任务输入和输出文件保存在 App 沙盒中的稳定相对路径。
- 剪辑设置、安装标识等小型配置使用 UserDefaults。

## Watch 同步

~~~text
WatchTrainingSyncOutbox
→ WCSession transferUserInfo
→ PhoneWatchSyncService
→ TrainingSessionImporter
→ ACK
→ Watch 删除 outbox 条目
~~~

- iPhone 导入按训练 ID 幂等处理。
- iPhone 成功导入后、发送 ACK 前记录同步成功事件。
- Watch 在未激活、发送失败或等待 ACK 时保留 outbox 数据，并定期重试。
- iPhone 保存 WatchConnectivity 诊断快照；Watch 没有独立日志导出。

## 视频与集锦任务

- 视频选择和元数据校验由 Photos/AVFoundation 服务完成。
- iCloud 视频先准备为可读本地资源，再进入规划和导出。
- VideoClipSegmentPlanner 将绝对打点映射到视频片段并合并相邻片段。
- VideoClipEditingService 使用 AVMutableComposition 组合视频和可用音轨，输出 MOV。
- HighlightJobManager 管理持久任务；HighlightJobRunner 串行执行。
- App 启动时把遗留的 queued、running 或 saving 任务标为 interrupted。
- 生成完成只产生本地可播放文件；VideoClipPhotoLibrarySaver 由用户手动触发。

## 日志与诊断

- AppLogger 把结构化 JSONL 日志写入本地，按日期轮转。
- 日志保留 14 天，总量上限 30 MB。
- 日志导出包含 manifest、设备/App 信息、本地日志和 iPhone 侧同步诊断。
- Watch 日志字段当前明确标记为未包含。

## 远端观测

- iPhone target 在 Debug 和 Release 中通过 Sentry 9.26.0 对接 GlitchTip；SwiftPM 从官方 `sentry-cocoa` 解析源码产品 `SentrySPM`，业务适配层导入 `SentrySwift`。
- `SentrySPM` 只链接到 ShotMarker 主 target，Watch target 不依赖 Sentry。
- AppLogger.error 同时写入本地并发送精简错误事件；其他日志级别只保存在本地。
- GlitchTip 不启用性能追踪、Profiling、Session Replay 或自动 Session Tracking。
- Analytics 只在 Release iPhone 启用；事件语义、请求、存储和隐私边界见 [产品埋点](analytics.md)。

## 有效隐私边界

- PrivacyInfo.xcprivacy 声明 Device ID、Product Interaction、UserDefaults 和文件时间戳用途。
- Tracking 为 false。
- GlitchTip 不配置用户身份，不上传训练记录、视频、截图或本地日志文件。
- 客户端 DSN 可以随 App 分发；服务端管理令牌不得进入工程或 Git。
