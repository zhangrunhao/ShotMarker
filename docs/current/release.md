# ShotMarker 发布状态

- 本地工程与 App Store Connect 复核：2026-10-27。
- 工程版本：1.3.1（Build 4），源码 main `f5c67ad`；商店现售版本在后台显示为 1.3（3）。
- Bundle ID：`com.heji.ShotMarker`；Watch Bundle ID：`com.heji.ShotMarker.watchkitapp`。

## 当前分发事实

- 2026-10-27 App Store Connect 现场显示 1.3 为 `Ready for Distribution`，关联 Build 3。TestFlight 最新既有版本为 1.3，Build 3 为 `Ready to Submit`；此结果不证明所有地区均可售，也不替代真机验收。
- 本次 1.3.1 草稿已建立，为 `Prepare for Submission`；发布说明与审核说明已保存，选择审核通过自动发布、立即向所有用户发布更新。Release Archive 已成功；App Store 分发导出提示 Xcode 无可用账户，尚未上传或送审，不能视为新版已上架。
- 新版沿用 English (U.S.) 本地化和既有截图；现场看到 iPhone 的 5 张继承素材、iPad 3 张、Watch 1 张。未改变商店定价或账户资料。
- `Sign-in required` 未选中；审核说明保留实体 iPhone/配对 Watch 的操作流程，补充分发来源、自用标记、版本、操作步骤及结果的有限 Analytics 披露。
- 2026-10-27 复核 App Privacy：五类数据仍为 Device ID、Product Interaction、Crash Data、Performance Data、Other Diagnostic Data；前两项关联身份、用于 Analytics，后三项为不关联身份的 App Functionality。此次没有更改问卷分类。
- 公开隐私政策为 [ShotMarker Privacy](https://zhangrh.shop/shotmarker/privacy)，本次网站字段说明已部署，并在浏览器核对。网站的发布与接收端验证由[网站发布记录](https://github.com/zhangrunhao/zhangrh.shop/blob/main/docs/archive/2026-10/2026-10-27-analytics-release-plan.md)维护。

本次具体执行见[发布计划](../changes/2026-10-27-analytics-release-plan.md)。构建与真机证据见[质量状态](quality.md)，生产遥测边界见[观测验证](observability.md)。

## 本地工程事实

- iOS 部署下限 26.4，watchOS 下限 26.2；发布与验证范围为 iPhone + Apple Watch。工程保留未完整验收的 iPad destination，不配置 macOS、Mac Catalyst 或 visionOS destination。
- App/Watch Debug、Release 四份产品配置均为 1.3.1（4），配置自动签名，Release 使用 DWARF with dSYM；两个 Info.plist 声明简体中文，主 App `ITSAppUsesNonExemptEncryption=false`。
- iPhone target 通过官方 `sentry-cocoa` 源码产品 `SentrySPM` 链接锁定版本 9.26.0；Watch 不链接。
- 核心使用无需登录或演示账户；视频流程按来源使用 Photos 权限，保存成片申请相册添加权限；Watch 使用 HealthKit workout session。
- 本次仅修改手机侧埋点及 App/Watch 产品版本，不改 Watch 发送逻辑、业务 schema 或数据世代。

## 有效发布决定与用户披露

- 用户于 2026-10-27 明确授权本次埋点增强提交、合并并发布；授权覆盖打包、上传、送审及审核后发布，不再重复询问发布意向。其他版本不据此推断授权，不从历史状态推断已上架。
- 用户于 2026-09-29 明确跳过的验收仅属于那次提交，不扩大本次验证覆盖。
- 当前隐私清单声明五类数据、三类 Required Reason API，属性见[技术架构](architecture.md)；本次 Archive 已提取核验；最终分发产物仍需在导出后核对。
- ShotMarker 不向自建服务器上传训练记录、打点、源视频或成片。系统相册/iCloud 保存与同步由用户设置决定。
- Release iPhone 会发送产品 Analytics 和精简 GlitchTip 错误/崩溃信息。审核说明和隐私披露不得声称“完全不联网”或“所有数据都不离开设备”。
- Analytics 包含项目、事件、随机安装标识、分发来源、自用标记、版本、专用操作标识与受控步骤/原因，不包含训练、媒体、文件名、语音、用户身份或自由文本；有效契约见[产品埋点](analytics.md)。GlitchTip 不配置默认 PII 或用户身份，不上传训练、视频、截图或本地日志文件。
- 低于 1.3 的旧版本首次进入数据世代 1 时，会清空两个 App 自有沙盒的旧业务数据及完整偏好，不迁移；发布说明继续提醒升级前将成片保存到系统相册。系统照片库、已保存成片、HealthKit、沙盒外文件与远端历史不删除。从已完成世代切割的 1.3 升到本次 1.3.1 不再次清理。
- 固定 cutover 在失败重试中复用；旧 Watch 载荷 ACK 后丢弃，成功后启动保留新数据。完整当前行为见[产品事实](product.md#数据与网络)。

## 外部验证边界

- 2026-10-27 main 的 511 单元 + 1 诊断 UI 全部通过；iPhone/Watch 1.3.1（4）Archive 已通过严格签名与 dSYM UUID 检查。Archive 使用 Development 签名，不能代替 App Store 分发重签名与上传验收。
- 真实 Photos 授权/保存、完整真机业务流程、iPad、VoiceOver、Watch 联机升级、分发渠道识别与生产事件、崩溃符号化和告警仍需各自证据。
- 新版服务端已部署；真实 App Store/TestFlight 手机到生产接收端的完整链路尚未完成受控验收。生产页面可访问不证明遥测正常。
- GlitchTip 生产链路本次未复验，既有结果保留原验证日期。
- 历史 1.3 提交材料、原手动发布设置和历史素材记录见[2026-09-29 提交记录](../archive/2026-09/2026-09-29-app-store-1-3-submission-plan.md)；旧记录不覆盖本次已经确认的自动发布设置。
