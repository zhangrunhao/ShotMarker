# ShotMarker 技术架构

- 最后复核：2026-10-25（本地源码：启动/场景生命周期、Watch runtime、日志目录与保留清理、配置及播放组件；验证结果另按日期和代码范围记录）
- 测试和构建结果见 [质量状态](quality.md)；外部集成与隐私声明沿用各段注明的核验日期。

## 运行单元

- ShotMarker：SwiftUI iPhone App；工程保留未验收的 iPad destination。
- ShotMarkerWatchApp：SwiftUI、HealthKit、WatchConnectivity。
- ShotMarkerTests：iPhone 单元、文件事务、媒体和服务测试。
- ShotMarkerUITests：时间轴拖动、片段确认、真实媒体连续导航及任务权限/配置/最大字号测试；三个 DEBUG 专用入口不进入 Release。
- ShotMarkerWatchAppTests：同步、outbox、运行时和数据世代重置测试。
- Shared：同步载荷及 `AppDataResetCoordinator`。

2026-10-25 本机工具链复核为 Xcode 27.1（27A9275）、Swift 6.4。工程语言模式为 Swift 5；iOS 下限 26.4，watchOS 下限 26.2。主 App 不配置 macOS、Mac Catalyst 或 visionOS destination。

## 启动和数据世代

`ShotMarkerApp` 提供场景入口；独立的 `ShotMarkerBootstrap.swift` 执行数据世代事务、加载及生命周期协调，`ShotMarkerServices.swift` 组装业务、日志、Analytics、GlitchTip 和 WatchConnectivity 服务。只有重置成功后才构造服务，失败只显示阻塞重试页。Watch 也在重置成功后才构造同步服务。

Bootstrap 在异步加载期间保存最近的 active/background 状态，inactive 不覆盖该状态。加载完成后先将状态应用到服务，再启动服务并发布到界面；加载期间进入后台不能被漏掉，后台状态下不启动生成调度。

- 当前 epoch 为 1；缺失或低版本触发清理，不迁移旧数据。
- iPhone 先将仅含目标 epoch 与固定 `dataCutoverAt` 的 journal 原子写入 Application Support/ShotMarkerReset/reset-state.json，再清理 ShotMarker 业务目录、旧 Application Support/Logs、Caches、tmp 和完整 UserDefaults domain。
- 成功写入 epoch 和切割时间后移除 journal。journal 优先于已写入 epoch，重试复用首次时间，不扩大旧载荷丢弃范围。
- Watch 清理自身 Application Support（含 outbox）、完整 UserDefaults、Caches、tmp，最后写入 epoch。
- 重置不访问 Photos/HealthKit 删除 API 或沙盒外目录。安装标识随偏好清理重新生成。
- 任务文档加载成功后才按引用清理孤立文件；损坏或未知版本文档不提供清理依据。

## 模型与持久化

- `TrainingSession` 保存 ID、训练起止和 `ShotMarkerEvent(id, markedAt)`；路径为 Application Support/ShotMarker/training-sessions.json。
- `TrainingSessionJSONTransferService` 导入单条或数组 JSON，以训练 UUID 新增或替换，导出为 JSON 数组；训练列表提供全部导出、多选合并及确认删除。正式服务不注入旧组合审核 Store，不修改已有任务快照。
- `HighlightTask` 拥有不可变训练快照、任务视频、`ClipSettings`、全部 `reviewItems`、活动执行、最近结果及当前成片。
- 新建快照使用新的任务本地打点 UUID、毫秒时间及稳定 `sourceOrder`，不保存原训练 ID 或原打点 ID；临时训练适配对象仅供纯规划和只读 UI。
- `HighlightTaskStore` actor 是 highlight-tasks.json 唯一写入者，正常事务写 schema 4，兼容读取 schema 1/2/3/4。旧任务取景缺失按原画面，缺少序号布局按任务当前默认；单纯读取或无变化事务不改写文件、不改 revision/epoch。schema 4 使不支持逐段布局的旧客户端走未来版本保护。读取后校验、原子写盘，成功后才发布 UI。
- `ClipSettings.isValidRange` 统一检查前后秒数有限、均在 -20…20 且相加至少 1 秒；不把负值取绝对值或静默改写。UserDefaults 不保存无效编辑中间值，读取无效默认值时回退产品默认。
- `ClipFraming` 保存倍率及正向源画面左上原点的归一化中心。UI 规范倍率到 0.1、中心到 0.00001 后限制边缘；持久化保留原始输入并严格校验，不能静默修复损坏取景。旧执行快照缺字段按原画面，明确 null 仍视为损坏。
- `MarkerLabelPlacement` 保存相对最终成片画布的字号比例及左上原点归一化中心，范围分别为 0.04…0.16、0…1、0…1，必须有限。审核项和执行片段持有可选布局；缺字段回退各自任务/执行快照的样式，无覆盖值编码时省略字段。显式 null、缺成员或非法数值按损坏处理。读取保留合法精度，拖动输入规范到 0.00001；只改字号不舍入已保存中心。逐段布局不包含透明度。
- 配置更新校验 expectedRevision；有变化才递增一次，无变化不写盘。生成进度、结果及相册状态不改变配置 revision。
- 未知高 schema 只读保护；损坏文档改名保留并报告错误，后续启动仍不当作空文档清理文件。
- PhotoKit 来源使用稳定资源引用；文件来源流式 SHA-256 后放入 HighlightTasks/<task>/Inputs/<video>.<ext>。所有已选文件均归任务持有，包括当前未参与成片的来源。
- 文件只存受控相对路径。`HighlightTaskFileStore` 先解析并规范受信根目录，再从同一根目录逐段派生可能尚未创建的目标路径；逐段拒绝符号链接，并验证最终规范路径仍位于根目录内。创建用 staging；更新先移动新增文件、提交 JSON 后才清理旧副本，失败回滚本次新增文件。
- 当前成片为 HighlightTasks/<task>/Outputs/<output>/highlight.mov；每次输出使用新的 UUID 目录。
- 旧 `HighlightJob` 和组合确认类型仍保留供旧契约回归，正式 App 不再实例化旧 Manager/Store，也不读取或迁移旧文档。训练服务默认不注入组合确认 Store。

## 界面与播放组件

- `TrainingSessionHighlightView` 管理视频选择、准备与配置草稿；`SelectedTrainingVideoCard` 独立展示所选视频的缩略图、可用性和准备进度。
- `HighlightClipPlaybackController` 管理片段播放状态与范围；独立的 `HighlightClipPlaybackEngine.swift` 定义可注入播放接口及 AVPlayer 适配，负责 item、seek 和时间观察者的系统调用。
- 播放器每次加载（含无效范围）先失效旧来源并释放 item 和观察者。预览、片尾回首与越界重播共享定位请求代次，发起前和完成后都校验；旧观察回调不能修改新来源。未完成定位显式保存目标，播放等待最新定位完成后才启动实际播放器。

## 任务与生成数据流

~~~text
训练 + 有序视频 + 设置
→ HighlightTaskPlanner.makeTask
→ 任务文件事务 + HighlightTaskStore.create
→ 任务配置 / HighlightReviewSession
→ expectedRevision 配置事务
→ HighlightRenderExecution（不可变快照）
→ HighlightTaskManager 全 App 串行调度
→ HighlightRenderRunner / VideoClipEditingService
→ 新输出移动 → 原子提交当前引用 → 清理旧输出
~~~

- `HighlightTaskPlanner` 复用默认范围规则；视频变化保留精确安全确认及其序号布局，确认项占位并分隔默认合并链。只改偏移保留人工范围、取景和序号布局，新默认窗口可用则更新基线，不可用则保留旧基线；样式变化不规划。重置全部片段重新生成无布局覆盖值的默认项。
- `HighlightReviewSession` 持有任务 revision、审核 ViewModel 和单一播放器，统一释放请求、AVAsset、播放器 item/观察者、帧数据和准备文件。
- 编辑器使用工作副本；保留或排除通过 `saveClipReview` 与 expectedRevision 事务保存，Store 成功后更新卡片、汇总和连续导航。过期提交或写盘失败保留当前调整；未保存调整的离开和跳转经过继续调整或放弃提示。
- 编辑器区分已保存 item 与入口工作基线，取景与序号布局各自优先使用目标保存值，只有 nil 才接受临时继承；dirty 比较范围、包含状态、有效取景和有效布局，全部回到基线就清除。确认将当前有效取景与完整布局快照和其他字段一并原子保存，排除项同样保存，失败不发布导航。
- 连续确认按 items 原顺序进入紧邻下一项，不过滤已确认或排除项，末项返回总览。缩略图条使用同一候选顺序，“下一个未看”单独查找后续默认项。只有同源成功确认产生携带目标 UUID、来源 ID、取景与序号布局的 `.continueReview`；消费时重新核对目标与来源，并分别优先采用目标保存值；普通 `.open` 不继承，当前项重选也按该入口重新打开。
- `HighlightClipReviewView` 持有会话级 `ClipEditorOperations`，模式为取景、序号或全关，默认取景且列表收起；导航复用状态，退出后不持久化。模式限制取景手势、倍率、恢复与无障碍动作，序号模式通过 `ClipMarkerLabelOverlay` 接收画布内相对拖动及四向无障碍移动，滑杆只修改字号。列表展开不改模式或业务数据，空间调整暂停播放器。
- `HighlightClipReviewContext` 从完整 items 顺序推导稳定候选编号和相邻项，与打点及导出序数独立。它将当前工作副本代入最终规划器，以最终片段的打点成员关系判断是否合并；跨视频不计算时间距离，同源范围使用实际交集与对称间隔。
- 时间轴在可视窗口内绘制同源相邻范围的淡色参考条，不接收手势；起止、整体移动和播放头保留拖动及 VoiceOver 步进。视图只显示相对播放进度，移除恢复默认范围和撤销的入口及对应 UI 处理路径。
- ReviewViewModel 仍保留完整前值恢复 API 与事务互斥作为底层能力，不写入额外任务字段；正式视图不调用它，相关单元测试继续保护 nil / 原画面 / 放大取景及加载代次语义。
- 导航目标每次打开使用独立 UUID 作为视图身份，包括重选当前片段；片段 UUID 仍用于数据查找和缩略图刷新。重新打开会重建编辑器、时间轴和媒体任务。显式跳转前清理旧媒体，离开回调不重复清理，避免取消同一片段新打开的胶片任务；迟到结果仍受加载代次保护。
- `ClipFramingViewport` 使用共享源画面比例适配几何，AVPlayerLayer/缩略图只在有效源区域内缩放和平移；编辑器先适配成片画布，再将当前来源取景适配进去，播放器外部留白不参与空间操作。`ClipOutputCanvas` 异步读取最终规划首个保留来源的正向尺寸，全排除仅预览当前来源；其加载代次和播放器 loadGeneration 分别阻止迟到元数据覆盖当前画布或来源。缺少真实画布或源尺寸时禁用空间编辑，不以假尺寸保存新布局。
- `HighlightClipReviewMediaProvider` 与 ViewModel 保留的缩略图数据均有上限；局部胶片退出时释放，审核不导出逐片段文件。
- 本地照片资源先校验可用，审核和生成关闭网络访问；下载由配置页明确准备流程承担。
- `HighlightClipReviewPlanner` 将无覆盖值解析为任务当前默认布局后规划最终片段；相邻合并要求同来源、有效取景和有效布局相等，排除项中断合并。不同取景或布局的重叠范围完整顺序输出。总览、关系提示和编辑器工作副本预览复用该规划器，预览显示所属最终片段的导出编号，排除项使用占位文本。
- `HighlightRenderRunner` 只读取执行快照，使用包含明确取景、已解析布局及任务样式的精确片段建立单一 AVMutableComposition/导出，并使用该执行独有临时目录；之后的任务或全局样式修改不进入运行中执行。
- `ClipFramingVideoComposition` 捕获每段方向、裁切、输出时间、编号及布局为不可变指令。自定义 CI compositor 按来源方向、共享裁切、固定画布比例适配、编号的顺序单次渲染，组成轨道保持 identity，透明编号不跳过取景。当前使用 BGRA SDR 路径，HDR/广色域保真未验收。
- 合成器串行渲染，以同一锁管理请求资源获取、结束与取消；取消返回前结束所有持有请求，后台渲染只使用已捕获资源，不能重复结束请求。音轨仍按各段输出位置插入，保持进度和取消清理事务。
- 活动状态统一推导操作集合为停止。停止先持久化执行失效，再取消；旧 Runner 真正退出和清理前不释放串行槽。
- 回调通过 task/execution/revision 门槛验证；迟到结果和进度不能覆盖停止或新执行。
- background 禁止调度并停止所有执行，inactive 不触发。启动将遗留执行改为 stopped，不自动恢复。
- 输出移动或 JSON 提交失败保留旧成片；新引用提交后再清理旧输出。删除先移除任务文档，再清理任务自有文件。
- `MarkerLabelRendering` 与 `MarkerLabelLayout` 为编辑预览和导出共用字体、栅格标签、内边距、边界及坐标转换；长文本必要时整体等比缩小，显示边界限制不改写期望中心。合成器图像缓存键包含文本、画布尺寸、字号及透明度，位置按每段计算；导出显式接收样式，不访问全局设置 Store。历史设计依据见[序号布局规格](../archive/2026-10/2026-10-25-clip-number-layout-spec.md)。

## Watch 同步

~~~text
Watch outbox → transferUserInfo → PhoneWatchSyncService
→ cutover 门槛 → TrainingSessionImporter → ACK → Watch 移除 outbox
~~~

- 同步入口在导入和内容日志前检查 payload.endedAt；小于或等于固定 cutover 的旧载荷只 ACK，不导入、不发送成功事件。
- 新载荷按训练 ID 幂等导入，成功写盘后、ACK 前记录同步成功事件。
- Watch 未激活、发送失败或等待 ACK 时保留 outbox 并重试。
- iPhone 提供同步诊断快照；Watch 没有独立日志导出。
- Watch 的 `HealthKitWorkoutRuntimeSessionManager` 为每次训练请求分配 UUID，以 idle / authorizing / running / finishing 状态隔离授权和结束回调。结束先使待授权或待启动请求失效；上一训练持有的 workout 完成结束采集及保存尝试后，仅启动仍在等待的新请求，过期授权/结束回调不改变新训练。
- HealthKit 后端只申请写 workout，不读取心率或其他健康数据。每个 `HealthKitWorkoutRuntimeHandle` 独立持有对应的 session 与 builder，直到结束采集及保存完成；保存失败同样释放 finishing 槽。

## 日志与远端观测

- AppLogger 通过 `AppLogStore` actor 写结构化 JSONL，默认目录为 Application Support/ShotMarker/Logs。正常 append 后在同一次无悬挂点的 actor 调用中执行 14 天窗口和 30 MB 总量清理；按日志文件日期删除过期或最旧文件，显式 cleanup 使用同一规则。
- 默认 Store 首次 append/cleanup 清理旧 Application Support/Logs，失败则后续重试；数据世代重置也清理该旧目录，epoch 仍为 1。注入自定义日志目录时默认不清理其它目录。
- 日志导出包含 manifest、设备/App 信息、日志和 iPhone 同步诊断。
- iPhone 通过官方 sentry-cocoa 9.26.0 源码产品 SentrySPM 对接 GlitchTip，业务适配层导入 SentrySwift；Watch 不链接 Sentry。
- AppLogger.error 同时发送精简错误事件；其他级别仅写本地。不开启性能追踪、Profiling、Session Replay 或自动 Session Tracking。
- 任务相关日志仅包含状态、计数、总时长及封闭错误类别；导出和相册错误不传递原 NSError 的来源信息，日志不记录片段起止范围。
- Analytics 仅在 Release 真机 iPhone 启用；发送来源、自用标记及同步/生成/保存的尝试、结果和受控原因。生成成功仍在当前输出引用提交后，保存成功仍在 Photos 实际成功后发送；分发解析不阻塞业务启动，见[产品埋点](analytics.md)。

## 有效隐私边界

- PrivacyInfo.xcprivacy 声明 Device ID、Product Interaction（linked、Analytics）和 Crash Data、Performance Data、Other Diagnostic Data（unlinked、App Functionality）；全部 Tracking 为 false。
- Required Reason API 覆盖 UserDefaults `CA92.1`、File Timestamp `C617.1` 和 System Boot Time `35F9.1`。2026-10-27 已核对源码、Release Archive 和导出的 Distribution IPA；此前 Simulator 产物核对不再是唯一证据。不声明后台持续生成。
- 任务、训练、视频、帧、业务来源标识、摘要、业务 UUID、文件名和绝对路径不进入 Analytics 或 GlitchTip metadata。Analytics 专用随机操作 UUID 只用于一次尝试配对，不增加业务存储字段。
- GlitchTip 不配置用户身份，不上传训练、视频、截图或本地日志文件。客户端 DSN 可随 App 分发；管理令牌不得进入 Git。
- 训练与任务创建后无回查、同步或级联删除关系；当前数据与生命周期契约见本页及[产品事实](product.md)；历史设计依据见 [任务规格](../archive/2026-09/2026-09-03-editable-highlight-task-spec.md)。
