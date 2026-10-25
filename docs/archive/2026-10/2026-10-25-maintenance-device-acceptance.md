# 维护后真机追加验收

- 日期：2026-10-25。
- 起始代码：`322ba2b`，包含此前维护提交 `2fa8049`；本轮最终生产代码：`3b8a3be`。
- 用户要求真机验收后合并 main。本记录只保存公开实现与验证摘要，不作为完整真机全功能通过声明。
- 验收结论：iPhone 限定回归通过，Watch 真机仍因调试连接失败而未完成。
- 本页记录脱敏后的设备环境、执行结果和限制；原始设备标识、签名身份、账号信息及真实业务内容不进入文档。

## 实现事实与处理

真机流程发现，合法任务目录使用系统 `/private/var` 与 `/var` 路径别名时，已存在根目录和未创建目标采用不同归一化表示，导致 `HighlightTaskFileStore` 误判 `invalidPath`。修复先解析并规范受信根目录，再从同一根目录派生目标路径，保留逐段符号链接和最终越界检查。新增 prepare/commit 真实字节回归，修复前 1 项以 `invalidPath` 失败，修复后 FileStore 5 项通过。

DEBUG 验收入口在 preparation 失败时显示可见错误，临时路径探针与编码诊断全部移除。首轮真机 23 项 UI 中 21 项通过、2 项失败；失败与测试辅助逻辑对步进控件可点击性、以及仅在序号模式执行滚动的假设有关。修正测试辅助逻辑，没有调整产品布局；后续仅按实际执行的受影响范围记录复验，不把不同批次数量相加作为完整套件结果。

## 最终验证摘要

| 范围 | 结果 | 代码和边界 |
| --- | --- | --- |
| iPhone Simulator 完整生产代码回归 | 492 单元 + 24 UI 共 516 项通过，0 失败 | `3b8a3be`；最终跳过统计：0；全套执行后仅调整测试辅助滚动和清理 fixture，随后完成上述定向复验；生产源码一致；结果包 `simulator-final.xcresult` |
| 测试辅助修改定向复验 | Simulator 的 FileStore 5 项和受影响 UI 8 项共 13 项通过；真机受影响 UI 8 项通过，均 0 失败/跳过 | `3b8a3be` 最终测试源码；`simulator-test-fixes.xcresult`、`stepper-media-green.xcresult` |
| 真机限定 UI 汇总 | 首轮 23 项中 21 项通过；修正测试滚动后，受影响的 8 项全部通过（包含原 2 项失败），覆盖 23 个不同用例；未执行请求真实 Photos 授权的 1 项 | 首轮与修正后的定向范围分别保留，不声称完整真机全功能完成 |
| 真机隔离 host 单元及真实视频导出 | 43 项通过，0 失败/跳过；包含真实视频生成、修改后重新生成、旧输出替换与重新加载 | `3b8a3be`；隔离 DEBUG 宿主和文件夹；结果包 `iphone-isolated-core.xcresult`；不代替真实 Photos 或 HealthKit 授权验收 |
| Release Simulator 增量构建 | 退出 0；DEBUG 验收入口不进入 Release | Simulator 产物，不是分发 Archive |
| 严格签名验证 | 退出 0 | `3b8a3be` 的开发签名 iPhone Debug App 1.3（3）；不据此推断正式 Archive 状态 |
| 生产源码 SwiftLint | 149 项：120 warning / 29 error，未增加 | 未放宽规则；静态检查仍未通过 |
| 代码审查 | 未发现必须修复的问题 | `3b8a3be` 全部生产、测试及架构文档差异 |
| Watch 本轮范围与结果 | 尝试真机 runtime 回归，连接尚未恢复；三次完整连接尝试均在测试启动前超时，0 项执行；不能记为通过 | 未执行或未通过的范围必须明确保留；旧 40 项 Simulator 基线不替代真机联机验收 |
| 公开文档与文本检查 | 本地路径、current 行数、归档月份和文本差异已完成检查 | 本地目标、可选私有链接边界、current 行数和归档月份分别检查 |

本地追加日志与结果包根目录为 `/tmp/shotmarker-device-20261025/`；它们不进入 Git。测试摘要不包含真实设备详细标识。

## 设备环境与执行证据

### iPhone

- 环境：iPhone 16 / iOS 26.6.1，USB 连接，开发者模式启用；Xcode 27.1（27A9275）。用户已确认解锁并知悉自动操作 App。
- generic iOS Debug 构建通过，随后物理 destination 测试构建通过。最终 App 的严格签名验证退出 0。全新派生目录直接 build-for-testing 首次因缺少 TEST_HOST 失败；先完成普通 App 构建后测试构建成功，没有更改签名配置。
- 首次物理 UI 测试的任务 fixture 初始化失败触发 DEBUG 断言；之后可见诊断确认本文路径别名问题。UI 首轮的另一失败原因是实际 Increment 按钮位于导航栏上方而父 Stepper 仍报告可点击，媒体辅助滚动仅处理序号模式。修正实际按钮完整可见检查和按几何滚动后，1 项范围恢复与 7 项媒体导航通过，包含原两项失败；不是一次完整 23 项零失败运行。
- 未运行 `testCompletedTaskOpensConfigurationAndDeletionRequiresConfirmation`：其 PhotoKit 来源 fixture 会申请真实 Photos read/write 权限；该项仍在 Simulator 全套通过。
- 43 项隔离宿主测试的分布为 FileStore 5、MediaIntegration 1、Playback 19、Bootstrap 3、AppLogStore 10、Reset 5。使用同目录复制的 xctestrun，仅启用目标，并设置 `SHOTMARKER_UI_TEST_TIMELINE=1` 避免启动真实 bootstrap；文件和偏好使用隔离 fixture。真实硬件完成 41 秒合成片生成、修改排除/取景后 26 秒重新生成、旧输出保留及替换、持久化重载与临时输出清理。
- 媒体测试使用共享日志实例，可能写入或清理日志，不修改真实 Photos 或 HealthKit。现有 `training-sessions.json` 与 `highlight-tasks.json` 在测试前、测试后、正常启动后三次 SHA-256 及字节数相同；核验仅保留一致性摘要，临时业务文件副本立即删除，不记录数据或用户标识。结论不扩大为整个沙盒零写入。
- 最后使用空业务参数、无测试环境变量、`startStopped=false` 正常前台启动，并确认同一进程随后仍在运行。Device Hub 屏幕共享要求 iOS 27 以上，此设备没有通过该入口完成正常首页视觉检查；UI 证据来自 XCTest，不等同人工全流程验收。

### Watch

- 环境：Apple Watch Series 8 / watchOS 26.6，系统显示已配对且开发者模式启用。用户确认解锁及手机连接，随后将 Watch 放到 Mac 旁并开启 Wi-Fi/蓝牙；Mac Wi-Fi 也已核验开启。
- devicectl 显示调试服务不可用及 tunnel disconnected；三次完整 Xcode destination 连接均在测试启动前超时，退出 70。最后底层错误为 `CoreDeviceError 4000` / `RemotePairingError 1001`，表示协商网络参数建立通道超时。Device Hub 曾提示需要靠近 Mac，靠近后仍未建立稳定调试通道。
- 未解除配对、重置 Watch 或变更开发权限/安全设置。本轮 0 项执行，应记为连接限制，不记为断言失败或验收通过；用户最终接受的合并范围见文末。

### 临时证据索引

以下均位于 `/tmp/shotmarker-device-20261025/`，可能被系统清理，不进入 Git：

- `iphone-ui-fixed.xcresult`：首轮 21/23；`stepper-probe.xcresult`：步进可见性 RED；`stepper-media-green.xcresult`：最终 8/8。
- `iphone-isolated-core.xcresult`：43/43；`signing-final.log`、`artifact-final-summary.json`：开发签名及版本摘要。
- `business-hashes-before.json`、`business-hashes-after-tests.json`、`business-hashes-after-launch.json`：三个时点的业务文件一致性摘要；不复制真实内容或原始摘要值。
- `normal-launch.json`、`normal-processes.json`：正常启动及同一进程存活。
- `watch-device-test.log`、`watch-device-retry.log`、`watch-device-nearby.log`、`watch-apps-nearby.log`：连接失败的本地原始证据；不将其中设备值复制到文档。

## 未验证与外部边界

- 本轮未验真实 Photos 授权/保存、HealthKit、完整真机全功能、Watch 联机升级、iPad 全功能、VoiceOver 人工朗读、HDR/广色域、正式 Archive 或线上 Analytics/GlitchTip。
- 商店、TestFlight、审核和上线状态最后核验日期仍沿用[发布状态](../../current/release.md)，本轮不推断其变化。
- 最终合并状态：2026-10-25，用户明确采用已通过的 iPhone 验收结果合并 main；维护分支已快进合并，合并点为 `2f54a80`。合并后的生产、测试和构建配置与已验收 `3b8a3be` 一致；后续仅更新本次验收决定与合并记录，不重复运行未变化的测试。本次未推送远端。
