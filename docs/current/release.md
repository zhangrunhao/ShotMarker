# ShotMarker 发布状态

- 最后复核：2026-08-20
- 工程版本：1.2（Build 1）
- Bundle ID：com.heji.ShotMarker
- Watch Bundle ID：com.heji.ShotMarker.watchkitapp

## 当前结论

仓库当前配置为 1.2（Build 1）；签名 Archive 与 Organizer Validate 最近于 2026-08-19 通过。2026-08-20 已通过 App Store Connect 网页复核并更新 iPhone 商店截图，但这不证明当前 TestFlight、审核或 App Store 可用状态。

## 构建与平台

- iOS 部署下限：26.4。
- watchOS 部署下限：26.2。
- 产品发布与验证范围为 iPhone + Apple Watch；主 App 工程仍保留未验收的 iPad destination，不配置 macOS、Mac Catalyst 或 visionOS destination。
- 自动签名已配置。
- Release 使用 DWARF with dSYM。
- iPhone target 从官方 `sentry-cocoa` 以源码产品 `SentrySPM` 链接 Sentry 9.26.0；Watch target 不链接。
- 当前工作区的 Release Simulator 构建于 2026-08-19 通过。
- 2026-08-19 已生成自动签名的正式 iOS Archive 1.2（Build 1）；主 App 与 Watch App 的二进制 UUID 均有匹配 dSYM，Archive 不再嵌入独立 `Sentry.framework`。
- 同日 Xcode Organizer Validate 成功，没有 warning/error 或 `Upload Symbols Failed`；该次验证未执行上传。

## 当前审核事实

- 核心使用不需要登录、账号或演示账户。
- App 需要照片读取/添加权限；Watch 使用 HealthKit workout session。

## 有效用户披露要求

- ShotMarker 不向自建服务器上传训练记录、打点、源视频或生成视频；系统照片库及 iCloud 是否保存或同步视频由用户设置决定。
- Release iPhone 会联网发送产品 Analytics 和 GlitchTip 错误/崩溃信息，因此审核说明和隐私披露不得声称“完全不联网”或“所有数据都不离开设备”。
- Analytics 只发送 project、event、device_id；不发送训练记录、视频、文件名、照片、语音、用户身份或自由文本。完整契约见 [产品埋点](analytics.md)。
- GlitchTip 不配置默认 PII 或用户身份，也不上传训练记录、视频、截图和本地日志文件。

## 外部状态

- 签名 Archive 与 Organizer Validate 的最近验证日期为 2026-08-19；该次验证没有执行上传。完整外部证据由私有台账维护。
- 2026-08-20 已通过 App Store Connect iPhone Media Manager 网页复核：6.9 英寸和 6.5 英寸各配置 4 张当前版本截图，顺序均为训练记录、集锦设置、集锦就绪和集锦完成。
- 截至 2026-08-20，当前 TestFlight、审核和 App Store 可用状态仍未通过网页独立复核。
- ShotMarker Analytics 四字段服务端链路和公开隐私页面最后一次生产验收日期为 2026-08-16；字段与保留边界见 [产品埋点](analytics.md)。
- 截至 2026-08-19，Analytics 和 GlitchTip 的线上状态尚未在 2026-08-16 的生产验收后重新验证。

## 发布前待验收

- 使用正式 Archive 或 TestFlight Build 验证四个 Analytics 事件。
- 触发真机崩溃并确认事件、符号化和 dSYM 对应关系。
- 验证 GlitchTip 告警通知。
- 复核 App Store Connect 隐私问卷与 PrivacyInfo.xcprivacy 一致。
- 使用与当前行为一致的 App Review Note，明确 Watch、HealthKit、照片权限和远端观测边界。
- 重新确认当前 TestFlight、审核与 App Store 可用状态。

正式验收结果应记录验证日期、Build、设备/系统和外部环境，并同步更新 [项目状态](status.md) 与 [质量状态](quality.md)。
