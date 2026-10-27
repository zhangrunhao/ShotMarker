# ShotMarker 产品埋点

- 本地源码复核：2026-10-27（Analytics 客户端、运行时策略、安装标识和正式服务组装；本次未运行测试）。
- 测试证据的代码范围见[质量状态](quality.md)；生产保留日志与查询 API 最后只读核验为 2026-10-27，受控接收与存储验收仍为 2026-08-16。
- 用途：仅用于观察核心产品流程是否成功，不用于广告、跨公司跟踪或用户画像

## 当前结论

客户端当前实现与下述事件、请求及隐私契约一致。线上接收与存储状态属于变化中的外部事实，必须以带日期的验证结果为准。

## 启用范围

- 只有 Release 且运行在 iPhone 时使用真实 Analytics 客户端。
- Debug、Apple Watch、iPad 和 visionOS 使用 no-op，不发送产品事件。
- App 内没有 Analytics 开关；发送范围由构建配置和设备类型决定。
- 当前实现不区分 App Store、TestFlight 和开发者 Release，也未显式排除 Release iPhone 模拟器。请求不包含分发渠道或 App 版本，分析时不能自动排除自用与测试。

## 有效事件契约

| 事件 | 成功触发点 | 不触发的情况 |
| --- | --- | --- |
| `app_launch` | 数据世代重置成功并完成依赖组装后，每个进程启动记录一次 | 前后台切换、View 重建、Debug 或非 iPhone 运行 |
| `training_sync_succeeded` | Watch payload 成功写入 iPhone 本地存储后、发送 ACK 前 | 切割前旧载荷、解码或导入失败；ACK 失败不撤销已记录事件 |
| `highlight_generate_succeeded` | 新成片已进入稳定路径且当前输出引用原子提交到任务后 | 创建、排队、运行、停止、失败、输出移动或任务提交失败 |
| `highlight_save_succeeded` | 当前成片实际写入 Photos 成功后；随后持久化本地保存状态 | 权限拒绝、缺少输出或相册写入失败；成功后的本地状态写入失败不撤销实际保存事件 |

Watch payload 重发或用户重复保存可能产生重复成功事件；网络失败或进程提前结束可能丢失事件。该链路不承诺恰好一次投递。

`app_launch` 表示进程依赖组装完成，没有主动进入前台的判定，不能等同于用户主动打开或使用会话。四事件没有 session、任务或成片关联标识；只能做安装级事件覆盖和首次观测回访，不能用次数直接计算严格业务漏斗或失败率。

## 有效请求契约

- 使用 `GET https://zhangrh.shop/track`。
- 查询参数严格只有 `project=shotmarker`、`event`、`device_id`。
- `device_id` 是保存在 UserDefaults 中的 12 位随机安装标识，只代表当前安装；卸载重装或全量数据世代切割后重新生成。
- 使用临时 URLSession、5 秒超时、不使用 Cookie 或持久缓存、不重试。
- URL 构造、网络、TLS、超时或非 `204` 响应都会静默丢弃；失败不影响同步、集锦或相册保存。

## 有效数据与隐私边界

- 客户端不发送训练记录、打点时间、视频、文件名、照片、语音、HealthKit 数据、错误详情、设备型号、系统版本、用户身份或自由文本。
- PrivacyInfo.xcprivacy 将 Device ID 和 Product Interaction 声明为 linked、用于 Analytics，Tracking 为 false。
- Analytics 遥测会离开设备并保存在自建服务器；ShotMarker 不向自建服务器上传训练记录、源视频、生成视频或其他业务内容。
- 源视频和用户手动保存的成片是否通过 iCloud 同步，由系统照片库设置决定。
- GlitchTip 错误与崩溃上报是独立链路，边界见 [技术架构](architecture.md) 与 [发布状态](release.md)。

## 外部状态摘要

- 2026-08-16 的最后一次生产验收中，服务端增加 ISO 8601 接收时间，并只保存 `project`、`event`、`time`、`device_id` 四个字段。
- 同一验收基线下，Analytics JSONL 不保存来源 IP、User-Agent、Cookie 或完整请求 URL，也没有固定自动过期时间。
- 2026-10-27 只读核验时，当前保留日志中 ShotMarker 四事件共 92 条，字段校验通过，四事件逐日次数和去重安装数与线上查询 API 一致。安装标识只在服务端内存参与去重，没有提取原始日志或将原始标识写入文档。
- 该次未发送测试事件，未核验受控 Release/TestFlight 端到端发送、自动过期配置或历史日志完整性。保留策略的最后验证日期仍为 2026-08-16；脱敏使用结论见[观测验证](observability.md)。
