# ShotMarker 产品埋点

- 本地实现复核：2026-10-27；测试与构建范围见[质量状态](quality.md)。
- 用途：观察核心流程的尝试、结果和故障位置，不用于广告、跨公司跟踪或用户画像。
- 2026-10-27 网站接收、查询与分析页面已部署；App 1.3.1（4）已提交 Apple 审核并设置通过后自动发布，尚未确认上架。历史线上数据不能回填来源或操作信息。

## 有效范围与来源

- 仅 Release 真机 iPhone 启用发送；Debug、模拟器、Apple Watch、iPad 和 visionOS 使用 no-op。
- 分发来源为 `app_store`、`test` 或 `unknown`；开发签名/TestFlight 归测试，无法确认的渠道保留未知，不默认算正式。
- 诊断入口提供本地“自用”标记，默认关闭；它影响后续新操作和启动事件，同一操作中途切换不会改变该操作分类；不修改历史数据或业务功能。
- 查询的“自用”优先于渠道；“正式使用”表示非自用且 App Store 分发，“测试”表示非自用测试分发。此分类不能证明访问者身份，也不能自动识别未标记的自用。

## 有效事件契约

| 流程 | 开始 | 结果与边界 |
| --- | --- | --- |
| 启动 | `app_launch` | 依赖组装完成后每进程一次；不等于主动进入前台或使用会话 |
| 手机接收同步 | `training_sync_started` | 识别 Watch 载荷类型后、解码前；导入成功记 `training_sync_succeeded`，解码/导入失败记 `training_sync_failed`，切割前旧载荷记 `training_sync_ignored` |
| 生成 | `highlight_generate_started` | 请求入口、校验前；稳定成片及任务引用提交后记 `highlight_generate_succeeded`，校验/排队/导出/提交失败记 `highlight_generate_failed`，停止/后台/取消记 `highlight_generate_cancelled` |
| 保存 | `highlight_save_started` | 有效保存入口、权限与文件检查前；Photos 实际成功记 `highlight_save_succeeded`，校验/权限/相册失败记 `highlight_save_failed`，取消记 `highlight_save_cancelled` |

- `training_sync_ack_failed` 是导入后的回执诊断；不撤销导入成功。
- `highlight_save_state_failed` 是 Photos 成功后的本地状态诊断；不撤销实际保存成功。
- 每次尝试使用独立随机 `operation_id`；生成排队、执行和终态共用它，重复或迟到回调不重复发送终态。该标识只属于遥测，不增加业务存储字段。
- Watch 重发会形成新的手机接收尝试，不能据此统计独立训练次数。没有增加 Watch 发送侧埋点，仍看不到未发送或未到达手机的情况。
- 不承诺恰好一次投递。无终态是“结果未知”，不直接算失败；有操作标识但缺开始的终态单列。旧版无操作标识仅参与趋势，不能还原步骤。

## 请求与接收契约

使用 `GET https://zhangrh.shop/track`，允许的查询字段为：

| 字段 | 内容 |
| --- | --- |
| `project` / `event` | 固定 `shotmarker` / 上述封闭事件名 |
| `device_id` | UserDefaults 中的 12 位随机安装标识；重装或全量世代切割后重建 |
| `distribution` / `is_self_use` | `app_store`、`test`、`unknown` / 字符串 `true`、`false` |
| `app_version` / `app_build` | 有长度限制的数字点分版本 / 数字构建号；无法解析时 `unknown` |
| `operation_id` | 专用随机小写 UUID；启动事件不包含 |
| `stage` / `reason` | 受控步骤及原因枚举；不发送原始错误文本 |

步骤覆盖接收、解码、导入、回执、校验、排队、导出、提交、权限、Photos 写入和本地状态。原因区分非法输入、来源不可用、导出/提交失败、权限拒绝、缺少成片、相册/状态写入失败，以及用户/后台/系统取消等受控类别。

- 临时 URLSession，5 秒超时，不使用 Cookie 或持久缓存，不重试。构造、网络、TLS、超时和非 `204` 响应静默丢弃，不改变业务结果。
- Nginx 仍负责追加 JSONL 和服务端接收时间；Node 仍负责只读聚合，未改用新采集或业务架构。
- 新字段及服务端完整枚举、校验、过滤、去重与资源限制由[网站 Track 契约](https://github.com/zhangrunhao/zhangrh.shop/blob/main/docs/current/track.md)维护。四字段旧记录归未知；非法扩展字段不降级成正式使用。

## 隐私边界

- 不发送训练记录、打点时间、视频、文件名、照片、语音、HealthKit 数据、原始错误、业务 UUID、设备型号、系统版本、用户身份或自由文本。
- 随机安装标识用于安装级去重；操作标识用于一次尝试的步骤配对。公开查询只返回聚合数据，不返回原始标识或事件。
- PrivacyInfo.xcprivacy 将 Device ID 和 Product Interaction 声明为 linked、用于 Analytics，Tracking 为 false。
- Analytics 会离开设备；训练记录、源视频和生成视频不上传至自建服务器。系统照片库/iCloud 行为由用户设置决定。
- GlitchTip 是独立链路，见[技术架构](architecture.md)与[发布状态](release.md)。

## 外部状态摘要

- 2026-08-16 受控验收的服务端只保存 `project`、`event`、`time`、`device_id`；不保存 IP、User-Agent、Cookie、完整 URL，当时没有固定自动过期时间。
- 2026-10-27 只读核验的保留日志含 ShotMarker 92 条四字段事件，逐日次数和安装去重数与查询 API 一致；未提取原始标识或日志到文档。
- 2026-10-27 网站发布完成：新旧接收格式已用实际配置和隔离日志验证，未向生产日志写入虚构用户事件；聚合接口和公开页面已核对。详情由[网站发布记录](https://github.com/zhangrunhao/zhangrh.shop/blob/main/docs/archive/2026-10/2026-10-27-analytics-release-plan.md)维护。
- 真实 App Store/TestFlight 来源分类及手机到生产接收的受控端到端验收仍未完成。服务端部署不改变历史使用结论，见[观测验证](observability.md)。
