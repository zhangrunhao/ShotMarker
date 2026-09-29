# ShotMarker 发布状态

- 最后复核：2026-09-29（新截图替换及重新送审）
- 工程版本：1.3（Build 3）
- Bundle ID：com.heji.ShotMarker
- Watch Bundle ID：com.heji.ShotMarker.watchkitapp

## 当前结论

1.3（Build 3）已替换当前界面截图并重新提交 Apple 审核，2026-09-29 当次后台状态为 `Waiting for Review`。继续使用原有构建，没有重新打包上传。发布方式为审核通过后手动发布，尚未上架 1.3。[Notion 1.3](https://app.notion.com/p/3cc387d074aa808bbffae296051b2918) 保存提交文案；详细分发证据由独立私有台账 `docs/private.local/shotmarker/current/release.md` 维护。

用户确认 TestFlight 的 iPhone 和 Watch 均能正常打开，并明确决定跳过后续验收、直接送审。启动反馈不等于完整功能、升级或线上观测验收通过。本次截图所需的 Debug Simulator 全新构建和演示流程通过；未重跑自动测试，Release Simulator 最近成功证据仍为 2026-09-10。

准备阶段静态复核基线为 `10a9f35`；截图构建包含后续 Xcode 配置调整，最终 Archive 与该基线的精确映射未独立核验。已完成的提交计划见 [归档](../archive/2026-09/2026-09-29-app-store-1-3-submission-plan.md)。

## 构建与平台

- iOS 部署下限：26.4。
- watchOS 部署下限：26.2。
- 产品发布与验证范围为 iPhone + Apple Watch；主 App 工程仍保留未验收的 iPad destination，不配置 macOS、Mac Catalyst 或 visionOS destination。
- 自动签名已配置。
- Release 使用 DWARF with dSYM。
- 当前 App/Watch Debug、Release 四个版本配置一致；两个 Info.plist 声明简体中文，主 App `ITSAppUsesNonExemptEncryption=false`，2026-09-29 静态检查通过。
- iPhone target 从官方 `sentry-cocoa` 以源码产品 `SentrySPM` 链接 Sentry 9.26.0；Watch target 不链接。
- 1.3（Build 3）Release Simulator 的当前验证代码为 `da129c1`：2026-09-10 增量构建通过，App/Watch dSYM 对应，DEBUG 入口及真实媒体测试场景不进入产物。全新 DerivedData 构建的最近验证代码为同日 `1975784`。
- 用户已完成 1.3（Build 3）Archive 和上传；Apple 已接收并允许送审。该次 Organizer Validate 日志、签名与 dSYM UUID 未独立复核，不沿用旧版本的详细验证结论。

## 当前审核事实

- 核心使用不需要登录、账号或演示账户。
- App 需要照片读取/添加权限；Watch 使用 HealthKit workout session。

## 有效用户披露要求

- 当前隐私清单包含五类数据与三类 Required Reason API，具体属性见 [技术架构](architecture.md)；2026-09-29 已静态核对，并在送审时核对商店已发布的五类数据及用途、关联属性；最终 Archive 内的清单未独立提取。
- ShotMarker 不向自建服务器上传训练记录、打点、源视频或生成视频；系统照片库及 iCloud 是否保存或同步视频由用户设置决定。
- Release iPhone 会联网发送产品 Analytics 和 GlitchTip 错误/崩溃信息，因此审核说明和隐私披露不得声称“完全不联网”或“所有数据都不离开设备”。
- Analytics 只发送 project、event、device_id；不发送训练记录、视频、文件名、照片、语音、用户身份或自由文本。完整契约见 [产品埋点](analytics.md)。
- GlitchTip 不配置默认 PII 或用户身份，也不上传训练记录、视频、截图和本地日志文件。

## 本地数据升级影响

- 当前数据世代为 1。缺失或旧 epoch 的 iPhone 与 Watch 首次启动会清空旧训练、旧审核、旧任务、App 内输入/成片、日志、缓存、outbox 和完整偏好设置，不提供迁移。
- iPhone 固定切割时间并在失败重试时复用；切割前结束的旧 Watch 载荷正常 ACK 后丢弃，防止旧训练重新进入本地。
- 系统照片库、已保存到相册的成片、HealthKit、沙盒外导出和远端历史不删除；成功后的后续启动保留新数据。
- 发布说明和升级披露必须明确此本地清理行为。本次已在实际提交的英文更新说明前部和审核备注中披露。

## 外部状态

- 2026-09-29 [Apple Lookup 美区查询](https://itunes.apple.com/lookup?id=6765859836&country=us) 返回公开版本 1.2，更新时间为 2026-08-29；[美区产品页](https://apps.apple.com/us/app/shotmarker/id6765859836) HTTP 200。Notion 的 1.2.1 发布记录不作为商店版本号证据。
- 同日中国区 Lookup 返回 0 条结果，既有中国区产品链接返回 404；地区可用性及原因尚未在后台核验，不能据此断言下架。
- 2026-09-29 已发布 [官网](https://zhangrh.shop/shotmarker/)的 1.3 产品、操作、升级和隐私说明；四条公开路径及 8 个静态资源均为 HTTP 200，并在 Chrome 核对正文。官网配图仍为已标注的旧版示意。网站实现和发布详情由 `zhangrh.shop` 仓库维护。
- 本次按用户要求先准备新截图，再撤回审核、替换素材，完成 `Add for Review` 和 `Submit for Review`，并查看新的实际审核详情。
- 实际商店本地化仅有 English (U.S.)。本次保存英文更新说明、产品描述和审核 Notes；简体中文文案仍为备用材料。
- 当前商店素材为新拍摄的 iPhone 6.9 英寸 5 张、iPad 13 英寸 3 张和 Watch Ultra 3 1 张；iPhone 与 iPad 的其余尺寸沿用对应新图。素材来源、尺寸及验证边界见 [截图记录](../archive/2026-09/2026-09-29-app-store-screenshots.md)。
- ShotMarker Analytics 四字段服务端链路最后一次生产验收日期为 2026-08-16；字段与保留边界见 [产品埋点](analytics.md)。
- Analytics 和 GlitchTip 的线上链路本次未复验，不能由公开页面 HTTP 200 推断其工作正常。

## 后续与验证边界

- 等待 Apple 审核结果；批准、拒绝及最终手动发布各自以届时后台为准。
- 用户已明确跳过本轮后续验收，不再将其作为本次提交的未完成前置条件。
- 当前候选的完整真机回归、iPad、VoiceOver、升级流程、Analytics 生产事件、崩溃符号化及告警仍无新增通过证据，详见 [质量状态](quality.md)。
- 最终 Archive 签名及 dSYM 未在本次独立复核。
