# 片段编辑精简实施计划

日期：2026-10-23
状态：实施中，依据用户明确五项调整要求。

**Goal:** 简化手机片段编辑并支持带符号的打点前后范围。
**Architecture:** 编辑页仅调整展示与入口；`ClipSettings` 提供共享有效性和范围文案，配置、规划、持久化共同使用，正常任务写入 schema 3。
**Tech Stack:** SwiftUI、AVFoundation、XCTest，不新增依赖。
**Spec:** [范围与边界](2026-10-23-clip-editor-simplify-spec.md)。

## Global Constraints

- 用户修改不可覆盖，使用已附加隔离工作树与 `codex/clip-editor-simplify`。
- UI 精简与 signed offsets 按独立文件并行；所有 xcodebuild 串行，最终完整套件由控制者执行。
- 低影响删除/文字布局使用既有 UI 回归与目视检查，不新增镜像实现的测试；有符号计算/存储边界先测试后实现。
- 保留已确认片段、取景、源范围与事务契约；无新 epoch，无远端推送、发布或自动删除用户数据。

## Review Focus

- 正常及 accessibility5 下固定底栏挤压内容：实际可见区域断言与截图。
- 负数被任一路径截断或拒绝：模型、配置、任务存储、执行快照往返与真实控件输入。
- 无效区间在进入审核后才失败：配置明确反馈、入口禁用及服务防线。
- 新默认窗口完全移出源时误删已确认范围/取景：配置协调和入口可用性测试。
- 旧客户端把新负值文档误判损坏：schema3保护及1/2读取无变化测试。

### Task 1: 编辑界面精简

**Files:** `Views/HighlightClipEditorView.swift`、`HighlightClipReviewView.swift`、`HighlightClipReviewNavigationView.swift`，必要的 DEBUG 媒体/确认 harness，`ShotMarkerUITests/HighlightClipConfirmationUITests.swift`、`HighlightClipMediaNavigationUITests.swift`。

- [ ] 删除继承提示、两页决定提示与撤销入口、恢复默认范围按钮及对应仅 UI 使用的代码；保留底层加载保护与现有取景功能。
- [ ] 四列时间替换为 `.caption` / monospaced 的片段内进度与总长，进度限制在0…duration；时间轴仍支持起止值的可访问性。
- [ ] 改写依赖被删除入口的已有 UI 测试，验证通过底部重开修改决定及迟到媒体隔离，不用隐藏测试按钮恢复已移除的产品入口。
- [ ] 运行相关 UI；检查正常/最大字体 screenshot，主要按钮完整可达；中文提交。

### Task 2: 有符号默认范围与兼容存储

**Files:** `Models/ClipSettings.swift`、`Services/HighlightTaskValidation.swift`、`HighlightTaskStore.swift`、`HighlightTaskPlanner.swift`、必要的默认规划入口，`Views/TrainingSessionHighlightView.swift`（新建与修改共享配置页），相关 Settings/Planner/Store/Review 测试与配置 UI harness/tests。

**Interface:** `ClipSettings.isValidRange` 检查 -20…20 有限值且 before+after>=1；共享相对范围说明属性由配置展示消费，不修改数值。默认规划保持 marker-before 到 marker+after。

- [ ] 添加并运行 signed offset/无效区间/确认保留/schema3 的失败测试。
- [ ] 共用有效性、放开两侧 Stepper 为 -20…20，展示明确的实际区间；无效时禁用进入审核/配置提交，服务也拒绝，不静默归一化。
- [ ] 默认窗口完全不相交时保留旧确认和旧合法基线；配置可用性考虑最终协调结果，未确认项按新默认规划。
- [ ] 任务读取1/2/3，正常写3，兼容文件读取/no-op保持；新增真实持久化和负值快照断言。
- [ ] 跑相关单元及实际配置 UI 控件回归；中文提交。

### Task 3: 整体验证与文档

- [ ] 一次完整 iPhone suite，专用已启动 Simulator，`-parallel-testing-enabled NO -collect-test-diagnostics never`，唯一结果包与日志。
- [ ] 独立审查完整变更并修正实际问题；最终 current 记录有效行为与验证边界。
- [ ] current更新后归档spec/plan与验证记录，检查链接/300行/文本差异，中文提交。
