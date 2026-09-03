# ShotMarker 技术架构

- 最后复核：2026-09-03
- 验证代码基线：`codex/highlight-clip-confirmation` / `babebb0`

## 当前结论

ShotMarker 当前由 iPhone App、Apple Watch App、三组测试 target 和共享同步载荷组成；训练、同步、可审核且带样式序数的集锦、日志与远端观测均按下述本地优先边界实现。可编辑任务与独立生成执行的替代架构已经确认但尚未进入代码，当前实现差距保留在下述独立章节。

## 已确认但未实现的架构

- `HighlightTask` 将成为长期可编辑聚合，拥有不可变训练快照、任务视频、设置、审核片段和当前成片；`HighlightRenderExecution` 是从指定任务 revision 建立的单次不可变生成快照。
- 点击“下一步：审核片段”时原子创建任务。任务不保留指向训练 Store 的外键；训练后续修改或删除不能影响任务，同样输入重复发起产生不同 UUID。
- 组合级 `HighlightClipReviewStore` 将退出业务链路，所有默认和确认片段进入任务文档；审核仍直接读取原 AVAsset，不产生逐片段视频文件，离页统一释放运行时媒体资源。
- 文件导入视频由任务目录持有，相册视频只保存稳定引用。任务配置通过 revision 和 actor Store 提交；生成执行持久化后进入全 App 串行队列。
- 排队和生成期间只允许停止。进入后台立即停止全部执行；进程异常退出后下次启动统一规范为 stopped，不设置后台生成或自动恢复。
- 新数据世代首次启动会清空 iPhone 与 Watch 的全部 ShotMarker 本地状态且不迁移；固定 `dataCutoverAt` 门槛负责 ACK 并丢弃切割前 Watch outbox 载荷。
- 当前代码仍使用 `HighlightJob`、组合级确认和 `interrupted` 启动恢复，因此与上述决定存在明确实施差距。完整数据契约、事务和验证要求见 [可编辑集锦任务规格](../changes/2026-09-03-editable-highlight-task-spec.md)。

## 运行单元

- ShotMarker：SwiftUI 主 App；已验证产品范围为 iPhone，工程仍保留未验收的 iPad destination。
- ShotMarkerWatchApp：Apple Watch App，SwiftUI、HealthKit、WatchConnectivity。
- ShotMarkerTests：iPhone 单元与服务测试。
- ShotMarkerUITests：iPhone Simulator UI 测试；通过两个 DEBUG 专用环境入口验证时间轴四类真实拖动，以及确认状态、编辑事务、连续导航、折叠控件和最大字号；Release 不包含这些入口。
- ShotMarkerWatchAppTests：Watch 同步、outbox 和运行时测试。
- Shared：手机与手表共用的训练同步载荷。

工程使用 Xcode 26.6 和 Swift 6.3.3 工具链；工程语言模式为 Swift 5。部署下限为 iOS 26.4 和 watchOS 26.2；主 App 当前只声明 iOS/iOS Simulator 平台，不配置 macOS、Mac Catalyst 或 visionOS destination。

## 数据模型与持久化

- TrainingSession 保存训练 ID、开始时间、结束时间和时间打点。
- ShotMarkerEvent 当前只保存 ID 与 markedAt，不包含语音事件或技术统计字段。
- 训练记录以 JSON 保存在 Application Support/ShotMarker/training-sessions.json。
- 集锦任务以 JSON 保存在 Application Support/ShotMarker/highlight-jobs.json。
- 逐片段确认以 schema 1 JSON 保存在 Application Support/ShotMarker/highlight-clip-reviews.json；它不进入 TrainingSession、HighlightJob、Watch 载荷或 UserDefaults。
- 集锦任务输入和输出文件保存在 App 沙盒中的稳定相对路径。
- ClipSettings 保存片段前后时长和 MarkerLabelStyle；旧版缺少样式的设置及任务解码时补入默认样式，已有时长保持不变。
- 剪辑设置、安装标识等小型配置使用 UserDefaults；HighlightJob 内嵌创建任务时规范化后的完整 ClipSettings 快照。
- 新建 HighlightJob 同时保存 `clipPlanVersion = 1` 和已验证的 `ConfirmedHighlightSegment` 数组；编辑工作副本不持久化，逐片段确认由独立 Store 保存。
- 审核组合包含完整训练身份与严格有序的视频身份。训练日期和打点日期规范化为 Unix epoch 毫秒，视频开始时间为毫秒、时长为 timescale 600 tick；全局前后时长与序数样式不进入组合身份。
- PhotoKit 来源使用带类型的资源标识，文件导入来源在后台以 1 MiB 分块计算完整 SHA-256；运行时视频 ID 与稳定审核身份相互独立。
- `FileHighlightClipReviewStore` 是 actor，串行执行读取、upsert、训练删除和 reconciliation；写入使用目标目录临时文件和原子替换。损坏文件会先改名保留再创建空 schema 1 文档，高于 schema 1 的文档只读保护且不会被覆盖。

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

- 视频选择和元数据校验由 Photos/AVFoundation 服务完成。照片库预览先请求禁止网络访问的完整画幅静态图；PhotoKit 没有返回海报时，再从本地可用视频资源提取首帧，不触发 iCloud 下载。
- iCloud 视频先准备为可读本地资源，再进入规划和导出。
- 集锦审核与导出链路为：

~~~text
训练内容 + 严格有序的已选视频
→ HighlightClipReviewIdentityBuilder 完整组合键
→ HighlightClipReviewStore 读取确认项
→ HighlightClipReviewPlanner 恢复确认项并重建其余默认范围
→ HighlightClipReviewViewModel / HighlightClipEditorViewModel
→ ConfirmedHighlightSegment[] / clipPlanVersion 1
→ HighlightJobManager
→ HighlightJobRunner 版本路由
→ VideoClipEditingService
~~~

- VideoClipSegmentPlanner 将绝对打点映射到默认视频片段并保留全部关联打点；HighlightClipReviewPlanner 统一 0.1 秒范围、重新编号、汇总、最终相邻合并和快照验证。
- HighlightClipReviewMediaProvider 提供可取消的中点缩略图与局部胶片帧，并使用有上限的内存缓存；HighlightClipPlaybackController 保证单一活跃播放器、范围结束回起点和观察者清理。
- 恢复规划先验证视频、关联打点、范围和重复占用；有效确认项占用其打点，剩余打点按当前全局时长重新生成默认卡片，并按原编号稳定交错。视频顺序变化形成新组合；只改前后时长会保留确认项并重建默认项。
- 编辑器持有独立工作副本；审核 ViewModel 先验证保留来源和 0.1 秒范围，再原子写入 Store，成功后才发布卡片、汇总、缩略图和导航。写入期间禁止继续编辑或放弃，失败不改变图集。
- 确认成功只搜索当前卡片之后的第一个默认卡片；默认卡片不构成提交门槛。序数样式变化不使审核输入失效。
- MarkerLabelLayout 统一预览与导出的 aspect-fit 画面、归一化中心点、按标签尺寸限制边界，以及 SwiftUI 左上原点到 Core Image 左下原点的转换。
- TrainingSessionHighlightView 以初值为 false 的页面级状态控制片段序数 DisclosureGroup；展开状态不持久化，设置内容继续绑定从 ClipSettingsStore 加载并自动保存的 MarkerLabelStyle。
- VideoClipEditingService 使用 AVMutableComposition 组合视频和可用音轨，按显式传入的 MarkerLabelStyle 绘制序数并输出 MOV；导出服务不读取 ClipSettingsStore。
- HighlightJobManager 只复制最终片段引用的视频并管理持久任务；HighlightJobRunner 对版本 1 直接使用精确片段，对两个新字段均缺失的旧 1.2/1.3 任务使用旧规划，其他不一致或未知版本不回退。
- HighlightJobRunner 串行执行，并把任务快照中的范围与样式显式传给导出服务。
- App 启动时把遗留的 queued、running 或 saving 任务标为 interrupted。
- 生成完成只产生本地可播放文件；VideoClipPhotoLibrarySaver 由用户手动触发。
- 训练删除、内容已变化的 JSON/Watch 替换和合并在训练保存成功后清理旧确认记录；列表加载按完整训练身份 reconciliation。清理失败只记录封闭错误类别和数量、不回滚训练事实，并可在下次加载重试。HighlightJob 的取消、失败、完成或删除不清理确认记录。

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
- 片段序数缩略图和样式不上传，也不产生新的 Analytics 事件。
- 审核缩略图、胶片帧、范围与原始打点引用不上传；稳定来源身份、组合摘要、训练/打点 UUID 和临时路径也不进入日志、Analytics、错误文案或界面。审核与清理日志只记录计数、总时长、是否合并和封闭错误类别。
- GlitchTip 不配置用户身份，不上传训练记录、视频、截图或本地日志文件。
- 客户端 DSN 可以随 App 分发；服务端管理令牌不得进入工程或 Git。
