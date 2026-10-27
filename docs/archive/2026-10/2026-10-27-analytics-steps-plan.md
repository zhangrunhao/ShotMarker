# 手机侧流程埋点 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. 按复核后的接口实施，用户已授权最小方案，无需再次请求批准。

**Goal:** 区分流量来源并观察手机同步、生成、保存的尝试与结果。
**Architecture:** 保持现有业务与采集架构；扩展严格白名单协议、手机侧调用点、现有JSONL查询与统计界面。
**Tech Stack:** Swift / SwiftUI / StoreKit、Nginx、Node24 / Express、React / TypeScript。
**Spec:** [最小增强契约](2026-10-27-analytics-steps-spec.md)

## Global Constraints

- 手表发送侧、业务schema、调度和业务结果不变；只做埋点增强。
- 新字段与事件使用spec中准确拼写；原始业务数据、错误文本和标识不得进入公开结果。
- 兼容旧事件；未知来源不计正式；无终态不计失败；取消与附属错误独立。
- 保留用户未提交改动。不得发布、部署、提交生产事件或修改私有配置。

## Review Focus

- 重复回调/停止后迟到回调：一个操作只产生一个终态，业务停止语义不变。
- Photos已保存而状态写入失败：保留成功，诊断单列。
- 同步导入成功而ACK失败：保留成功，诊断单列。
- 旧或非法扩展字段：未知/拒绝聚合，绝不误计正式。
- 无开始/无结果/冲突和跨窗口样本：不凭空补齐或伪造成功率。

### Task 1: iPhone埋点与调用点

**Files:** ShotMarker/Services/Analytics/*，ShotMarkerServices.swift，PhoneWatchSyncService.swift，HighlightTaskManager.swift，TrainingSessionListView.swift；对应ShotMarkerTests及必要UI测试。
**Interfaces:** 消费spec中的GET字段与事件；产生带专用operation_id的受控事件；保持AnalyticsTracking可测试且业务依赖注入不变。
- [x] 先补分类、请求、同步/生成/保存分支的失败测试，运行并记录预期失败。
- [x] 扩展类型与真实客户端、环境解析和诊断自用开关；模拟器与Debug no-op。
- [x] 在现有业务分支补开始/终态/诊断，关联操作，不改变业务异常传播、成功点与调度。
- [x] 定向测试转绿，跑iPhone单元与UI套件、Release模拟器构建；记录真实命令与限制。
- [x] 自查差异并交独立review；修复实际问题。

### Task 2: 统计服务与页面

**Files:** zhangrh.shop/backend/projects/track*.js、backend/tools/track*.test.mjs、frontend/project/analytics/*、公开Nginx示例及ShotMarker隐私页。
**Interfaces:** 消费spec扩展JSONL字段，保留旧/api/track/trend响应；新增/api/track/shotmarker及来源过滤；响应不含原始标识。
- [x] 先跑既有测试，再补来源分类、配对/去重/异常样本和新旧兼容失败测试。
- [x] 扩展读取与受限查询，加入聚合路由、Nginx接收配置示例，不动生产。
- [x] 页面加入来源/版本过滤和简单步骤表，测试空态/错误/切换条件，兼容单并发。
- [x] 使用Node24运行npm run check；准备本地可验证样例和部署顺序说明。
- [x] 自查差异并交独立review；修复实际问题。

### Task 3: 集成、记录与交付

**Files:** 两仓库docs/current、docs/README、同topic spec/plan及验证归档。
- [x] 用相同受控样例交叉核对Swift请求字段与Node解析；确认业务与Watch改动边界。
- [x] 验证文档链接、current行数、git diff --check；记录未部署及真机渠道待验收。
- [x] 更新current后归档已完成spec/plan；不把未执行验收写成通过。
- [x] 完整review后交付代码位置、验证结果和上线前剩余步骤。


## 完成与验证（2026-10-27）

本地实施完成，未提交、部署、上传 App 或写入生产事件。ShotMarker 基线为 `2f1a31b`，网站基线为 `fda0d1a`，均在独立 `codex/analytics-steps` 工作区完成。原目录已有未提交分析文档保留。

### 最终结果

| 范围 | 已验证结果 |
| --- | --- |
| iPhone 最终源码 | iPhone 17 Pro / iOS 26.5 Simulator：511 完整单元 + 1 新诊断 UI，共 512 通过，0 失败/0 跳过；最终命令成功且独立 xcresult 有效 |
| 既有 UI | 本轮较早源码执行既有任务 7、审核 6、媒体 7、时间轴 4，共 24 项均通过；此后源码改动限于埋点终态仲裁。不能宣称一次命令执行了 536 项并全部成功 |
| 生成边界 | 两项独立审查发现均先以 gate 回归复现再修复；聚焦 27 项通过，复审关闭两项 P2，未发现新增阻塞 |
| 最终 Release | generic iOS Simulator 增量构建退出 0；不替代正式签名 Archive |
| 网站完整检查 | 实际 Node.js v24.19.0：`npm run check` 通过，根 9 + 前端 188 + 后端 25 = 222 项；lint、TypeScript 与五站生产构建通过 |
| 网站定向检查 | Analytics 27 项通过，含默认测试发现不执行的既有 TSX 文件；新增测试使用 `.test.ts` 纳入默认检查 |
| 跨仓字段 | 编译实际 Swift 客户端请求构造代码，15 类事件与 Nginx 示例字段集合及 Node 24 解析、正式来源/版本过滤一致；全部虚构数据，没有网络发送 |
| 页面 | 本地虚构数据核对来源/版本切换、三流程计数与中文诊断，浏览器未见 error/warn；未发布页面 |
| 审查与记录 | 服务源码独立审查通过；iPhone 修复复审通过；跨仓文档旧隐私日期已改为本地 10 月更新并明确未部署 |

### 修复与验收边界

- 分发查询只在埋点发送 Task 内等待共享解析，不阻塞业务服务初始化。同一操作保持来源与自用快照。
- 生成关联在安装 execution 的 await 前建立，后台停止依据 Store 实际返回的停止结果完成埋点，避免旧列表缓存漏取消。
- 终态依据持久化返回仲裁；停止进行时只在遥测内存暂存已知失败，停止成功记取消、停止失败释放实际失败。没有改变业务 Store、异常传播或调度顺序。
- 诊断 UI 首轮点击定位断言失败，改为命中开关位置后通过；首轮并行验证还遇到结果缓存/构建锁错误，不将该首轮命令整体记为成功。最终检查已顺序执行并使用独立结果包。
- 本轮覆盖了 511 单元与 25 个不同 UI 用例，但既有 24 UI 与最终新增 UI 分属上述不同运行及源码范围。
- 最终检查使用真正 Node 24；早期探索的同名运行时路径实际指向其他版本，未将早期结果冒充 Node 24 验收。
- 本机没有 Nginx，未执行 `nginx -t`；字段集合与解析检查不替代实际接收/落盘。真实 App Store、TestFlight、Release 真机及生产端到端仍未验收。
- 未运行本次 SwiftLint；既有违规基线仍见质量状态。新增 receipt 辅助判断有弃用 API 提示；构建成功不等于零警告。

### 发布顺序

后续获得发布授权后，先部署兼容新旧记录的 Backend，再合并并验证 Nginx 扩展接收格式，随后发布 Analytics/隐私页面，最后发布新版 iPhone。旧记录不回填，Watch 发送前和未送达手机的路径仍不可见。此次实现不包含上述外部发布步骤。
