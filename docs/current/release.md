# ShotMarker 发布状态

- 最后复核：2026-08-19
- 当前版本：1.2（Build 1）
- Bundle ID：com.heji.ShotMarker
- Watch Bundle ID：com.heji.ShotMarker.watchkitapp

## 构建与平台

- iOS 部署下限：26.4。
- watchOS 部署下限：26.2。
- 产品发布与验证范围为 iPhone + Apple Watch；主 App 工程仍保留未验收的 iPad destination，不配置 macOS、Mac Catalyst 或 visionOS destination。
- 自动签名已配置。
- Release 使用 DWARF with dSYM。
- iPhone target 从官方 `sentry-cocoa` 以源码产品 `SentrySPM` 链接 Sentry 9.26.0；Watch target 不链接。
- 当前工作区的 Release Simulator 构建于 2026-08-19 通过。
- 2026-08-19 已生成自动签名的正式 iOS Archive 1.2（Build 1）；主 App 与 Watch App 的二进制 UUID 均有匹配 dSYM，Archive 不再嵌入独立 `Sentry.framework`。
- 同日 Xcode Organizer Validate 成功，没有 warning/error 或 `Upload Symbols Failed`。Xcode 为验证提交自动管理的 Build Number 是 2；本地 Archive 元数据仍是 Build 1。

## 审核与用户披露事实

- 核心使用不需要登录、账号或演示账户。
- ShotMarker 不向自建服务器上传训练记录、打点、源视频或生成视频；系统照片库及 iCloud 是否保存或同步视频由用户设置决定。
- App 需要照片读取/添加权限；Watch 使用 HealthKit workout session。
- Release iPhone 会联网发送产品 Analytics 和 GlitchTip 错误/崩溃信息，因此审核说明和隐私披露不得声称“完全不联网”或“所有数据都不离开设备”。
- Analytics 只发送 project、event、device_id；不发送训练记录、视频、文件名、照片、语音、用户身份或自由文本。完整契约见 [产品埋点](analytics.md)。
- GlitchTip 不配置默认 PII 或用户身份，也不上传训练记录、视频、截图和本地日志文件。

## 外部状态

- Xcode Organizer 于 2026-08-19 显示：本任务开始前已有一条 1.2（Build 1）的 `Uploaded to Apple` 归档记录；本任务新建的 1.2（Build 1）归档状态仅为 `Validation succeeded`。
- 本任务没有点击 `Distribute App` 或执行上传，因此没有由本任务新增的 TestFlight Build；TestFlight 当前可安装状态未通过网页独立复核。
- Git 历史表明 1.1.0 曾在 2026-06-16 完成 TestFlight 发布。
- ShotMarker Analytics 四字段服务端链路和公开隐私页面最后一次生产验收日期为 2026-08-16；字段与保留边界见 [产品埋点](analytics.md)。
- 上述结果是带日期的事实；除本次 Organizer Validate 外，当前 App Store、TestFlight、Analytics 和 GlitchTip 线上状态未重新验证。

## 发布前待验收

- 使用正式 Archive 或 TestFlight Build 验证四个 Analytics 事件。
- 触发真机崩溃并确认事件、符号化和 dSYM 对应关系。
- 验证 GlitchTip 告警通知。
- 复核 App Store Connect 隐私问卷与 PrivacyInfo.xcprivacy 一致。
- 使用与当前行为一致的 App Review Note，明确 Watch、HealthKit、照片权限和远端观测边界。
- 重新确认当前 TestFlight 与 App Store 可用状态。

正式验收结果应记录验证日期、Build、设备/系统和外部环境，并同步更新 [项目状态](status.md) 与 [质量状态](quality.md)。
