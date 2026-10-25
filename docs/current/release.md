# ShotMarker 发布状态

- 本地工程复核：2026-10-25；外部分发最后核验：2026-09-29，当前审核及上线状态未重新确认。
- 工程版本：1.3（Build 3）。
- Bundle ID：`com.heji.ShotMarker`；Watch Bundle ID：`com.heji.ShotMarker.watchkitapp`。

## 外部分发摘要

2026-09-29 最后核验时，1.3（3）沿用已上传构建、替换截图后重新送审，后台显示 `Waiting for Review`。用户当日确认 TestFlight 的 iPhone/Watch 能打开，并明确跳过后续验收后送审；启动反馈不等于完整功能或升级验收。审核是否已经结束、1.3 是否已经发布及当前商店素材均未在本次任务复核。

2026-09-29 最后核验时，美区公开版本为 1.2；中国区 Lookup 无结果及产品页 404 的原因未核验，不能推断下架。同日核验的商店本地化为 English (U.S.)，素材为 iPhone 5 张、iPad 3 张及 Watch 1 张。这些都是历史基线；详情见[提交记录](../archive/2026-09/2026-09-29-app-store-1-3-submission-plan.md)和[截图记录](../archive/2026-09/2026-09-29-app-store-screenshots.md)。

详细 App Store Connect、TestFlight、正式 Archive、真机和生产观测证据的权威来源为独立私有台账 `docs/private.local/shotmarker/`。公开文档仅保留必要摘要，不依赖其可用性解释产品行为与披露要求。

## 本地工程事实

- iOS 部署下限 26.4，watchOS 下限 26.2；发布与验证范围为 iPhone + Apple Watch。工程保留未完整验收的 iPad destination，不配置 macOS、Mac Catalyst 或 visionOS destination。
- App/Watch Debug、Release 四份产品配置均为 1.3（3），配置自动签名，Release 使用 DWARF with dSYM；两个 Info.plist 声明简体中文，主 App `ITSAppUsesNonExemptEncryption=false`。
- iPhone target 通过官方 `sentry-cocoa` 的源码产品 `SentrySPM` 链接锁定版本 9.26.0；Watch 不链接。
- 构建与本地产物最近验证的日期、代码范围和边界见[质量状态](quality.md)。Debug 安装不等于分发 Archive，Simulator dSYM 不证明正式签名及符号文件。
- 核心使用无需登录或演示账户；视频流程按来源使用 Photos 权限，保存成片申请相册添加权限；Watch 使用 HealthKit workout session。

## 有效发布决定与用户披露

- 最终发布保留用户手动操作；不从历史审核状态推断可发布或已发布。
- 用户于 2026-09-29 明确跳过的后续验收不再作为那次提交的未完成前置条件；其他版本及变更的验证范围仍按实际证据记录。
- 当前隐私清单声明五类数据、三类 Required Reason API，属性见[技术架构](architecture.md)。商店披露最后核验于 2026-09-29；正式 Archive 内的清单仍未独立提取核验。
- ShotMarker 不向自建服务器上传训练记录、打点、源视频或成片。系统相册/iCloud 保存与同步由用户设置决定。
- Release iPhone 会发送产品 Analytics 和精简 GlitchTip 错误/崩溃信息。审核说明和隐私披露不得声称“完全不联网”或“所有数据都不离开设备”。
- Analytics 请求仅包含 `project`、`event`、`device_id`，不包含训练、媒体、文件名、语音、用户身份或自由文本；有效契约见[产品埋点](analytics.md)。GlitchTip 不配置默认 PII 或用户身份，不上传训练、视频、截图或本地日志文件。
- 发布说明和升级披露必须说明数据世代 1 首次启动清空两个 App 自有沙盒中的旧业务数据及完整偏好，不迁移。系统照片库、已保存成片、HealthKit、沙盒外文件与远端历史不删除。
- 固定 cutover 在失败重试中复用；旧 Watch 载荷 ACK 后丢弃，成功后启动保留新数据。完整当前行为见[产品事实](product.md#数据与网络)。

## 外部验证边界

- 最后核验于 2026-09-29 的 1.3 Archive 已获 Apple 接收，但该次签名、dSYM UUID、Organizer Validate 日志及源码精确映射未独立复核。
- 完整真机剪辑、iPad、VoiceOver、Watch 联机升级、Analytics 生产事件、崩溃符号化和告警仍无新增验收证据，见[质量状态](quality.md)。
- Analytics 生产四字段存储最后验收于 2026-08-16；GlitchTip 生产链路本次未复验。公开页面可访问不证明遥测正常。
- 官网实现、支持页和 how-to 由 `zhangrh.shop` 仓库维护；其公开内容最后核验于 2026-09-29，本次未确认线上状态。旧外部核验详情见[文档整理记录](../archive/2026-10/2026-10-25-documentation-audit.md)。
