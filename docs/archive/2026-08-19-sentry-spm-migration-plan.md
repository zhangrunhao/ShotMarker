# SentrySPM 源码依赖迁移实施计划（已完成）

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Do not dispatch subagents unless the user explicitly requests delegation.

**Goal:** 把 iPhone target 的 Sentry 9.26.0 从预编译 `Sentry-Static` 切换为官方源码产品 `SentrySPM`，重新完成自动化测试、正式 Archive、dSYM/UUID 检查和 App Store Connect Validate，并消除 `Upload Symbols Failed` 警告。

**Architecture:** Swift Package Manager 仍负责依赖解析，但包来源从 `sentry-apple-binaries` 改为 `sentry-cocoa`，由 Xcode 在本机构建 `SentrySPM`。实际源码产品导出 `SentrySwift` module，因此经用户确认后只调整两个导入语句；GlitchTip DSN、错误上报器行为和隐私边界保持不变，Watch target 不链接 Sentry。

**Tech Stack:** Xcode 26.6、Swift 5 language mode、Swift Package Manager、Sentry Cocoa 9.26.0、XCTest、`xcodebuild`、`dwarfdump`、Xcode Organizer。

**Spec:** 本文的“范围与约束”“验收标准”和“根因证据”章节是本计划实施的内嵌规格；用户要求只创建这一份变更文档。

## Global Constraints

- 所有开发直接在 `main` 进行，不创建 branch 或 worktree。
- 实施前必须重新确认当前分支是 `main`。
- `ShotMarker.xcodeproj/project.pbxproj` 已有用户未提交修改；必须保留版本 `1.2`、Build `1` 和用户已有的平台配置调整，不得覆盖或回退。
- Sentry 版本保持 `9.26.0`，本次只改变包来源和产品形态。
- 只把 `SentrySPM` 链接到 `ShotMarker` iPhone target；不得添加到 `ShotMarkerWatchApp`。
- 不修改现有 GlitchTip DSN、事件字段、隐私策略或上报行为。
- 不上传 TestFlight，不提交 App Store 审核，不上传 dSYM 到 GlitchTip，不修改任何线上服务。
- 可以执行 App Store Connect Validate，但验证完成后必须停止，不进入 Upload 流程。
- 不把 Apple 凭据、Token、DSN 实际值、设备 UDID 或测试人员信息写入文档或 Git。
- 任何测试、Archive、Validate 和 UUID 结论都必须来自本次实际执行结果；失败时记录真实失败，不得沿用旧结论。

---

## 范围与约束

### 包含

- SwiftPM 包地址和产品引用迁移。
- Sentry/GlitchTip 相关回归测试以及 iPhone、Watch 完整测试。
- Release 构建和带签名的正式 iOS Archive。
- App、Watch App 以及可能存在的嵌入式 Sentry 二进制的 UUID/dSYM 对应检查。
- Xcode Organizer 的 Validate App。
- 根据真实结果更新公开当前文档；正式 Archive 私有事实仅在私有仓库完成同步后记录。

### 不包含

- TestFlight 或 App Store 上传。
- GlitchTip dSYM 上传、真机崩溃触发、线上符号化或告警验收。
- Sentry SDK 升级、降级或 API 重构。
- Analytics、Watch 同步、视频或训练业务行为修改。
- 编辑历史文档 `docs/archive/2026-08-16-glitchtip-crash-reporting-spec.md`；其中的 `Sentry-Static` 是当时有效的历史决定。

## 根因证据

- 当前工程依赖 `https://github.com/getsentry/sentry-apple-binaries.git`，产品是 `Sentry-Static` 9.26.0。
- 2026-08-19 检查的正式 Archive 内含独立 `Sentry.framework`，其 UUID 为 `723C731E-FE79-36BD-A59B-52D3D2B97CAE`。
- 同一 Archive 的 `dSYMs` 目录没有匹配的 `Sentry.framework.dSYM`；App 与 Watch App 自身 dSYM UUID 完整。
- 当前二进制不含可供 `dsymutil` 重建的 DWARF 调试信息，因此不能合理地修补旧 Archive，也不能复制 UUID 不同的 dSYM 冒充匹配文件。
- Sentry 官方 9.26.0 源码仓库明确提供 `SentrySPM` compile-from-source 产品：<https://github.com/getsentry/sentry-cocoa/tree/9.26.0#swift-package-manager-compile-from-source>。

## 文件边界

**计划修改：**

- `ShotMarker.xcodeproj/project.pbxproj`：把远程包从 `sentry-apple-binaries` 改为 `sentry-cocoa`，把 `Sentry-Static` 产品改为 `SentrySPM`。
- `ShotMarker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`：由 SwiftPM 重新解析为 `sentry-cocoa` 9.26.0；不手工伪造 revision 或 origin hash。
- `ShotMarker/Services/AppLogging/GlitchTipCrashReporter.swift`：把源码产品对应的 module 导入改为 `SentrySwift`，不改变上报行为。
- `ShotMarkerTests/GlitchTipConfigurationTests.swift`：同步使用 `SentrySwift` module，不改变测试语义。
- `docs/current/architecture.md`：记录 iPhone target 使用源码编译的 SentrySPM 9.26.0。
- `docs/current/quality.md`：仅在本次测试、Archive 和符号检查成功后更新证据。
- `docs/current/release.md`：仅在本次正式 Archive/Validate 成功后更新版本和发布验证事实，并继续明确 TestFlight 未上传。
- `docs/current/status.md`：按实际结果更新当前阶段与仍未完成的线上验收。
- `docs/README.md`：计划进行中时保留本文件入口；完成后删除入口并把本文移到 `docs/archive/`。

**预期不修改：**

- `ShotMarker/Services/AppLogging/AppLogger.swift`
- `ShotMarkerTests/AppLoggerTests.swift`
- 任何 Watch、训练、视频、Analytics 或隐私实现文件。

如果编译暴露真实的 Sentry 9.26.0 源码产品兼容问题，必须先记录具体编译错误并重新评估；不能为了让构建变绿而无范围地修改业务代码。

## 验收标准

- `Package.resolved` 只解析 `sentry-cocoa` 9.26.0，不再包含 `sentry-apple-binaries`。
- `project.pbxproj` 的 `ShotMarker` target 依赖产品为 `SentrySPM`；Watch target 不含 Sentry。
- 用户已有的版本 `1.2`、Build `1` 与平台设置仍存在。
- Sentry/GlitchTip 定向测试通过。
- iPhone 164 项与 Watch 30 项测试全部通过；如果测试数量因当前代码基线自然变化，则记录实际数量和原因。
- Release 构建和正式 iOS Archive 成功。
- `ShotMarker.app` 与 `ShotMarker.app.dSYM` UUID 完全匹配；Watch App 及其 dSYM 的各架构 UUID 完全匹配。
- 源码静态链接的预期结果是 Archive 不再嵌入独立 `Sentry.framework`。如果仍存在该框架，则必须同时存在 UUID 完全匹配的 `Sentry.framework.dSYM`，否则验收失败。
- Xcode Organizer 显示 Validation Successful，且不再出现 `Upload Symbols Failed`。
- App Store Connect/TestFlight 中没有新增上传 Build。
- `git diff --check` 通过，且最终 diff 没有覆盖用户原有未提交修改。

---

### Task 1: 固化基线并保护用户改动

**Files:**

- Inspect: `ShotMarker.xcodeproj/project.pbxproj`
- Inspect: `ShotMarker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Inspect: `ShotMarker/Services/AppLogging/GlitchTipCrashReporter.swift`
- Inspect: `ShotMarkerTests/AppLoggerTests.swift`
- Inspect: `ShotMarkerTests/GlitchTipConfigurationTests.swift`

**Interfaces:**

- Consumes: 当前 `main` 工作区和用户未提交的版本/平台修改。
- Produces: 可与迁移后结果逐项比较的依赖、版本、target 和工作区基线。

- [x] **Step 1: 确认分支和工作区状态**

Run:

```bash
git branch --show-current
git status --short
```

Expected: 分支为 `main`；`ShotMarker.xcodeproj/project.pbxproj` 显示为用户已修改文件。

- [x] **Step 2: 复核并保留用户现有工程修改**

Run:

```bash
git diff -- ShotMarker.xcodeproj/project.pbxproj
```

Expected: diff 至少包含主 App 与 Watch 的 `MARKETING_VERSION = 1.2`，以及用户已有的平台配置调整；后续任何编辑都不得移除这些 hunks。

- [x] **Step 3: 记录迁移前 Sentry 接线**

Run:

```bash
rg -n -C 2 'Sentry-Static|sentry-apple-binaries' \
  ShotMarker.xcodeproj/project.pbxproj \
  ShotMarker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

Expected: 工程和 resolved file 都指向 `sentry-apple-binaries` 9.26.0，主 target 使用 `Sentry-Static`。

- [x] **Step 4: 确认现有代码只依赖稳定的 `Sentry` module API**

Run:

```bash
rg -n 'import Sentry|SentrySDK' ShotMarker ShotMarkerTests
```

Expected: 现有调用通过 `import Sentry` 使用 SDK；没有直接引用 `Sentry-Static` 产品名。

### Task 2: 把 SwiftPM 接线迁移到 SentrySPM

**Files:**

- Modify: `ShotMarker.xcodeproj/project.pbxproj:11,113,235,277,816-830`
- Regenerate: `ShotMarker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

**Interfaces:**

- Consumes: `ShotMarker` target 现有 `FF7000012FA6000000B04685` 包引用与 `FF7000022FA6000000B04685` 产品引用。
- Produces: 同一 target 的 `sentry-cocoa` 9.26.0 / `SentrySPM` 依赖；源码产品实际 Swift module 名为 `SentrySwift`。

- [x] **Step 1: 最小化修改工程依赖引用**

Apply these exact semantic replacements in `project.pbxproj`：

```text
XCRemoteSwiftPackageReference "sentry-apple-binaries"
→ XCRemoteSwiftPackageReference "sentry-cocoa"

https://github.com/getsentry/sentry-apple-binaries.git
→ https://github.com/getsentry/sentry-cocoa.git

Sentry-Static
→ SentrySPM
```

Keep:

```text
kind = upToNextMajorVersion;
minimumVersion = 9.26.0;
```

Expected: 只改变包地址、注释和产品名；PBX object IDs、版本号、Build 号、平台设置及 target 归属保持不变。

- [x] **Step 2: 检查工程 diff 没有吞掉用户修改**

Run:

```bash
git diff -- ShotMarker.xcodeproj/project.pbxproj
```

Expected: 用户的 1.2/平台修改仍在；新增变化只涉及 Sentry package/product 接线。

- [x] **Step 3: 让 SwiftPM 生成真实解析结果**

Run:

```bash
xcodebuild -resolvePackageDependencies \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker
```

Expected: exit 0；解析 `https://github.com/getsentry/sentry-cocoa.git` 9.26.0，并在本机下载源码 checkout。

- [x] **Step 4: 验证 resolved file 与 target 归属**

Run:

```bash
rg -n 'sentry-cocoa|sentry-apple-binaries|SentrySPM|Sentry-Static' \
  ShotMarker.xcodeproj/project.pbxproj \
  ShotMarker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

Expected: 只出现 `sentry-cocoa`、`SentrySPM` 和版本 `9.26.0`；旧包与旧产品均不存在。`SentrySPM` 只位于 `ShotMarker` target 的 Frameworks/package dependencies。

### Task 3: 验证源码产品没有改变上报行为

**Files:**

- Test: `ShotMarkerTests/AppLoggerTests.swift`
- Test: `ShotMarkerTests/GlitchTipConfigurationTests.swift`
- Verify only: `ShotMarker/Services/AppLogging/GlitchTipCrashReporter.swift`

**Interfaces:**

- Consumes: 源码构建后的 `SentrySwift` module 和现有 GlitchTip adapter。
- Produces: 与迁移前相同的初始化、禁用策略和 `.error` 上报行为证据。

- [x] **Step 1: 运行 Sentry/GlitchTip 定向测试**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/AppLoggerTests \
  -only-testing:ShotMarkerTests/GlitchTipConfigurationTests
```

Expected: 两个 test class 全部通过；没有 module import、linker 或 duplicate symbol 错误。

- [x] **Step 2: 运行完整 iPhone 测试**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: 当前基线 164 项通过，0 失败，0 跳过；记录本次实际数量。

- [x] **Step 3: 运行完整 Watch 测试，确认未引入 Sentry**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarkerWatchApp \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5'
```

Expected: 当前基线 30 项通过，0 失败，0 跳过；Watch 构建日志不链接 `SentrySPM`。

### Task 4: 生成正式 Archive 并校验符号

**Files:**

- Produce: `/tmp/shotmarker-sentryspm-archive.*/ShotMarker.xcarchive`
- Inspect: Task 4 固定路径 `/tmp/ShotMarker-SentrySPM-Verification-2026-08-19.xcarchive/Products/Applications/ShotMarker.app`
- Inspect: Task 4 固定路径 `/tmp/ShotMarker-SentrySPM-Verification-2026-08-19.xcarchive/dSYMs/*.dSYM`

**Interfaces:**

- Consumes: 已通过测试的 Release 工程和 Apple 自动签名配置。
- Produces: 可供 Xcode Validate 的正式 Archive 与 UUID/dSYM 验收证据。

- [x] **Step 1: 执行 Release 构建**

Run:

```bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator'
```

Expected: exit 0；`SentrySPM` 从源码编译并链接成功。

- [x] **Step 2: 创建隔离的正式 Archive 路径并执行签名 Archive**

Run:

```bash
archive_path="/tmp/ShotMarker-SentrySPM-Verification-2026-08-19.xcarchive"
test ! -e "$archive_path"
xcodebuild archive \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path"
```

Expected: `** ARCHIVE SUCCEEDED **`；Archive 的 Info.plist 显示版本 `1.2`、Build `1`、Bundle ID `com.heji.ShotMarker`。

- [x] **Step 3: 验证主 App 与 Watch App dSYM UUID**

Run:

```bash
archive_path="/tmp/ShotMarker-SentrySPM-Verification-2026-08-19.xcarchive"
dwarfdump --uuid "$archive_path/Products/Applications/ShotMarker.app/ShotMarker"
dwarfdump --uuid "$archive_path/dSYMs/ShotMarker.app.dSYM"
dwarfdump --uuid "$archive_path/Products/Applications/ShotMarker.app/Watch/ShotMarkerWatchApp.app/ShotMarkerWatchApp"
dwarfdump --uuid "$archive_path/dSYMs/ShotMarkerWatchApp.app.dSYM"
```

Expected: 主 App 的全部 UUID 在对应 dSYM 中存在；Watch App 每个架构的 UUID 都在对应 dSYM 中存在。

- [x] **Step 4: 确认不再留下无符号的 Sentry.framework**

Run:

```bash
archive_path="/tmp/ShotMarker-SentrySPM-Verification-2026-08-19.xcarchive"
find "$archive_path/Products/Applications/ShotMarker.app" \
  -path '*/Frameworks/Sentry.framework/Sentry' -print
find "$archive_path/dSYMs" -name 'Sentry.framework.dSYM' -print
```

Expected: 源码静态链接时两条命令均无输出。如果第一条有输出，第二条必须找到 dSYM，并使用 `dwarfdump --uuid` 证明二者 UUID 完全匹配；否则立即判定验收失败。

- [x] **Step 5: 检查 Archive 元数据与签名**

Run:

```bash
archive_path="/tmp/ShotMarker-SentrySPM-Verification-2026-08-19.xcarchive"
plutil -p "$archive_path/Info.plist"
codesign --verify --deep --strict --verbose=2 \
  "$archive_path/Products/Applications/ShotMarker.app"
```

Expected: Archive 元数据正确；`codesign` exit 0。

### Task 5: 只执行 Validate，不上传 TestFlight

**Files:**

- Inspect: Task 4 生成的 `ShotMarker.xcarchive`

**Interfaces:**

- Consumes: 已完成本地 UUID 和签名检查的 Archive。
- Produces: Apple 服务端 validation 结果；不产生 TestFlight Build。

- [x] **Step 1: 在 Xcode Organizer 打开新 Archive**

Run:

```bash
archive_path="/tmp/ShotMarker-SentrySPM-Verification-2026-08-19.xcarchive"
open "$archive_path"
```

Expected: Xcode Organizer 选中本次 1.2（1）Archive。

- [x] **Step 2: 执行 Validate App**

在 Organizer 中选择 `Validate App`，使用当前 ShotMarker distribution 配置完成检查。

Expected: 显示 `Validation Successful`，且不存在 `Upload Symbols Failed` 或其他 warning/error。

- [x] **Step 3: 在验证成功页面停止**

点击 `Done` 返回 Organizer；不得选择 `Distribute App`、`Upload` 或任何 TestFlight 上传入口。

Expected: App Store Connect/TestFlight 中没有由本任务新增的 Build。

### Task 6: 更新证据文档并完成变更生命周期

**Files:**

- Modify: `docs/current/architecture.md`
- Modify: `docs/current/quality.md`
- Modify: `docs/current/release.md`
- Modify: `docs/current/status.md`
- Modify: `docs/README.md`
- Move after completion: `docs/changes/2026-08-19-sentry-spm-migration-plan.md` → `docs/archive/2026-08-19-sentry-spm-migration-plan.md`
- Conditionally modify after private repository sync: `docs/private.local/shotmarker/current/release.md`

**Interfaces:**

- Consumes: Tasks 2–5 的真实解析、测试、Archive、UUID 和 Validate 输出。
- Produces: 与代码和外部验证状态一致的公开当前事实，以及必要的私有 Archive 台账。

- [x] **Step 1: 更新公开当前事实**

只记录实际验证结果：

- `architecture.md`：Sentry 9.26.0 使用 `sentry-cocoa` 的 `SentrySPM` 源码产品，仅链接 iPhone target。
- `quality.md`：写入本次测试数量、Release/Archive 结果、App/Watch UUID 对应结果和 Validate 无警告结果。
- `release.md`：按 Archive 元数据记录 1.2（Build 1）和正式 Archive/Validate 结果，并明确本任务未上传 TestFlight。
- `status.md`：把缺少正式 Archive 的风险更新为本次真实结果；继续保留真机崩溃、GlitchTip 符号化、告警和 TestFlight 未验收项。

Expected: 不把本次 Validate 表述为 TestFlight、真机或 GlitchTip 线上验收。

- [x] **Step 2: 按私有仓库规则处理正式 Archive 事实**

先检查并同步独立私有仓库：

```bash
git -C docs/private.local status --short --branch
git -C docs/private.local pull --rebase
```

只有同步成功且工作区干净时，才在 `docs/private.local/shotmarker/current/release.md` 记录本次签名 Archive 和 Validate 日期/版本；不得写凭据、证书私钥、设备 UDID 或账号信息。私有仓库的 commit/push 必须与公开仓库分开，并且只在该执行范围获得授权时进行。

- [x] **Step 3: 运行最终静态检查**

Run:

```bash
git diff --check
rg -n 'sentry-apple-binaries|Sentry-Static' \
  ShotMarker.xcodeproj \
  docs/current
git status --short
```

Expected: `git diff --check` exit 0；活动工程和 current 文档没有旧依赖；用户原有修改与本次修改都清晰可审阅。

- [x] **Step 4: 完成后归档本计划**

仅当所有验收标准满足时：

1. 从 `docs/README.md` 的“正在进行的变更”移除本计划入口；
2. 把本文移动到 `docs/archive/2026-08-19-sentry-spm-migration-plan.md`；
3. 不编辑旧的 GlitchTip 历史规格；新的 current 文档代表当前有效决定。

Expected: `docs/changes/` 不再把已完成的迁移列为进行中；archive 保存完整实施与验证步骤。

## 实际执行结果（2026-08-19）

- 实施前确认分支为 `main`，并逐项保留了用户未提交的 1.2（Build 1）和平台配置调整。
- SwiftPM 成功解析官方 `sentry-cocoa` 9.26.0，`SentrySPM` 只属于 ShotMarker 主 target；Watch target 的依赖图不含 Sentry。
- 第一次定向测试按停止条件中止：`import Sentry` 无法解析。检查 9.26.0 源码产品和官方示例后确认其 module 为 `SentrySwift`；经用户明确确认，只修改主 App adapter 与对应测试的两个导入语句，未改变 DSN、事件字段或上报行为。
- 修正后 Sentry/GlitchTip 定向测试 10 项通过；iPhone 164 项通过；Watch 30 项通过，均为 0 失败、0 跳过。Watch 按名称选择 destination 时因 Xcode 26.6 出现歧义，改用当次明确选择的模拟器 destination 后通过，未把模拟器标识写入文档。
- Release Simulator 构建成功；正式签名 Archive `/tmp/ShotMarker-SentrySPM-Verification-2026-08-19.xcarchive` 成功，元数据为 1.2（Build 1）。
- 主 App 二进制与 dSYM UUID 完全匹配；Watch App 各架构二进制与 dSYM UUID 完全匹配；Archive 未嵌入独立 `Sentry.framework`，签名严格校验通过。
- Xcode Organizer Validate 成功，状态日志只有准备验证和验证成功记录，没有 warning/error 或 `Upload Symbols Failed`。Xcode 为验证提交自动管理的 Build Number 是 2，本地 Archive 仍是 Build 1。
- 本任务在验证成功页面停止，没有点击 `Distribute App` 或执行上传。Organizer 中同日较早的 `Uploaded to Apple` 记录在本任务开始前已经存在；本任务新归档的最终状态仅为 `Validation succeeded`。
- 公开 current 文档已按当次证据更新；私有发布台账已在独立仓库同步、提交并推送。
- `git diff --check` 通过；活动工程和 `docs/current/` 中不再出现旧包或旧产品引用，用户原有工程修改仍保留在最终 diff 中。

## 停止条件

出现以下任一情况时停止，不继续 Validate：

- SwiftPM 不能解析官方 `sentry-cocoa` 9.26.0。
- `SentrySPM` 导致现有 `import Sentry` 无法编译或出现 duplicate symbols。
- 任一自动化测试失败。
- Archive 签名失败。
- App、Watch 或任何嵌入式框架的二进制 UUID 没有匹配 dSYM。
- Validate 仍出现 `Upload Symbols Failed` 或其他 error/warning。
- 实施需要覆盖无法与用户未提交修改安全分离的工程配置。

停止时保留失败日志和当前 diff，说明具体阻塞点；不得通过关闭 dSYM、关闭符号上传、伪造 dSYM 或上传 TestFlight 来绕过。
