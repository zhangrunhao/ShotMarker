# ShotMarker 最小埋点上报设计

日期：2026-08-16

状态：已确认
涉及项目：`ShotMarker`、`zhangrh.shop`

## 1. 背景

ShotMarker 当前是本地优先的 iPhone 与 Apple Watch 应用。训练记录、打点、所选视频和
集锦视频都在用户设备上处理。iPhone 端已有 `AppLogger`、`AppLogEvent` 和
`AppLogStore`，但这些组件只用于本地诊断日志，只有用户主动导出时开发者才能看到。

`zhangrh.shop` 已有一套不依赖数据库和第三方 SDK 的一方埋点链路：

1. 客户端向 `GET /track` 发送事件。
2. Nginx 返回 `204`，并把事件写入独立的 `events.jsonl`。
3. 日志按周期轮转并保留约 98 天。
4. Backend 只读聚合日志，通过 `/api/track/summary` 返回项目、事件、日期和设备数汇总。
5. 汇总接口不返回原始设备标识。

本设计让 ShotMarker 复用这条链路，只观察最小核心漏斗，不引入账号、数据库、第三方
分析 SDK、离线队列或远程诊断日志。

## 2. 已确认决策

1. 首版观察四个核心节点：App 启动、Watch 训练同步成功、集锦生成成功、集锦保存成功。
2. 使用 12 位随机安装 ID 区分安装；不使用 IDFA、IDFV、Apple ID 或硬件信息。
3. 随机安装 ID 保存在 `UserDefaults`，卸载重装后重新生成。
4. 埋点默认开启，不增加设置开关或首次启动提示。
5. 使用独立的 `AnalyticsTracking` 客户端，不复用或包装 `AppLogger`。
6. 每次事件即时发送；不缓存、不批量、不重试，失败直接丢弃。
7. 只有 iPhone 端发送事件；Apple Watch 不直接访问网络埋点接口。
8. 所有事件使用空参数对象，不上传训练、视频、错误或诊断上下文。
9. Debug 与单元测试默认不上报；TestFlight 和 App Store 的 Release 构建上报。
10. App Store 隐私披露采用保守口径：设备 ID 和产品交互用于分析、与设备关联、不用于
    Tracking。

## 3. 目标

- 查看指定时间范围内 ShotMarker 的事件次数和独立安装数。
- 观察从启动到同步、生成和保存的近似漏斗。
- 保持埋点失败与产品主流程完全隔离。
- 明确限制上报字段，避免把本地诊断日志或业务数据带到服务端。
- 复用 `zhangrh.shop` 的 Nginx JSONL、轮转和查询能力。
- 让代码、隐私清单、App Store Connect 和公开隐私政策使用一致口径。

## 4. 非目标

- 不统计账号、真实用户或跨设备用户。
- 不实现严格按顺序、按 cohort 或按首次使用日期计算的漏斗。
- 不实现留存、会话时长、页面停留、按钮点击或失败原因分析。
- 不上传训练记录 ID、训练时间、打点时间、打点数量或 Watch 设备信息。
- 不上传视频 ID、视频时间、视频数量、集锦任务 ID 或文件信息。
- 不上传错误对象、错误码、本地诊断日志、系统版本或设备型号。
- 不引入第三方分析 SDK、数据库、后台管理页面或新认证系统。
- 不实现离线 outbox、请求重试、发送回执、客户端去重或服务端业务去重。
- 不增加埋点开关、隐私选择页面或远程删除接口。
- 不修改 Apple Watch target 的网络行为或隐私清单。

## 5. 总体架构

```text
ShotMarker iPhone 业务成功节点
        │
        │ AnalyticsTracking.track(event)
        ▼
AnalyticsClient
  ├── InstallationIDStore：读取或生成随机安装 ID
  ├── 固定 project=shotmarker
  ├── 固定 params={}
  └── 临时 URLSession 即时发送
        │
        │ GET https://zhangrh.shop/track?...
        ▼
zhangrh.shop Nginx
  ├── 返回 204
  └── 追加写 events.jsonl
        │
        ▼
zhangrh.shop Backend 只读聚合
        │
        ▼
GET /api/track/summary?days=30&project=shotmarker
```

职责边界：

- ShotMarker 只生成安装 ID、选择固定事件并发送请求。
- Nginx 负责接收、生成服务端接收时间、持久化和配合日志轮转。
- Backend 负责校验、过滤和聚合，不修改原始日志。
- `AppLogger` 继续只记录本地诊断日志，不调用埋点客户端。
- 埋点客户端不读取或上传 `AppLogStore` 中的任何内容。

## 6. iPhone 客户端设计

### 6.1 固定事件类型

新增只包含四个 case 的事件类型：

```swift
enum AnalyticsEvent: String, Sendable {
    case appLaunch = "app_launch"
    case trainingSyncSucceeded = "training_sync_succeeded"
    case highlightGenerateSucceeded = "highlight_generate_succeeded"
    case highlightSaveSucceeded = "highlight_save_succeeded"
}
```

业务调用点不能发送任意字符串，也不能附加任意参数。新增事件必须显式修改枚举、测试、
埋点文档，并重新检查隐私披露是否仍然准确。

### 6.2 安装 ID

`InstallationIDStore` 负责提供安装 ID：

- 使用专用 `UserDefaults` key，例如 `analytics.installation_id`。
- 有效值必须匹配 `[A-Za-z0-9]{12}`。
- 首次读取不到有效值时，生成新的 12 位随机字母数字字符串并保存。
- 后续事件复用同一值。
- 测试可注入 `UserDefaults` suite 和 ID 生成函数。
- 不从设备名称、系统配置、网络地址或其他信号推导 ID。
- 不使用 IDFA、IDFV、Keychain 或 iCloud，因此卸载重装会得到新 ID。

`UserDefaults` 选择是有意的：本设计只需要区分当前安装，不需要在重装后继续识别同一
设备。

### 6.3 发送接口

定义可注入的最小协议：

```swift
protocol AnalyticsTracking: Sendable {
    func track(_ event: AnalyticsEvent)
}
```

`AnalyticsClient` 实现该协议。`track` 是同步、无返回值且不抛错的方法；它只负责安排一
个独立异步请求，然后立即把控制权交还业务调用方。

生产请求固定为：

```text
GET https://zhangrh.shop/track
  ?time=<客户端 Unix 毫秒时间戳>
  &project=shotmarker
  &device_id=<12 位随机安装 ID>
  &event=<AnalyticsEvent.rawValue>
  &params={}
```

使用 `URLComponents` 和 `URLQueryItem` 编码查询参数，不手工拼接或转义 URL。请求使用
HTTPS、忽略本地缓存、超时 5 秒。客户端使用不持久化 Cookie 和响应缓存的临时
`URLSession` 配置。

### 6.4 构建配置

- Release 组合根只在 iPhone 运行时创建真实 `AnalyticsClient`。
- iPad、Apple Watch、visionOS 和 macOS 运行时使用 `NoopAnalyticsTracker`。
- Debug 组合根创建 `NoopAnalyticsTracker`。
- 单元测试默认注入 spy、stub 或 no-op，不访问公网。
- `AnalyticsClient` 自身的请求构造测试显式实例化真实实现，但注入测试网络会话。

这样可以避免 Xcode 日常调试、SwiftUI Preview、非 iPhone 平台和单元测试污染生产
统计。iPhone 上的 TestFlight 与 App Store Archive 使用 Release 配置，因此会发送真实
事件。

## 7. 事件语义与调用点

### 7.1 `app_launch`

触发位置：`ShotMarkerApp.init()` 完成埋点依赖组装后，每个 iPhone App 进程发送一次。

不触发：

- Scene 在前后台切换。
- SwiftUI View 重建。
- Apple Watch App 启动。
- Debug、Preview 或单元测试默认组合根。

事件次数近似 App 进程启动次数；独立安装数表示查询范围内至少启动过一次的安装数。

### 7.2 `training_sync_succeeded`

触发位置：`PhoneWatchSyncService.handleReceivedUserInfo` 中，payload 解码成功且
`TrainingSessionImporter.import` 已成功写入 iPhone 本地存储之后、发送 ACK 之前。

选择导入成功而不是 ACK 成功作为节点，是因为用户的训练记录此时已经在 iPhone 上可用；
后续 ACK 失败不应把有效同步记为失败。

Watch 可能因为 ACK 失败再次发送同一 payload。首版允许重复事件：它可能略微增加事件
次数，但同一查询范围内的独立安装数不会因此增加。

### 7.3 `highlight_generate_succeeded`

触发位置：`HighlightJobManager` 等待 `HighlightJobRunner.run` 返回后，确认最终任务状态
为 `.completed` 且输出视频已移动到正式任务路径时发送一次。

不能在 `HighlightJobRunner` 的通用 `onChange` 回调中按 `.completed` 发送，因为当前
manager 会先收到状态回调，再处理 runner 的最终返回值，可能导致同一次任务重复上报。

任务创建、进入队列、开始导出、导出进度完成但文件移动失败、取消或失败均不上报。用户
重新运行失败任务并最终成功时，新的成功运行会产生一条事件。

### 7.4 `highlight_save_succeeded`

触发位置：`HighlightJobManager.saveToPhotoLibrary` 中，相册写入成功、
`photoLibrarySavedAt` 已更新且任务状态已持久化之后发送。

相册权限请求、开始保存、缺少输出文件、用户拒绝权限或相册写入失败均不上报。如果用户
实际重复保存同一集锦，每次成功写入都可以产生一条成功事件。

## 8. 失败与并发行为

客户端必须遵守以下失败边界：

- URL 构造失败：丢弃事件。
- 无网络、DNS 失败、TLS 失败或超时：丢弃事件。
- 服务端返回非 `204`：丢弃事件。
- App 在请求完成前退出：允许丢失事件。
- 埋点失败不写入 outbox，不在下次启动补发。
- 埋点失败不弹窗、不改变业务状态、不影响 Watch ACK、集锦任务或相册保存结果。
- 埋点失败不作为 `AppLogger` 的 error 记录，避免分析系统与诊断系统互相依赖。

客户端不保证恰好一次投递。网络重放、用户重复操作和 Watch payload 重发可能产生重复
事件；进程终止和网络失败可能导致事件丢失。这是“最简单、非关键遥测”方案接受的取舍。

埋点实现需要能从 App 初始化、WatchConnectivity 回调和 `@MainActor` 的集锦管理器安全
调用。实现可使用不可变依赖与内部同步保护，并通过 Swift 严格并发检查；不能要求业务
调用方等待网络请求。

## 9. 服务端设计

### 9.1 采集协议与存储

沿用现有 `/track` Nginx location 和 JSONL schema v1，不新增 API：

- `schema_version`：固定为 `1`。
- `request_id`：Nginx 生成。
- `received_at`：Nginx 生成，作为查询日期和保留范围的可信时间。
- `client_time`：ShotMarker 发送的毫秒时间戳，只用于诊断，不用于日期过滤。
- `project`：固定为 `shotmarker`。
- `device_id`：随机安装 ID。
- `event`：四个固定事件之一。
- `params_encoded`：编码后的空 JSON 对象。

Nginx 埋点记录不包含 IP、User-Agent、Referer、Cookie、Authorization 或完整请求 URL。
网络服务处理请求时会临时看到来源网络地址，但不把它写入独立的埋点 JSONL。

日志继续使用宿主机持久目录、轮转文件和约 98 天保留策略。服务端不建立 ShotMarker
专用数据库或表。

### 9.2 项目白名单

`zhangrh.shop` 当前只接受 `hub` 和 `cardgame`。实现需要在以下两处加入
`shotmarker`：

- `backend/projects/track-query.js` 的记录解析项目集合。
- `backend/projects/track.js` 的查询参数项目集合与对应错误文案。

不顺带抽取新的共享配置模块；两处小型白名单保持与现有结构一致，并用测试防止遗漏。

### 9.3 查询结果

使用现有接口：

```text
GET /api/track/summary?days=30&project=shotmarker
```

响应继续包含：

- `totals.events`：查询范围内的有效事件数。
- `totals.devices`：查询范围内出现过任一事件的独立安装数。
- `event_breakdown`：每个事件的事件数和独立安装数。
- `daily`：每天的事件数和独立安装数。
- `diagnostics`：读取、拒绝、重复和范围过滤统计。

接口不返回原始安装 ID、原始参数或逐条事件。

首版的漏斗是近似漏斗。例如，可以用同一时间范围内
`highlight_generate_succeeded.devices / app_launch.devices` 观察趋势，但这不是严格转化率：

- 分母可能包含在查询期之前已经完成早期节点的老安装。
- 接口不校验同一安装是否按顺序经过全部节点。
- 接口不按首次安装日期建立 cohort。

本设计不修改聚合响应来计算漏斗交集或顺序。

## 10. 隐私设计

### 10.1 实际采集字段

ShotMarker 只主动发送：

- 客户端事件时间。
- 固定项目名 `shotmarker`。
- 随机安装 ID。
- 四个事件之一。
- 空参数对象。

服务端另外生成请求 ID 和接收时间。随机安装 ID 不与账号、姓名、联系方式、训练记录、
视频、健康数据、其他 App 数据或 `zhangrh.shop` 浏览器设备 ID 合并。

### 10.2 Apple 隐私声明

ShotMarker 主 App target 新增 `PrivacyInfo.xcprivacy`，至少声明：

- `NSPrivacyTracking = false`。
- `Device ID`：用途为 Analytics，linked 为 `true`，tracking 为 `false`。
- `Product Interaction`：用途为 Analytics，linked 为 `true`，tracking 为 `false`。
- 不声明 tracking domain。

采用 linked 为 `true` 的保守口径，是因为持久安装 ID 会把多次产品交互关联到同一安装。
它不表示开发者知道真实身份，也不表示进行 Apple 定义的 Tracking。

App Store Connect 在包含该功能的新版本上线前同步声明：

- Identifiers → Device ID。
- Usage Data → Product Interaction。
- Purpose → Analytics。
- Data Linked to the User/Device → Yes。
- Used for Tracking → No。

本方案不访问 IDFA，不把数据与其他公司收集的数据结合用于广告或广告衡量，也不与数据
经纪商共享，因此不请求 AppTrackingTransparency 权限。

参考：

- [Apple App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests)
- [Apple User privacy and data use](https://developer.apple.com/app-store/user-privacy-and-data-use/)

### 10.3 公开隐私政策

`zhangrh.shop` 的 ShotMarker 中英文隐私政策需要在 App 新版本上线前更新，明确：

- iPhone App 默认收集随机安装 ID 和四类产品使用事件；其他平台不发送这些事件。
- 数据只用于统计安装使用情况和功能漏斗。
- 不采集训练记录、打点、视频、HealthKit 数据或诊断日志作为埋点内容。
- 不使用第三方分析 SDK，不用于广告或跨公司 Tracking。
- 原始埋点日志保留约 98 天并自动轮转删除。
- 卸载 App 会移除设备上的安装 ID；已上报事件仍按服务端保留周期自动删除。
- 埋点汇总接口不公开原始安装 ID。

现有“当前版本不使用第三方分析 SDK”可以保留，但必须补充“一方产品分析”说明，不能让
用户误解为 App 完全不发送使用数据。

## 11. 测试设计

### 11.1 ShotMarker 单元测试

安装 ID：

- 首次访问生成符合 `[A-Za-z0-9]{12}` 的 ID。
- 生成值写入指定 `UserDefaults`。
- 后续访问复用相同值。
- 缺失、长度错误或包含非法字符时重新生成。
- 不访问 IDFA 或 IDFV。

请求构造：

- endpoint 固定为 `https://zhangrh.shop/track`。
- HTTP method 为 `GET`。
- `time` 是注入时钟产生的 Unix 毫秒值。
- `project` 等于 `shotmarker`。
- `device_id` 等于注入的安装 ID。
- `event` 等于对应 enum raw value。
- `params` 解码后严格等于 `{}`。
- 特殊字符由 `URLQueryItem` 正确编码。
- 网络失败和非 `204` 响应不会抛到调用方或触发重试。

业务调用点：

- App 组合根只在 Release iPhone 使用真实 tracker，在 Debug 和非 iPhone 平台使用
  no-op。
- payload 导入成功后发送一次 `training_sync_succeeded`。
- payload 解码或导入失败时不发送同步成功事件。
- runner 最终返回 `.completed` 时发送一次 `highlight_generate_succeeded`。
- runner 进度回调、失败、取消或无有效片段时不发送生成成功事件。
- 相册写入且状态持久化成功后发送一次 `highlight_save_succeeded`。
- 相册权限、文件缺失或写入失败时不发送保存成功事件。

隐私清单：

- `plutil` 可解析 `PrivacyInfo.xcprivacy`。
- 清单包含 Device ID 与 Product Interaction。
- 两者 purpose 为 Analytics、linked 为 true、tracking 为 false。
- ShotMarker 主 App target 包含该清单，Watch target 不声明未发生的远程采集。

### 11.2 zhangrh.shop 测试

- JSONL 解析器接受 `project=shotmarker`。
- `project=shotmarker` 查询过滤正确。
- ShotMarker 事件按事件数和安装 ID 去重统计设备数。
- `hub`、`cardgame` 的现有行为不变。
- 未知项目仍被解析器拒绝，查询路由仍返回稳定的 `invalid_project`。
- 路由错误文案列出全部三个合法项目。
- 公开埋点文档包含 ShotMarker 协议和四个事件。
- ShotMarker 隐私页面包含随机安装 ID、一方分析、保留期限和非 Tracking 说明。

### 11.3 验证命令与线上检查

实现阶段需要执行：

- ShotMarker 相关 XCTest 与完整可行测试集。
- ShotMarker iPhone Release build。
- `PrivacyInfo.xcprivacy` plist 校验和产物包含检查。
- `zhangrh.shop` Backend 测试。
- `zhangrh.shop` Frontend 测试与 ShotMarker 隐私内容测试。

线上不发送额外的 `smoke_test` 事件。服务端发布后，通过 TestFlight 安装产生真实
`app_launch`，再查询 1 天 ShotMarker 汇总确认链路。该开发者安装作为正常安装计入统计。

## 12. 上线顺序

1. 在 `zhangrh.shop` 完成项目白名单、测试、埋点文档和 ShotMarker 隐私政策更新。
2. 发布 `zhangrh.shop` Backend 与静态站点，确认新隐私政策可访问。
3. 查询 `project=shotmarker` 的空或现有汇总，确认服务端已经接受新项目。
4. 在 ShotMarker 中加入客户端、调用点、测试和 `PrivacyInfo.xcprivacy`。
5. 在包含埋点的新版本上线前，更新并发布 App Store Connect 隐私回答。
6. 上传 Release/TestFlight 构建，通过真实启动和汇总查询验证链路。
7. 确认四个事件名称、隐私清单、公开政策和 App Store 标签一致后再发布正式版本。

服务端与隐私政策必须先于会发送事件的 App 版本上线，避免新 App 的事件被读取端拒绝，
也避免线上实际数据行为早于公开说明。

## 13. 验收标准

- Release iPhone App 能向现有 `/track` 发送四种固定事件。
- Debug、Preview、单元测试和非 iPhone 平台不会访问生产埋点接口。
- 同一安装在卸载前稳定复用一个 12 位随机安装 ID。
- 上报内容不包含训练、打点、视频、任务、错误或诊断数据。
- 埋点请求失败不改变任何用户可见状态和业务结果。
- `project=shotmarker` 能通过现有汇总接口查询事件数与独立安装数。
- 汇总结果不暴露原始安装 ID。
- `hub` 和 `cardgame` 的采集与查询行为保持不变。
- ShotMarker 主 App 隐私清单、App Store Connect 和公开隐私政策使用一致声明。
- ShotMarker 与 zhangrh.shop 的相关自动化测试和 Release build 通过。

## 14. 已接受取舍

- 即时、无重试的发送方式会丢失部分事件，但不会增加持久化和恢复复杂度。
- 事件可能因重复业务操作或 Watch 重发而重复，但独立安装数仍可用于趋势观察。
- 随机安装 ID 只能代表一次安装，不能代表真实用户或卸载前后的同一设备。
- 当前汇总只能形成近似漏斗，不能回答严格顺序转化或 cohort 留存。
- 默认开启且没有开关能保持产品与实现简单，但必须用清晰、保守的隐私披露补偿信息不对称。
