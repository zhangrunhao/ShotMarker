# ShotMarker 项目进度状态页实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有项目进度快照重写成可信的内部状态页，并让后续 Codex 在每个功能或重要修复完成后持续维护它。

**Architecture:** `docs/current-codebase-status.md` 是唯一的项目状态来源，保存当前结论、验证结果、风险、下一步和少量近期进展；Git 历史保存更早记录。`AGENTS.md` 只保存更新触发规则和事实口径，不复制具体项目状态。

**Tech Stack:** Markdown、Git、Xcode `xcodebuild`、`xcresulttool`、`plutil`、ripgrep

---

## 文件结构

- Modify: `docs/current-codebase-status.md` — 当前项目状态的唯一来源。
- Modify: `AGENTS.md` — 告诉后续 Codex 何时以及按什么证据更新状态页。
- Reference: `docs/superpowers/specs/2026-08-16-project-status-document-design.md` — 已批准的结构和验收标准。

本任务不新增生成脚本或第二份状态文档。项目是个人项目，所有工作直接在 `main` 上完成，不创建分支或 worktree。

### Task 1: 建立可复核的当前基准

**Files:**

- Read: `docs/current-codebase-status.md`
- Read: `docs/PRD.md`
- Read: `docs/superpowers/specs/2026-08-16-glitchtip-crash-reporting-design.md`
- Read: `docs/superpowers/specs/2026-08-16-shotmarker-analytics-design.md`
- Read: `docs/superpowers/specs/2026-08-16-project-status-document-design.md`
- Read: `ShotMarker.xcodeproj/project.pbxproj`
- Read: `ShotMarker/PrivacyInfo.xcprivacy`

- [ ] **Step 1: 确认允许编辑的 Git 基准**

Run:

```bash
git branch --show-current
git status --short
git rev-parse --short HEAD
```

Expected: branch is `main`. If the status output contains user work, preserve it and do not stage or rewrite those paths. Record the HEAD shown here as the status page baseline.

- [ ] **Step 2: 收集上次状态页之后的重要仓库事实**

Run:

```bash
git log --date=short --pretty=format:'%h %ad %s' --max-count=30
rg -n "GlitchTipCrashReporter.start|tracesSampleRate = 0|AnalyticsRuntimePolicy|analytics.track|NSPrivacyCollectedDataType" \
  ShotMarker ShotMarkerTests Config
rg -n "MARKETING_VERSION|CURRENT_PROJECT_VERSION|DEBUG_INFORMATION_FORMAT" \
  ShotMarker.xcodeproj/project.pbxproj
```

Expected: evidence exists for GlitchTip startup with performance disabled, four-event analytics wiring, Release-iPhone-only analytics policy, the app privacy manifest, version `1.1`, and Release dSYM generation.

- [ ] **Step 3: 验证 Privacy Manifest**

Run:

```bash
plutil -lint ShotMarker/PrivacyInfo.xcprivacy
plutil -p ShotMarker/PrivacyInfo.xcprivacy | rg \
  "DeviceID|ProductInteraction|PurposeAnalytics|UserDefaults|CA92.1|FileTimestamp|C617.1"
```

Expected: plist lint succeeds and the approved collected-data and required-reason entries are present.

- [ ] **Step 4: 运行当前代码的全量 iPhone 测试**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ShotMarker-ProjectStatus-Tests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`. Preserve the `.xcresult` path printed by Xcode, then obtain the exact totals with:

```bash
SHOTMARKER_STATUS_XCRESULT="$(find /tmp/ShotMarker-ProjectStatus-Tests/Logs/Test -maxdepth 1 -name '*.xcresult' -print | sort | tail -n 1)"
test -n "$SHOTMARKER_STATUS_XCRESULT"
xcrun xcresulttool get test-results summary \
  --path "$SHOTMARKER_STATUS_XCRESULT" \
  --format json
```

Expected: result is `Passed`, with zero failed tests. Record the exact passed, failed and skipped counts in the status page.

- [ ] **Step 5: 运行当前代码的无签名 Release 构建**

Run:

```bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/ShotMarker-ProjectStatus-Release \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`, and both paths exist:

```bash
test -d /tmp/ShotMarker-ProjectStatus-Release/Build/Products/Release-iphoneos/ShotMarker.app
test -d /tmp/ShotMarker-ProjectStatus-Release/Build/Products/Release-iphoneos/ShotMarker.app.dSYM
```

### Task 2: 重写唯一项目状态页

**Files:**

- Modify: `docs/current-codebase-status.md`

- [ ] **Step 1: 用已批准的固定结构替换过期快照**

Rewrite the document with these exact top-level sections:

```markdown
# ShotMarker 当前项目进度

## 1. 文档元数据
## 2. 总体状态
## 3. 已完成功能
## 4. 正在进行的工作
## 5. 测试与构建状态
## 6. 风险与待确认事项
## 7. 下一步优先级
## 8. 发布前检查项
## 9. 最近进展
## 10. 维护规则
```

The content must state these evidence-backed conclusions:

- iPhone 与 Apple Watch 的训练打点、同步、视频选择、集锦任务、生成、播放和保存主链路已经具备。
- GlitchTip 原生崩溃捕获能力已接入，并会转发 `logger.error`；用户在 2026-08-16 确认 Project 4 已显示验证事件和业务错误事件；性能监控关闭；真机原生崩溃仍待发布前验证。
- 最小埋点客户端已实现四个固定事件，并且只在 iPhone Release 构建启用；生产端到端统计验证仍等待埋点整体工作完成和下一次发布。
- `PrivacyInfo.xcprivacy` 已声明分析数据与必需原因 API，是否满足最终 App Store Connect 回答仍需发布前人工核对。
- dSYM 自动上传、下一次 Archive、真机崩溃验证与 TestFlight 发布暂缓，待埋点整体完成后统一执行。
- 仓库能确认版本配置和历史发布提交，但当前 App Store 审核或线上状态未重新验证，不能沿用旧文档中的 `Waiting for Review`。
- Task 1 得到的实际测试总数、失败数、构建结果、日期和基准提交必须原样记录。

Keep the recent-progress list to the latest 5–10 important milestones. Include the GlitchTip integration, analytics client, privacy manifest, status-document design, and any newer completed work discovered in Task 1.

- [ ] **Step 2: 删除或改写所有已过期结论**

Run:

```bash
rg -n "2026-06-16|2eaa62a|Waiting for Review|当前最重要的事项不是继续开发" \
  docs/current-codebase-status.md
```

Expected: no output. Historical facts may only remain if explicitly labeled with their historical date and relevance; the initial migration should not need them.

- [ ] **Step 3: 验证固定结构和关键状态**

Run:

```bash
rg -n '^## [1-9]\\.|^## 10\\.' docs/current-codebase-status.md
rg -n "GlitchTip|logger.error|性能监控|埋点|PrivacyInfo.xcprivacy|dSYM|Archive|真机|TestFlight|未确认" \
  docs/current-codebase-status.md
git diff --check
```

Expected: all ten sections appear once, every required project area is represented, and the diff has no whitespace errors.

- [ ] **Step 4: 提交当前状态页**

Run:

```bash
git add -- docs/current-codebase-status.md
git diff --cached --check
git commit -m "docs: 更新 ShotMarker 当前项目进度"
```

Expected: one `docs:` commit containing only `docs/current-codebase-status.md`.

### Task 3: 让后续任务持续维护状态页

**Files:**

- Modify: `AGENTS.md`

- [ ] **Step 1: 增加状态页维护规则**

Append these rules under `## Development Rules`:

```markdown
- Treat `docs/current-codebase-status.md` as the single source of truth for current project progress.
- After completing a feature or important bug fix, update that status page with the new state, verification scope, risks, and next step.
- Record only evidence-backed test, build, release, and external-service results; mark changing external state as unverified unless it was checked in the current task.
```

- [ ] **Step 2: 验证规则没有复制具体状态或覆盖现有约束**

Run:

```bash
rg -n "single source of truth|After completing a feature|evidence-backed" AGENTS.md
rg -n 'directly on `main`|Do not create or use git worktrees|Never discard' AGENTS.md
git diff --check
```

Expected: all three maintenance rules and all existing branch/worktree/change-preservation rules remain present.

- [ ] **Step 3: 提交维护规则**

Run:

```bash
git add -- AGENTS.md
git diff --cached --check
git commit -m "docs: 规定项目进度文档维护方式"
```

Expected: one `docs:` commit containing only `AGENTS.md`.

### Task 4: 最终审计

**Files:**

- Verify: `docs/current-codebase-status.md`
- Verify: `AGENTS.md`

- [ ] **Step 1: 对照设计规格检查覆盖范围**

Run:

```bash
test -f docs/current-codebase-status.md
test -f docs/superpowers/specs/2026-08-16-project-status-document-design.md
rg -n "更新时间|基准|总体状态|已完成功能|正在进行|测试与构建|风险|下一步|发布前|最近进展|维护规则" \
  docs/current-codebase-status.md
```

Expected: the status page covers every section required by the approved design.

- [ ] **Step 2: 检查秘密和夸大结论**

Run:

```bash
! rg -n "SENTRY_AUTH_TOKEN[[:space:]]*=|token[[:space:]]*[:=][[:space:]]*[[:alnum:]]{16,}|Apple.*password[[:space:]]*=|BEGIN.*PRIVATE KEY" \
  docs/current-codebase-status.md AGENTS.md
rg -n "全量测试|Release 构建|未确认|暂缓" docs/current-codebase-status.md
```

Expected: no secret appears. Every success statement corresponds to Task 1 evidence, while external or deferred work is explicitly labeled.

- [ ] **Step 3: 确认提交和工作区边界**

Run:

```bash
git log -3 --oneline
git status --short
```

Expected: the status-page and AGENTS commits are present. A clean worktree is ideal; if unrelated user changes appeared, they remain unstaged and are reported without modification.
