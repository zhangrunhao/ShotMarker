# 维护后真机追加验收

- 日期：2026-10-25。
- 起始代码：`322ba2b`，包含此前维护提交 `2fa8049`；本轮最终生产代码：`3b8a3be`。
- 用户要求真机验收后合并 main。本记录只保存公开实现与验证摘要，不作为完整真机全功能通过声明。
- 验收结论：iPhone 限定回归通过，Watch 真机仍因调试连接失败而未完成。
- 真实硬件、设备过程及私有外部证据由[独立私有台账](../../private.local/shotmarker/current/release.md)维护；公开仓库不记录设备标识或复制详细硬件过程。

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

## 未验证与外部边界

- 本轮未验真实 Photos 授权/保存、HealthKit、完整真机全功能、Watch 联机升级、iPad 全功能、VoiceOver 人工朗读、HDR/广色域、正式 Archive 或线上 Analytics/GlitchTip。
- 商店、TestFlight、审核和上线状态最后核验日期仍沿用[发布状态](../../current/release.md)，本轮不推断其变化。
- 最终合并状态：尚未合并；等待完成 Watch 验收或用户明确采用已通过的 iPhone 验收范围。
