# 文档审计与整理记录

- 日期：2026-10-25。
- 范围：公开文档入口、六份 current、活跃语音规格中的任务技术引用，以及一处历史归档链接。
- 本记录保存整理依据和从 current 移出的历史证据；下列既有测试、安装与外部结果沿用原记录日期，不表示本次重新执行或核验。
- 本次未访问私有仓库、App Store Connect、TestFlight、Analytics 生产或 GlitchTip 项目。

## 整理依据

1. current 应保留当前实现、有效决定、最近验证基线和边界；状态页、质量页、发布页及入口中重复的开发过程改由历史记录承担。
2. App Store 审核、地区、素材、本地化及线上服务属于变化中的外部事实。未重新核验时保留最后日期，不写成当前状态。
3. 活跃语音规格仍引用旧 `HighlightJobManager` / `HighlightJob`，与正式 App 使用独立 `HighlightTask` 和不可变 `HighlightRenderExecution` 的实现冲突；仅修正技术接点，不改变已确认的语音产品决定。
4. 当前页面支持训练 JSON 导入和全部导出，长按进入多选合并或删除。选中导出仍是 ViewModel API，页面没有该入口。
5. current 链接归档规格仅作为历史设计依据，不能把归档中的旧交互重新视为当前契约。

审计时 69 个 Git 跟踪 Markdown 中发现一处失效本地链接：旧 1.2 提交计划仍指向已移入 archive 的 1.3 计划。本次修正该路径；不对归档正文作全量改写。修改后检查 69 个受 Git 跟踪 Markdown 及本记录，共 70 份文档的本地路径链接，未发现失效目标；六份 current 均少于 300 行。该检查只验证本地路径存在，不验证外部 URL、私有事实或旧测试结果。

## 整理前已有验证结果

以下表格从原质量页移入，保留当时的代码范围、环境和限制。表中“本次”“当日”“当前工作副本”指原验证任务，不指本次文档审计。

| 范围 | 环境 | 日期 | 结果 |
| --- | --- | --- | --- |
| 任务编辑入口与配置精简 | `7f3d18b`；Xcode 27.1；iPhone 17 Pro / iOS 26.5 Simulator | 2026-10-25 | 8 项 UI 通过，0 失败/跳过；含摘要/空白不导航、显式编辑、序数入口移除、状态权限、最大字号及逐段序号模式；Debug 测试构建成功 |
| 控件配色与入口微调 | `8831c5b`；iPhone 17 Pro / iOS 26.5 Simulator | 2026-10-25 | 浅色 2 项、深色 1 项 UI 通过，均 0 失败/跳过；实际浅深色及浅色最大辅助字号截图已核对；未重跑底层单元全套 |
| 编辑控件样式 | `326b200`；iPhone 17 Pro / iOS 26.5 Simulator | 2026-10-25 | 4 项专项 UI 通过；最终宽度调整后浅色/深色各 1 项通过，均 0 失败；检查实际截图，未重跑底层单元全套 |
| 逐段序号布局 | Xcode 27.1；本次变更；iPhone 17 Pro / iOS 26.5 Simulator | 2026-10-25 | 499 通过，0 失败/跳过；475 单元 + 24 UI；包含真实导出像素、操作模式、逐段保存继承和最大辅助字号 |
| 最终代码限定复测 | `38c88c0`；同一 iPhone Simulator，新增序号 UI 使用深色 | 2026-10-25 | 477 通过，0 失败/跳过；全部 475 单元 + 2 新增序号 UI；新增解码隔离警告已消除 |
| 候选配置静态检查 | `10a9f35`；plutil + Python plist 读取与断言 | 2026-09-29 | App/Watch Debug、Release 均为 1.3（3）；五类数据、三类 Required Reason API、zh-Hans 和加密标记核对通过；不等同 XCTest 或构建 |
| 商店截图构建 | Xcode 27.0；当前工作副本；全新 DerivedData；generic iOS Simulator Debug | 2026-09-29 | 构建成功，App/Watch 均为 1.3（3）；没有生成或上传新 Archive；仍有 Sendable、链接器及 AppIntents 提示 |
| 商店截图与演示 | 专用 iPhone 17 Pro Max、iPad Pro 13-inch (M5)、Watch Ultra 3 Simulator；系统 26.5 | 2026-09-29 | 普通 App 入口拍摄 5/3/1 张原生截图；iPhone 调整并确认片段、排除片段、实际生成 38.5 秒合成演示集锦；检查 iPad 审核/编辑/样式及 Watch 起始画面；上传 JPEG/PNG 尺寸和无 Alpha 检查通过，不等同完整功能验收 |
| 取景优先级专项回归 | Xcode 27.1；`3fe813f`；iPhone 17 Pro / iOS 26.5 Simulator | 2026-10-23 | 464 通过，0 失败/跳过；全部 453 单元 + 6 审核 UI + 5 真实媒体 UI；覆盖当前项重开后 8 帧及播放推进 |
| iPhone 完整测试 | Xcode 27.1（27A9275）；`111303d`；iPhone 17 Pro / iOS 26.5 Simulator | 2026-10-23 | 475 通过，0 失败，0 跳过；含 453 项单元测试、22 项 UI 测试；Debug 测试构建成功 |
| 取景真实导出 | AVFoundation / CI；合成 H.264、真实文件与像素解码 | 2026-10-23 | 中心/边缘、旋转/镜像/原生竖屏、多源画布、透明编号、编号位置/切点、完整重叠时长、音频对齐与实际取消清理通过 |
| 取景原生 UI | 真实 Store、AVPlayer、像素采样与 accessibility5 | 2026-10-23 | 2.2× 保存/继承、底部手动恢复、恢复原画面、竖屏/旋转预览和手势暂停通过；最大字号下主要操作与缩略图可滚动到完整可见区域，未载入取景时页面可滚动 |
| iOS 开发签名构建 | Xcode 27.1；main `7adac03`；generic iOS Debug | 2026-10-25 | 构建退出码 0；App 为 1.3（3），codesign 深度严格验证通过；安装与正常前台启动成功，同一进程随后仍在运行；不是分发 Archive |
| 连续审核与媒体隔离 UI | 真实任务 Store/Session、AVPlayer 和帧提取；合成 H.264 文件 | 2026-10-23 | 候选 1 → 2（691.1 秒）→ 跨来源候选 3 → 返回重开通过；切换来源后迟到的旧加载不能覆盖当前范围；定位、8 帧胶片、手柄与播放推进正确 |
| Watch 完整测试 | Apple Watch Series 11 46mm / watchOS 26.5 Simulator；`1975784` | 2026-09-10 | 31 通过，0 失败，0 跳过；2026-10-23 未重跑 Watch 测试，未修改 Watch 代码 |
| Release 构建 | generic iOS Simulator；当日增量构建 | 2026-09-10 | 成功；主 App/Watch 均为 1.3（3），dSYM UUID 对应；全新 DerivedData 构建的最近验证代码为 `1975784` |
| Release 边界 | App/Watch 二进制及 App 包 | 2026-09-10 | 三个 DEBUG 入口、真实媒体测试场景及计数观测均不在产物中；Privacy Manifest 存在，Tracking=false，无后台生成模式 |
| 真实视频导出 | AVFoundation + 真实文件 | 2026-09-10 | 41 秒成片修改后替换为 26 秒，旧文件清理，重载与外部源保护通过 |
| 数据升级与交互 | 专用 iPhone Simulator 原生入口及沙盒核验 | 2026-09-10 | 创建恢复、独立任务、编辑、停止/后台/进程终止、播放/保存、删除和一次性升级通过；具体覆盖方式见验证记录 |
| Git 文本检查 | 本次公开仓库改动的 git diff --check | 2026-10-25 | 通过；私有设备台账独立维护 |
| 分发与启动反馈 | 1.3（Build 3）；用户截图、用户报告及 App Store Connect 页面 | 2026-09-29 | 已 Archive、上传、TestFlight 分发并送审；用户确认 iPhone/Watch 可打开；未复核设备型号、系统和完整主流程 |
| 正式签名 / dSYM / Organizer Validate 详细核验 | 1.2（Build 1） | 2026-08-19 | 最近详细证据；未作为 1.3 产物验收 |


原记录补充：

- 2026-10-25 序号布局验证检查过普通字号浅色/深色的拖动、折叠滑杆和操作按钮，以及浅色最大辅助字号。全部控件展开后页面可滚动至播放按钮，固定决定按钮保持可用；媒体均为合成数据。
- 2026-10-23 原生媒体 UI 覆盖候选 1 → 候选 2（691.1 秒）→ 跨来源候选 3 → 返回重开、8 帧胶片及播放推进；它不证明尚未执行的真机流程。
- 2026-10-25 `362d66e` 的 Debug iphoneos 构建曾报告播放回调 handler 的 Sendable 警告及 AppIntents metadata 提示；真实取消测试曾记录等待 AVFoundation Utility 线程的 QoS 提示，没有据此声称无警告。
- SwiftLint 最近的旧结果为 2026-08-18 的 42 个 violation，其中 5 个 type_body_length error；整理时尚未重新执行，不能作为当前数量。

完整历史命令与结果仍见[任务验证](../2026-09/2026-09-10-editable-highlight-task-validation.md)、[任务入口验证](2026-10-25-task-entry-validation.md)、[控件样式验证](2026-10-25-editor-controls-style-validation.md)、[序号布局验证](2026-10-25-clip-number-layout-validation.md)及[取景优先级验证](2026-10-23-framing-priority-validation.md)。

## 整理前已有外部状态摘要

以下内容从原发布页移入，仅保存 2026-09-29 及各条注明日期的历史，不作为当前外部状态。

- 2026-09-29 [Apple Lookup 美区查询](https://itunes.apple.com/lookup?id=6765859836&country=us) 返回公开版本 1.2，更新时间为 2026-08-29；[美区产品页](https://apps.apple.com/us/app/shotmarker/id6765859836) HTTP 200。Notion 的 1.2.1 发布记录不作为商店版本号证据。
- 同日中国区 Lookup 返回 0 条结果，既有中国区产品链接返回 404；地区可用性及原因尚未在后台核验，不能据此断言下架。
- 2026-09-29 已发布 [官网](https://zhangrh.shop/shotmarker/)的 1.3 产品、操作、升级和隐私说明；四条公开路径及 8 个静态资源均为 HTTP 200，并在 Chrome 核对正文。官网配图仍为已标注的旧版示意。网站实现和发布详情由 `zhangrh.shop` 仓库维护。
- 本次按用户要求先准备新截图，再撤回审核、替换素材，完成 `Add for Review` 和 `Submit for Review`，并查看新的实际审核详情。
- 实际商店本地化仅有 English (U.S.)。本次保存英文更新说明、产品描述和审核 Notes；简体中文文案仍为备用材料。
- 当前商店素材为新拍摄的 iPhone 6.9 英寸 5 张、iPad 13 英寸 3 张和 Watch Ultra 3 1 张；iPhone 与 iPad 的其余尺寸沿用对应新图。素材来源、尺寸及验证边界见 [截图记录](../2026-09/2026-09-29-app-store-screenshots.md)。
- ShotMarker Analytics 四字段服务端链路最后一次生产验收日期为 2026-08-16；字段与保留边界见 [产品埋点](../../current/analytics.md)。
- Analytics 和 GlitchTip 的线上链路本次未复验，不能由公开页面 HTTP 200 推断其工作正常。


## 有效决定的保留边界

任务固定训练快照、执行不可变、停止保留旧成片、确认后紧邻导航、目标保存取景与布局优先、手动打开不继承、数据世代清理、手动发布、隐私披露及后续导航方向继续由 current 维护。个人投篮剪辑优先于语音阶段；整段视频补点管理仍待讨论。文档整理不改变这些决定。
