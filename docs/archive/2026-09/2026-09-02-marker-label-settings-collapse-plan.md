# 片段序数样式默认收起 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让片段序数样式区域每次进入页面时默认收起，同时保留现有本地样式数值与位置恢复行为。

**Architecture:** 在 `TrainingSessionHighlightView` 中用一个仅存在于当前页面生命周期的布尔状态驱动系统 `DisclosureGroup`。设置内容继续绑定现有 `clipSettings.markerLabelStyle`，持久化仍由 `ClipSettingsStore` 和页面现有 `.onChange` 完成，不增加数据模型或存储迁移。

**Tech Stack:** Swift 5 language mode、SwiftUI、XCTest、UserDefaults、Xcode 26.6

**Spec:** `docs/archive/2026-09/2026-09-02-marker-label-settings-collapse-spec.md`

## Global Constraints

- 直接在 `main` 实现，不创建分支或 worktree。
- 保留已有未提交的 `docs/README.md` 与 `docs/changes/2026-08-21-app-store-1-2-submission-plan.md`，不得纳入本变更提交。
- 展开状态不持久化；每个新的 `TrainingSessionHighlightView` 默认收起。
- 样式数值和位置继续使用现有 `ClipSettingsStore` 本地持久化。
- 不新增依赖、存储键、Analytics 事件或远端字段。
- 本次 UI 状态按用户确认采用 Simulator 人工验证，不引入 UI Test 框架。
- 完成后先更新 `docs/current/`，再将本 spec 和 plan 移入 `docs/archive/2026-09/`。

---

### Task 1: 记录并验证现有样式持久化基线

**Files:**

- Verify: `ShotMarker/Models/ClipSettings.swift`
- Verify: `ShotMarkerTests/ClipSettingsStoreTests.swift`

**Interfaces:**

- Consumes: `ClipSettingsStore.save(_:)` 与 `ClipSettingsStore.load()`
- Preserves: `ClipSettings.markerLabelStyle` 的五个字段完整往返

- [x] **Step 1: 运行聚焦存储测试**

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/ClipSettingsStoreTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `ClipSettingsStoreTests` 全部通过，其中 `testStoreSavesAndRestoresNormalizedStyle` 证明字号、横纵位置和两种不透明度能由本地恢复。

- [x] **Step 2: 确认不需要修改持久化实现**

检查 `TrainingSessionHighlightView` 的 `clipSettings` 初始化和 `.onChange(of: clipSettings)`。Expected: 页面从共享 store 加载，任一样式绑定变化都会保存完整设置，因此本任务不修改模型或 store。

### Task 2: 默认收起片段序数样式

**Files:**

- Modify: `ShotMarker/Views/TrainingSessionHighlightView.swift`

**Interfaces:**

- Consumes: `$clipSettings.markerLabelStyle`
- Produces: 页面生命周期内的 `isMarkerLabelSettingsExpanded: Bool`
- Preserves: `MarkerLabelSettingsView` 的初始化参数与现有禁用行为

- [x] **Step 1: 加入页面级默认收起状态**

在其他 `@State` 属性旁加入：

```swift
@State private var isMarkerLabelSettingsExpanded = false
```

- [x] **Step 2: 用 DisclosureGroup 包裹现有设置视图**

将 `markerLabelSettingsSection` 的内容改为：

```swift
Section("片段序数") {
    DisclosureGroup(
        "样式调整",
        isExpanded: $isMarkerLabelSettingsExpanded,
    ) {
        MarkerLabelSettingsView(
            thumbnailData: firstSelectedItem.thumbnailData,
            previewLabel: plan.segments.first?.markerLabel ?? "1/1",
            isDisabled: isCreatingHighlightJob,
            style: $clipSettings.markerLabelStyle,
        )
    }
}
```

Expected: 新页面初值为收起；展开和收起不会替换 `clipSettings` 绑定。

- [x] **Step 3: 执行聚焦编译与存储回归**

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/ClipSettingsStoreTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: 编译成功且 `ClipSettingsStoreTests` 全部通过。

- [x] **Step 4: 提交功能代码**

```bash
git add ShotMarker/Views/TrainingSessionHighlightView.swift
git commit -m "feat: 默认收起片段序数样式设置"
```

Expected: 提交仅包含 `TrainingSessionHighlightView.swift`。

### Task 3: 完整验证并维护当前文档

**Files:**

- Modify: `docs/current/product.md`
- Modify: `docs/current/architecture.md`
- Modify: `docs/current/quality.md`
- Move: `docs/changes/2026-09-02-marker-label-settings-collapse-spec.md` → `docs/archive/2026-09/2026-09-02-marker-label-settings-collapse-spec.md`
- Move: `docs/changes/2026-09-02-marker-label-settings-collapse-plan.md` → `docs/archive/2026-09/2026-09-02-marker-label-settings-collapse-plan.md`

**Interfaces:**

- Records: 当前产品行为、视图状态边界与本次验证证据
- Preserves: 每份 `docs/current/` 文件不超过 300 行

- [x] **Step 1: 运行完整 iPhone 测试**

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: ShotMarker iPhone 测试 0 失败。

- [x] **Step 2: 运行 Release Simulator 构建**

```bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: 在 iOS Simulator 检查交互**

选择一个已有训练和视频，核对规格中的验收标准 1–4。Expected: 默认收起；展开后可调整；同页收起再展开不丢状态；重新进入仍收起且恢复本地样式。若 Simulator 没有可用训练或视频，只记录未完成项，不推断通过。

Result: 模拟器存在训练、视频及已保存的非默认样式，但系统 PhotosPicker 加载完成后没有向当前电脑控制接口暴露可操作的视频元素，未完成选择流程；本步骤保持未勾选。

- [x] **Step 4: 更新 current 文档并归档 Change**

在 `product.md` 记录默认收起与样式恢复行为；在 `architecture.md` 记录展开状态仅为页面状态且不持久化；在 `quality.md` 只记录本次实际完成的自动和人工验证。随后用 `apply_patch` 将 spec 和 plan 移入 `docs/archive/2026-09/`。

- [x] **Step 5: 执行文档与差异检查**

```bash
wc -l docs/current/*.md
git diff --check
git status --short
```

Expected: current 文件均不超过 300 行，`git diff --check` 退出码为 0，用户原有两项改动仍保持原状态。

- [x] **Step 6: 提交文档与归档**

```bash
git add \
  docs/current/product.md \
  docs/current/architecture.md \
  docs/current/quality.md \
  docs/archive/2026-09/2026-09-02-marker-label-settings-collapse-spec.md \
  docs/archive/2026-09/2026-09-02-marker-label-settings-collapse-plan.md
git commit -m "docs: 记录片段序数设置收起状态"
```

Expected: 提交不包含用户原有的 `docs/README.md` 或 App Store 计划。

- [x] **Step 7: 复核最终范围**

```bash
git status --short
git log -3 --oneline
git show --stat --oneline HEAD~1..HEAD
```

Expected: 工作区只保留用户原有两项改动；本需求的功能和文档提交位于 `main`。
