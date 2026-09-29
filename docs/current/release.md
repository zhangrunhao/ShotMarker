# ShotMarker 发布状态

- 最后复核：2026-09-29（提交准备、静态检查和公开链接）
- 工程版本：1.3（Build 3）
- Bundle ID：com.heji.ShotMarker
- Watch Bundle ID：com.heji.ShotMarker.watchkitapp

## 当前结论

仓库当前 iPhone App 与随包 Watch App 配置为 1.3（Build 3），2026-09-29 静态复核代码为 `10a9f35`。用户已确认开始提交准备；[Notion 1.3](https://app.notion.com/p/3cc387d074aa808bbffae296051b2918) 已备好中英文更新说明、审核备注、升级披露及验收清单。执行入口为 [1.3 提交计划](../changes/2026-09-29-app-store-1-3-submission-plan.md)。

当前本机 Xcode 27.0 许可未接受，测试命令未开始，尚未为 1.3 生成签名 Archive 或上传/送审。Release Simulator 最近成功证据仍为 2026-09-10；签名 Archive 与 Organizer Validate 最近证据为 2026-08-19 的 1.2（Build 1）。Build 3 是否可上传需重新核对 App Store Connect。

## 构建与平台

- iOS 部署下限：26.4。
- watchOS 部署下限：26.2。
- 产品发布与验证范围为 iPhone + Apple Watch；主 App 工程仍保留未验收的 iPad destination，不配置 macOS、Mac Catalyst 或 visionOS destination。
- 自动签名已配置。
- Release 使用 DWARF with dSYM。
- 当前 App/Watch Debug、Release 四个版本配置一致；两个 Info.plist 声明简体中文，主 App `ITSAppUsesNonExemptEncryption=false`，2026-09-29 静态检查通过。
- iPhone target 从官方 `sentry-cocoa` 以源码产品 `SentrySPM` 链接 Sentry 9.26.0；Watch target 不链接。
- 1.3（Build 3）Release Simulator 的当前验证代码为 `da129c1`：2026-09-10 增量构建通过，App/Watch dSYM 对应，DEBUG 入口及真实媒体测试场景不进入产物。全新 DerivedData 构建的最近验证代码为同日 `1975784`。
- 2026-08-19 已生成自动签名的正式 iOS Archive 1.2（Build 1）；主 App 与 Watch App 的二进制 UUID 均有匹配 dSYM，Archive 不再嵌入独立 `Sentry.framework`。
- 同日 Xcode Organizer Validate 成功，没有 warning/error 或 `Upload Symbols Failed`；该次验证未执行上传。
- 尚未为 1.3（Build 3）执行正式签名 Archive、Organizer Validate 或上传。

## 当前审核事实

- 核心使用不需要登录、账号或演示账户。
- App 需要照片读取/添加权限；Watch 使用 HealthKit workout session。

## 有效用户披露要求

- 当前隐私清单包含五类数据与三类 Required Reason API，具体属性见 [技术架构](architecture.md)；2026-09-29 已静态核对，商店问卷和最终 Archive 声明仍需独立核验。
- ShotMarker 不向自建服务器上传训练记录、打点、源视频或生成视频；系统照片库及 iCloud 是否保存或同步视频由用户设置决定。
- Release iPhone 会联网发送产品 Analytics 和 GlitchTip 错误/崩溃信息，因此审核说明和隐私披露不得声称“完全不联网”或“所有数据都不离开设备”。
- Analytics 只发送 project、event、device_id；不发送训练记录、视频、文件名、照片、语音、用户身份或自由文本。完整契约见 [产品埋点](analytics.md)。
- GlitchTip 不配置默认 PII 或用户身份，也不上传训练记录、视频、截图和本地日志文件。

## 本地数据升级影响

- 当前数据世代为 1。缺失或旧 epoch 的 iPhone 与 Watch 首次启动会清空旧训练、旧审核、旧任务、App 内输入/成片、日志、缓存、outbox 和完整偏好设置，不提供迁移。
- iPhone 固定切割时间并在失败重试时复用；切割前结束的旧 Watch 载荷正常 ACK 后丢弃，防止旧训练重新进入本地。
- 系统照片库、已保存到相册的成片、HealthKit、沙盒外导出和远端历史不删除；成功后的后续启动保留新数据。
- 发布说明和升级披露必须明确此本地清理行为。该代码变更尚未执行正式签名 Archive 或分发。

## 外部状态

- 2026-09-29 [Apple Lookup 美区查询](https://itunes.apple.com/lookup?id=6765859836&country=us) 返回公开版本 1.2，更新时间为 2026-08-29；[美区产品页](https://apps.apple.com/us/app/shotmarker/id6765859836) HTTP 200。Notion 的 1.2.1 发布记录不作为商店版本号证据。
- 同日中国区 Lookup 返回 0 条结果，既有中国区产品链接返回 404；地区可用性及原因尚未在后台核验，不能据此断言下架。
- 同日 Support、Privacy、How-to 三条公开路径返回 HTTP 200，但内容为 SPA 入口；正文、隐私披露和 1.3 操作指引尚未完成浏览器验收。
- 本次浏览器连接超时，未获得 App Store Connect 或 TestFlight 当前状态；Notion 的 `Waiting for Review` 是内部分类，不表示实际送审。
- 签名 Archive 与 Organizer Validate 的最近验证日期为 2026-08-19；该次验证没有执行上传。完整外部证据由私有台账维护。
- 2026-08-20 已通过 App Store Connect iPhone Media Manager 网页复核：6.9 英寸和 6.5 英寸各配置 4 张当前版本截图，顺序均为训练记录、集锦设置、集锦就绪和集锦完成。
- ShotMarker Analytics 四字段服务端链路和公开隐私页面最后一次生产验收日期为 2026-08-16；字段与保留边界见 [产品埋点](analytics.md)。
- Analytics 和 GlitchTip 的线上链路本次未复验，不能由公开页面 HTTP 200 推断其工作正常。

## 发布前待验收

- 用户完成 Xcode 许可确认后，在实际可用 Simulator 重新执行 iPhone/Watch 候选测试及 iPad 验证；本次 `xcodebuild test` 退出 69，不能记为通过。
- 更新与 1.3 UI 一致的 iPhone、iPad、Watch 截图；已有 2026-08-20 素材不作为新界面验收。
- 为 1.3（Build 3）生成正式签名 Archive，核验主 App、Watch App、dSYM 和 Organizer Validate，再决定上传候选 Build。
- 使用正式 Archive 或 TestFlight Build 验证四个 Analytics 事件。
- 触发真机崩溃并确认事件、符号化和 dSYM 对应关系。
- 验证 GlitchTip 告警通知。
- 复核 App Store Connect 隐私问卷与 PrivacyInfo.xcprivacy 一致。
- 使用与当前行为一致的 App Review Note，明确 Watch、HealthKit、照片权限和远端观测边界。
- 重新确认当前 TestFlight、审核与 App Store 可用状态。

正式验收结果应记录验证日期、Build、设备/系统和外部环境，并同步更新 [项目状态](status.md) 与 [质量状态](quality.md)。
