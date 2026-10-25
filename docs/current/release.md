# ShotMarker 发布状态

- 本地工程复核：2026-10-25；外部分发最后核验：2026-09-29，当前审核及上线状态未重新确认。
- 工程版本：1.3（Build 3）。
- Bundle ID：`com.heji.ShotMarker`；Watch Bundle ID：`com.heji.ShotMarker.watchkitapp`。

## 外部分发摘要

2026-09-29 最后核验时，1.3（3）沿用已上传构建、替换截图后重新送审，后台显示 `Waiting for Review`。用户当日确认 TestFlight 的 iPhone/Watch 能打开，并明确跳过后续验收后送审；启动反馈不等于完整功能或升级验收。审核是否已经结束、1.3 是否已经发布及当前商店素材均未在本次任务复核。

2026-09-29 最后核验时，美区公开版本为 1.2；中国区 Lookup 无结果及产品页 404 的原因未核验，不能推断下架。同日核验的商店本地化为 English (U.S.)，素材为 iPhone 5 张、iPad 3 张及 Watch 1 张。这些都是历史基线；详情见[提交记录](../archive/2026-09/2026-09-29-app-store-1-3-submission-plan.md)和[截图记录](../archive/2026-09/2026-09-29-app-store-screenshots.md)。

发布与分发结论在本页维护，真机及构建验证见[质量状态](quality.md)，Analytics / GlitchTip 验证见[观测验证](observability.md)。脱敏后的详细记录保存在本仓库 archive；账号配置、内部管理定位等敏感运维细节才保留私有。

## 最近分发证据（2026-09-29）

- 当次 App Store Connect 重新提交于 16:33，成功提示 `1 Item Submitted`，审核详情含 iOS App 1.3 / 1.3（3），状态 `Waiting for Review`；继续使用原构建，没有新建或上传分发 Archive。
- 用户提供的 Organizer 截图显示候选 Archive 创建于当日 11:18；TestFlight 截图显示 11:31 上传后由 `Processing` 转为 `Complete`，内部测试组中为 `Testing`，到期时间显示 90 天。该 Archive 的精确代码、签名、dSYM 和 Validate 未独立核验；sessions/crashes 横杠不表示零缺陷。
- 用户当日确认 iPhone 与 Watch 能打开，并决定跳过后续完整验收后提交；设备型号和系统版本未记录，不能推断升级或完整功能验收通过。
- 发布选项为手动发布，自动更新选项为立即向所有用户发布；同次侧栏的 1.2 为 `Ready for Distribution`，不据此推断各地区当时或现在可售。
- 已提交 English (U.S.) 的 Description、What's New 和 Review Notes，未新增中文本地化；更新说明披露旧本地数据清理、无自动迁移和升级前保存成片。`Sign-in required` 未选中；原审核联系信息沿用，具体值不存文档。
- 当次 App Privacy 已发布问卷将 Device ID / Product Interaction 归为关联身份的 Analytics，将 Crash Data / Performance Data / Other Diagnostic Data 归为不关联身份的 App Functionality；未修改问卷，未提取最终 Archive 隐私清单。
- 当次发布的隐私政策链接为 [ShotMarker Privacy](https://zhangrh.shop/shotmarker/privacy)；后台存在链接不等于已核验页面正文。
- 截图替换、上传失败恢复和最终素材见[商店截图记录](../archive/2026-09/2026-09-29-app-store-screenshots.md)。更早 1.2 的签名 Archive、匹配 dSYM 与 Organizer Validate 证据见[2026-08-20 发布记录](../archive/2026-08/2026-08-20-release-status.md)，不能替代 1.3 验证。

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
- 真机覆盖限于[质量状态](quality.md)所列的 iPhone 自动回归与视频导出；真实 Photos 授权/保存、完整业务流程、iPad、VoiceOver、Watch 联机升级、Analytics 生产事件、崩溃符号化和告警仍未验收。
- Analytics 生产四字段存储最后验收于 2026-08-16；GlitchTip 生产链路本次未复验。公开页面可访问不证明遥测正常。
- 官网实现、支持页和 how-to 由 `zhangrh.shop` 仓库维护；其公开内容最后核验于 2026-09-29，本次未确认线上状态。旧外部核验详情见[文档整理记录](../archive/2026-10/2026-10-25-documentation-audit.md)。
