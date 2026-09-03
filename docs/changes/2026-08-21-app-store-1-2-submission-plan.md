# ShotMarker 1.2 App Store Submission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** 把 ShotMarker 1.2 从 `Prepare for Submission` 推进到经过代码、Archive、TestFlight、真机、隐私披露和商店资料验收的 App Review 提交，并在批准后以人工确认的方式发布。

**Architecture:** 保持现有 iPhone App + 嵌入式 Apple Watch App 架构，不新增业务功能。先在仓库内修正候选构建身份、隐私清单、导出合规和语言声明，再从同一提交生成 1.2（Build 3）Archive；随后用该候选完成 TestFlight、真机、Analytics、GlitchTip、商店元数据和审核资料验收。所有会改变 Apple、GlitchTip 或线上发布状态的动作都放在明确的人工确认门后。

**Tech Stack:** Xcode 26.6、Swift 5 language mode、SwiftUI、XCTest、Swift Package Manager、Sentry Cocoa 9.26.0 `SentrySPM`、App Store Connect、TestFlight、GlitchTip CLI、`xcodebuild`、`plutil`、`dwarfdump`、`codesign`、`sips`、Git。

**Spec:** 本次没有独立 spec。需求来自用户于 2026-08-21 确认的“开始准备提交并列出逐步计划”，当前事实以 [项目状态](../current/status.md)、[产品事实](../current/product.md)、[质量状态](../current/quality.md)、[发布状态](../current/release.md) 和当前代码为准。

**Global Constraints:**

- 所有开发直接在 `main` 完成；不得创建分支或 worktree。
- 每次编辑前确认分支仍为 `main`，且不得覆盖或丢弃用户未提交修改。
- 商店版本固定为 1.2；候选 Build 固定为 3。已知 App Store Connect 有 1.2（Build 1），且 2026-08-19 的 Validate 流程曾自动管理到 Build 2，因此不复用 1 或 2。
- 主 App 保持 `TARGETED_DEVICE_FAMILY = "1,2"`，本次不尝试删除已公开的 iPad 支持；iPad 必须进入候选验收和截图范围。
- 产品正式范围仍为 iPhone + Apple Watch；未经真机验收，不继续向 Mac 或 Apple Vision Pro 提供兼容版。外部可用性开关在执行时须再次获得用户确认。
- 不改变 iOS 26.4、watchOS 26.2 部署下限，不实现仍在独立 Change 中的语音功能。
- 不记录 Apple 登录信息、测试者邮箱、设备 UDID、GlitchTip Token、DSN 管理凭据、原始用户标识或任何 `.env` 实际值。
- `Add for Review`、`Submit for Review`、App Privacy `Publish`、TestFlight 上传、GlitchTip 符号上传和 `Release This Version` 都是外部状态修改；执行到对应步骤前必须展示最终检查结果并获得用户确认。
- 任一自动化测试、签名、Archive、dSYM UUID、Validate、TestFlight 主链路、隐私披露或必填元数据验收失败，都必须停止；不得靠忽略 warning、关闭符号、伪造披露或提交旧 Build 绕过。
- 公开代码与产品事实留在本仓库；App Store Connect、TestFlight、真机和线上观测的完整证据只写入独立私有台账。

## 2026-08-21 基线判断

- 用户截图显示 iOS App 1.2 仍为 `Prepare for Submission`，页面右上角可以点击 `Add for Review`；按钮可点不等于资料和候选 Build 已验收。
- 仓库当前为 1.2（Build 1）。最新正式 Archive 已 Validate，但没有上传；Organizer 中另有更早的 Build 1 上传记录。
- 当前公开商店页仍写着“不需要 server connection”，隐私标签仍是“No Data Collected”，但 1.2 Release iPhone 已发送有限 Analytics 和 GlitchTip 错误/崩溃信息，提交前必须同步更正。
- 当前 `PrivacyInfo.xcprivacy` 只声明 Device ID、Product Interaction、UserDefaults 和 File Timestamp；源码方式接入的 Sentry 官方 manifest 资源没有进入最终 bundle，因此主 App manifest 还必须补齐 Crash Data、Performance Data、Other Diagnostic Data 和 System Boot Time。
- 当前 iPhone 6.9 英寸和 6.5 英寸各有 4 张 2026-08-20 截图；仓库中的 iPad 与 Watch 上传素材来自 2026-05-20，需要使用 1.2 候选重新核验或重拍。
- 主 App 公开支持 iPad；Apple 当前规格要求运行在 iPad 的 App 提供 13 英寸截图，包含 Watch App 时提供 Watch 截图。
- 工程 UI 主要为简体中文，但项目开发语言和公开商店语言仍显示 English；提交前要把二进制语言声明改为简体中文，并新增简体中文商店元数据。

## 文件与外部对象清单

### 仓库内预计修改

- `ShotMarker/PrivacyInfo.xcprivacy`
- `ShotMarkerTests/PrivacyManifestTests.swift`
- `ShotMarker.xcodeproj/project.pbxproj`
- `Config/ShotMarker-Info.plist`
- `Config/ShotMarkerWatchApp-Info.plist`
- `AppStoreScreenshots/2026-08-21-ipad-13/*.png`
- `AppStoreScreenshots/2026-08-21-watch-46/*.png`
- 完成后按真实结果更新 `docs/current/status.md`
- 完成后按真实结果更新 `docs/current/architecture.md`
- 完成后按真实结果更新 `docs/current/quality.md`
- 完成后按真实结果更新 `docs/current/release.md`
- 完成后按真实结果更新 `docs/current/analytics.md`
- 完成后更新 `docs/README.md`
- 完成后移动本计划到 `docs/archive/2026-08/2026-08-21-app-store-1-2-submission-plan.md`

### 私有台账预计修改

- `docs/private.local/shotmarker/current/release.md`
- `docs/private.local/shotmarker/current/observability.md`

### 外部对象

- App Store Connect 的 iOS App 1.2 版本页
- TestFlight 的 1.2（Build 3）候选
- App Privacy 回答与隐私政策 URL
- App Information 的年龄分级
- Pricing and Availability 的地区、Mac 和 Apple Vision Pro 可用性
- App Review 联系信息、审核备注和 Draft Submission
- GlitchTip 的 dSYM、受控崩溃事件和告警
- ShotMarker 公开 App Store 产品页

## Phase 1：生成可提交的 1.2（Build 3）候选

### Task 1：锁定发布基线和外部权限边界

**Files:**

- Inspect: `ShotMarker.xcodeproj/project.pbxproj`
- Inspect: `docs/current/*.md`
- Inspect: `docs/private.local/shotmarker/current/*.md`

- [ ] **Step 1: 确认公开仓库仍在 main 且工作区可安全编辑**

Run:

```bash
git branch --show-current
git status --short
git log -1 --oneline --decorate
```

Expected: 第一条严格输出 `main`；状态为空，或所有已有修改都已逐项识别并能与本计划安全共存。若分支不是 `main` 或存在无法归属的修改，停止。

- [ ] **Step 2: 检查独立私有仓库但不修改**

Run:

```bash
git -C docs/private.local branch --show-current
git -C docs/private.local status --short
```

Expected: 私有仓库为 `main` 且干净；否则只报告状态，不同步、不编辑。

- [ ] **Step 3: 在 App Store Connect 只读核验构建号和合同状态**

依次查看 `TestFlight > iOS > 1.2`、`Business` 和 `Pricing and Availability`：

1. 记录所有 1.2 Build 号及 `Processing`、`Complete`、`Failed` 状态；
2. 确认 Build 3 没有被使用；
3. 确认没有阻止免费 App 更新的协议、税务、银行或地区提示；
4. 不在本步骤上传、发布隐私回答或修改可用性。

Expected: Build 3 可用，且没有必须先由 Account Holder 处理的红色阻塞。若 Build 3 已存在，停止并把候选号统一提升到第一个未使用的更大整数后更新本计划和工程。

### Task 2：先用失败测试锁定完整隐私 manifest

**Files:**

- Modify: `ShotMarkerTests/PrivacyManifestTests.swift`
- Test: `ShotMarkerTests/PrivacyManifestTests.swift`

- [ ] **Step 1: 增加诊断数据精确集合测试**

在 `PrivacyManifestTests` 新增测试，要求收集数据类型集合严格为以下五项，不能缺失也不能静默增加：

```swift
func testCollectedDataTypesExactlyMatchAnalyticsAndDiagnosticsContract() throws {
    let manifest = try loadManifest()
    let entries = try XCTUnwrap(
        manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]],
    )
    let types = entries.compactMap {
        $0["NSPrivacyCollectedDataType"] as? String
    }

    XCTAssertEqual(Set(types), Set([
        "NSPrivacyCollectedDataTypeDeviceID",
        "NSPrivacyCollectedDataTypeProductInteraction",
        "NSPrivacyCollectedDataTypeCrashData",
        "NSPrivacyCollectedDataTypePerformanceData",
        "NSPrivacyCollectedDataTypeOtherDiagnosticData",
    ]))
    XCTAssertEqual(types.count, 5)
}
```

- [ ] **Step 2: 增加诊断数据属性测试**

新增测试，逐项要求 Crash Data、Performance Data 和 Other Diagnostic Data：

- `Linked = false`
- `Tracking = false`
- purposes 只包含 `NSPrivacyCollectedDataTypePurposeAppFunctionality`
- 每个类型恰好出现一次

- [ ] **Step 3: 扩展 Required Reason API 测试**

在现有表驱动断言中加入：

```swift
("NSPrivacyAccessedAPICategorySystemBootTime", "35F9.1")
```

同时把测试名改为能覆盖 app 与源码 Sentry 所需 API 的名称。

- [ ] **Step 4: 运行定向测试并确认先失败**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/PrivacyManifestTests
```

Expected: 新增的诊断数据和 System Boot Time 断言失败；失败原因必须是当前 manifest 缺项，而不是编译、模拟器或依赖问题。

### Task 3：补齐 App 隐私 manifest

**Files:**

- Modify: `ShotMarker/PrivacyInfo.xcprivacy`
- Verify: `ShotMarkerTests/PrivacyManifestTests.swift`

- [ ] **Step 1: 保留现有 Analytics 声明**

保留以下契约不变：

- Device ID：linked、Analytics、not tracking
- Product Interaction：linked、Analytics、not tracking
- `NSPrivacyTracking = false`
- 不添加 tracking domains

- [ ] **Step 2: 合并 Sentry 官方诊断声明**

在 `NSPrivacyCollectedDataTypes` 增加：

- Crash Data：unlinked、App Functionality、not tracking
- Performance Data：unlinked、App Functionality、not tracking
- Other Diagnostic Data：unlinked、App Functionality、not tracking

在 `NSPrivacyAccessedAPITypes` 增加：

- System Boot Time：reason `35F9.1`

保留：

- UserDefaults：reason `CA92.1`
- File Timestamp：reason `C617.1`

- [ ] **Step 3: 验证 plist 结构与定向测试**

Run:

```bash
plutil -lint ShotMarker/PrivacyInfo.xcprivacy
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/PrivacyManifestTests
```

Expected: `plutil` 输出 `OK`；PrivacyManifestTests 全部通过。

### Task 4：固化 Build 3、导出合规和简体中文语言声明

**Files:**

- Modify: `ShotMarker.xcodeproj/project.pbxproj`
- Modify: `Config/ShotMarker-Info.plist`
- Modify: `Config/ShotMarkerWatchApp-Info.plist`

- [ ] **Step 1: 统一主 App 与 Watch App 的候选构建号**

只修改产品 targets 的 Debug/Release 配置：

- `ShotMarker` 的 `CURRENT_PROJECT_VERSION`：1 → 3
- `ShotMarkerWatchApp` 的 `CURRENT_PROJECT_VERSION`：1 → 3
- `MARKETING_VERSION` 保持 1.2
- 两个测试 target 的版本号不改

- [ ] **Step 2: 固化导出合规键**

在 `Config/ShotMarker-Info.plist` 增加：

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

前提是本次源码复核仍确认 App 只使用 Apple 系统提供的 HTTPS/TLS，没有自带、实现或嵌入非豁免加密。若发现自定义加密，停止并重新进行出口合规判断。

- [ ] **Step 3: 让二进制语言声明与中文 UI 一致**

在工程对象中：

- `developmentRegion` 从 `en` 改为 `zh-Hans`
- `knownRegions` 保留 `Base`，把 `en` 替换为 `zh-Hans`

在主 App 和 Watch App Info plist 中都加入：

```xml
<key>CFBundleLocalizations</key>
<array>
    <string>zh-Hans</string>
</array>
```

把 Watch 的两个 HealthKit 使用说明改成简体中文并保持事实准确：

- `NSHealthShareUsageDescription`：`ShotMarker 不读取健康数据；训练授权仅用于维持手表训练会话。`
- `NSHealthUpdateUsageDescription`：`ShotMarker 会写入一次训练记录，以便训练期间保持手表训练界面运行。`

- [ ] **Step 4: 验证 Build Settings**

Run:

```bash
xcodebuild -project ShotMarker.xcodeproj -scheme ShotMarker -showBuildSettings \
  | rg 'CURRENT_PROJECT_VERSION|MARKETING_VERSION|TARGETED_DEVICE_FAMILY|DEVELOPMENT_LANGUAGE'
xcodebuild -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -showBuildSettings \
  | rg 'CURRENT_PROJECT_VERSION|MARKETING_VERSION|TARGETED_DEVICE_FAMILY|DEVELOPMENT_LANGUAGE'
plutil -lint Config/ShotMarker-Info.plist
plutil -lint Config/ShotMarkerWatchApp-Info.plist
```

Expected: 产品 targets 都显示 1.2（3）；主 App family 仍为 `1,2`，Watch 为 `4`；开发语言为 `zh-Hans`；两个 plist 均为 `OK`。

- [ ] **Step 5: 提交候选配置改动**

Run:

```bash
git diff --check
git diff -- ShotMarker/PrivacyInfo.xcprivacy \
  ShotMarkerTests/PrivacyManifestTests.swift \
  ShotMarker.xcodeproj/project.pbxproj \
  Config/ShotMarker-Info.plist \
  Config/ShotMarkerWatchApp-Info.plist
git add ShotMarker/PrivacyInfo.xcprivacy \
  ShotMarkerTests/PrivacyManifestTests.swift \
  ShotMarker.xcodeproj/project.pbxproj \
  Config/ShotMarker-Info.plist \
  Config/ShotMarkerWatchApp-Info.plist
git commit -m "fix: 完善 1.2 提交隐私与构建配置"
```

Expected: diff 只包含本任务明确列出的内容；commit 成功且仍位于 `main`。

### Task 5：运行完整自动化和三类模拟器验收

**Files:**

- Verify: all app, watch and test sources
- Produce: fresh `.xcresult` files in a temporary directory

- [ ] **Step 1: 解析并锁定 Sentry 依赖**

Run:

```bash
xcodebuild -resolvePackageDependencies \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker
```

Expected: 解析 `sentry-cocoa` 9.26.0 和 `SentrySPM` 成功，`Package.resolved` 没有意外变化。

- [ ] **Step 2: 完整 iPhone 测试**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: 全部通过，0 失败；记录实际测试数量，不沿用旧的 164 项数字。

- [ ] **Step 3: 完整 Watch 测试**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarkerWatchApp \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5'
```

Expected: 全部通过，0 失败；记录实际测试数量，不沿用旧的 30 项数字。

- [ ] **Step 4: 在 iPad 13 英寸模拟器运行完整主 App 测试与构建**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5'
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5'
```

Expected: 测试与 Release build 均成功；Analytics 运行策略测试继续证明 iPad 为 no-op。

- [ ] **Step 5: 运行 Release iPhone build**

Run:

```bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator'
```

Expected: `** BUILD SUCCEEDED **`，没有新的 linker、privacy manifest 或 Sentry warning。

- [ ] **Step 6: 记录而不掩盖 SwiftLint 基线**

运行项目现有 SwiftLint 命令；记录本次实际结果。现有 42 violation / 5 error 不是本次 App Store 技术阻塞，但本次不得新增 violation，也不得把非绿色结果写成“通过”。

## Phase 2：Archive、TestFlight 与真机发布门

### Task 6：生成正式 Archive 并核对内部产物

**Files:**

- Produce: `/tmp/ShotMarker-1.2-3-Submission.xcarchive`

- [ ] **Step 1: 创建唯一 Archive 路径并签名归档**

Run:

```bash
archive_path="/tmp/ShotMarker-1.2-3-Submission.xcarchive"
test ! -e "$archive_path"
xcodebuild archive \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path"
```

Expected: `** ARCHIVE SUCCEEDED **`。

- [ ] **Step 2: 验证主 App 元数据、语言、设备和导出合规**

Run:

```bash
archive_path="/tmp/ShotMarker-1.2-3-Submission.xcarchive"
app_path="$archive_path/Products/Applications/ShotMarker.app"
plutil -p "$app_path/Info.plist" \
  | rg 'CFBundleShortVersionString|CFBundleVersion|CFBundleDevelopmentRegion|CFBundleLocalizations|UIDeviceFamily|ITSAppUsesNonExemptEncryption'
plutil -p "$app_path/PrivacyInfo.xcprivacy"
```

Expected: 版本 1.2、Build 3、开发语言/本地化 `zh-Hans`、family 包含 1 和 2、`ITSAppUsesNonExemptEncryption = false`，PrivacyInfo 恰好覆盖五类数据和三类 Required Reason API。

- [ ] **Step 3: 验证嵌入式 Watch App**

Run:

```bash
archive_path="/tmp/ShotMarker-1.2-3-Submission.xcarchive"
watch_path="$archive_path/Products/Applications/ShotMarker.app/Watch/ShotMarkerWatchApp.app"
plutil -p "$watch_path/Info.plist" \
  | rg 'CFBundleShortVersionString|CFBundleVersion|CFBundleDevelopmentRegion|CFBundleLocalizations|UIDeviceFamily|NSHealth'
```

Expected: Watch 同为 1.2（3）、family 4、语言为 `zh-Hans`，HealthKit 说明与实现一致。

- [ ] **Step 4: 验证主 App 与 Watch dSYM UUID**

Run:

```bash
archive_path="/tmp/ShotMarker-1.2-3-Submission.xcarchive"
dwarfdump --uuid "$archive_path/Products/Applications/ShotMarker.app/ShotMarker"
dwarfdump --uuid "$archive_path/dSYMs/ShotMarker.app.dSYM"
dwarfdump --uuid "$archive_path/Products/Applications/ShotMarker.app/Watch/ShotMarkerWatchApp.app/ShotMarkerWatchApp"
dwarfdump --uuid "$archive_path/dSYMs/ShotMarkerWatchApp.app.dSYM"
```

Expected: 主 App 和 Watch App 的每个二进制 UUID 都在对应 dSYM 中出现。

- [ ] **Step 5: 验证签名和静态 Sentry 产物**

Run:

```bash
archive_path="/tmp/ShotMarker-1.2-3-Submission.xcarchive"
codesign --verify --deep --strict --verbose=2 \
  "$archive_path/Products/Applications/ShotMarker.app"
find "$archive_path/Products/Applications/ShotMarker.app" \
  -path '*/Frameworks/Sentry.framework/Sentry' -print
```

Expected: `codesign` exit 0；源码静态链接模式下没有独立 `Sentry.framework`。

### Task 7：在 Organizer Validate，尚不上传

**Files:**

- Inspect: `/tmp/ShotMarker-1.2-3-Submission.xcarchive`

- [ ] **Step 1: 打开本次 Archive**

Run:

```bash
open /tmp/ShotMarker-1.2-3-Submission.xcarchive
```

Expected: Organizer 选中 1.2（3），日期和 Archive 路径与本次一致。

- [ ] **Step 2: 执行 Validate App**

在 Organizer 选择 `Validate App`。如果出现 “Manage Version and Build Number”，保持最终验证摘要为 1.2（3）；若 Xcode 试图自动改号，取消并关闭自动管理后重试。

Expected: `Validation Successful`，没有 `Upload Symbols Failed`、privacy manifest、export compliance、bundle version、Watch bundle 或签名 warning/error。

- [ ] **Step 3: 在 Validate 成功页停止**

点击 `Done` 返回 Organizer，不点击 `Distribute App`。

Expected: 本步骤不产生新的 App Store Connect Build。

### Task 8：获得确认后上传 Build 3 并启用内部 TestFlight

**External side effect gate:** 向用户展示 Tasks 1–7 的实际结果；只有用户明确同意上传后继续。

- [ ] **Step 1: 从同一个 Archive 上传**

在 Organizer 选择：

1. `Distribute App`
2. `App Store Connect`
3. `Upload`
4. 保持符号上传开启
5. 最终摘要必须显示 iOS App 1.2（3）和嵌入式 Watch App 1.2（3）

Expected: Xcode 报告上传成功；不得改用旧 Build 1 Archive。

- [ ] **Step 2: 等待 App Store Connect 处理完成**

在 `TestFlight > iOS > 1.2 > Build 3` 检查状态。

Expected: `Complete` 且没有 warning badge。若 `Failed`，修复后 Apple 允许复用同一 Build 号，但本计划仍优先提升到 Build 4，避免混淆证据；若超过 24 小时仍 `Processing`，按 Apple 指引联系支持，不继续提交。

- [ ] **Step 3: 确认导出合规不是 Missing Compliance**

Expected: Build 不显示 `Missing Compliance`。若仍显示，先核对归档 Info.plist 中的键和实际加密使用，再回答；不得在没有重新判断的情况下随意选择。

- [ ] **Step 4: 加入内部测试组并填写 What to Test**

English:

```text
Please test Apple Watch start/mark/end, reliable sync to iPhone, video selection and marker coverage, highlight generation, playback, Photos saving, and iPad launch/import. No account is required.
```

简体中文：

```text
请测试 Apple Watch 开始、打点和结束训练，可靠同步到 iPhone，视频选择与打点覆盖检查，集锦生成、播放和保存相册，以及 iPad 启动和导入。不需要账户。
```

Expected: 内部测试者可在 TestFlight 安装 1.2（3）；不提交外部 Beta Review。

### Task 9：完成 TestFlight 真机矩阵

**Evidence:** 只在私有台账记录设备型号、系统版本、Build、日期和结论；不记录 UDID 或测试者邮箱。

- [ ] **Step 1: iPhone 全新安装**

1. 删除旧 TestFlight 版本并安装 1.2（3）；
2. 首次启动无崩溃，照片权限文案为中文；
3. 不登录即可进入训练记录页；
4. 空数据、导入、导出和删除流程正常。

Expected: 全新安装主流程可用，且没有英文/中文声明与实际 UI 明显冲突。

- [ ] **Step 2: 从 App Store 1.1 升级到 TestFlight 1.2（3）**

1. 安装公开 1.1 并创建或保留一条训练记录；
2. 直接用 TestFlight 安装 1.2（3）；
3. 确认训练记录和本地任务数据没有丢失；
4. 完成一次新集锦任务。

Expected: 升级不丢数据、不开启重复迁移、不崩溃。

- [ ] **Step 3: 配对 iPhone + Apple Watch 完整流程**

1. Watch 长按开始训练并处理 HealthKit 写入授权；
2. 双击屏幕打点；
3. 转动数码表冠累计达到阈值打点；
4. Watch 长按结束；
5. iPhone 收到训练记录并返回 ACK；
6. Watch outbox 最终清理；
7. iPhone 选择匹配视频、检查覆盖、生成、播放并保存。

Expected: 同步不重复、不丢失；HealthKit 只请求写 workout，不读取健康数据；生成视频可播放并成功保存。

- [ ] **Step 4: 权限拒绝与恢复**

分别验证 Photos 读取、Photos 添加和 HealthKit 写入被拒绝时：

- App 不崩溃；
- 用户能看到可理解反馈或核心打点流程按设计降级；
- 重新授权后可恢复；
- 不上传照片、视频或 HealthKit 内容。

- [ ] **Step 5: iPad 1.2（3）验收**

在 13 英寸 iPad 或对应模拟器：

1. 启动、旋转和列表布局无截断；
2. 导入从 iPhone 导出的训练 JSON；
3. 选择视频并完成覆盖检查、生成、播放、保存；
4. 验证 iPad 不发送产品 Analytics；
5. 明确 Watch 实时同步需要配对 iPhone，不在 iPad 上伪装为可用。

Expected: 已公开的 iPad destination 具备可提交的基本体验。

### Task 10：验收 Analytics、GlitchTip、dSYM 和告警

- [ ] **Step 1: 验证四个 Analytics 事件**

用全新安装的 iPhone 1.2（3）在一个明确时间窗口依次触发：

1. `app_launch`
2. `training_sync_succeeded`
3. `highlight_generate_succeeded`
4. `highlight_save_succeeded`

在生产 Analytics 查询中确认同一安装标识、四个事件名和接收时间；确认请求仍只有 `project`、`event`、`device_id`，服务端记录仍只有 `project`、`event`、`time`、`device_id`。不得把原始 installation ID 写入文档。

- [ ] **Step 2: 确认 iPad、Watch 和 Debug 不发送 Analytics**

分别在独立时间窗口运行 iPad、Watch 和 Debug；在服务端与网络观察中确认没有新增 ShotMarker 产品事件。

- [ ] **Step 3: 安装或检查 GlitchTip CLI 并使用 OAuth 登录**

Run:

```bash
command -v glitchtip-cli || curl -fsSL https://glitchtip.com/install.sh | sh
glitchtip-cli --url https://glitchtip.zhangrh.shop login --method oauth
glitchtip-cli info
```

Expected: CLI 可用并通过浏览器 OAuth 登录；Token 不出现在命令、shell history 或仓库文件中。

- [ ] **Step 4: 上传本次 Archive dSYM**

从 GlitchTip 项目设置读取现有 organization/project slug，并仅保存在当前 shell 变量：

```bash
read -r "glitchtip_org?GlitchTip organization slug: "
read -r "glitchtip_project?GlitchTip project slug: "
glitchtip-cli --url https://glitchtip.zhangrh.shop debug-files upload \
  /tmp/ShotMarker-1.2-3-Submission.xcarchive/dSYMs \
  --org "$glitchtip_org" \
  --project "$glitchtip_project"
unset glitchtip_org glitchtip_project
```

Expected: 主 App 与 Watch dSYM 均上传成功；后台能按 UUID 找到文件。

- [ ] **Step 5: 使用同一 Archive 的可安装导出触发受控原生崩溃**

1. 从同一 Archive 导出 Development 或 Ad Hoc 安装包，不重新编译；
2. 安装到已注册真机；
3. 启动后从 Xcode 附加到 ShotMarker 进程；
4. 在 LLDB 执行 `expr (void)raise(6)`，继续进程直到崩溃；
5. 脱离调试器后重新启动 App，让 SDK 发送崩溃；
6. 删除导出的临时安装包，不提交 crash hook 到源码。

Expected: GlitchTip 收到 production 原生崩溃；App 自身堆栈有函数名和源码行，UUID 与上传的 Archive dSYM 一致。

- [ ] **Step 6: 验证新问题告警**

Expected: 受控崩溃触发配置的邮件或 Webhook；记录送达时间和渠道类型，不保存收件地址、Webhook URL 或消息原文。

## Phase 3：补齐 App Store Connect 资料

### Task 11：更新并上传三类设备截图

**Files:**

- Verify: `AppStoreScreenshots/2026-08-20-iphone-69/*.png`
- Verify: `AppStoreScreenshots/2026-08-20-iphone-65/*.png`
- Create: `AppStoreScreenshots/2026-08-21-ipad-13/*.png`
- Create: `AppStoreScreenshots/2026-08-21-watch-46/*.png`

- [ ] **Step 1: 复核现有 iPhone 截图**

保留当前 4 张顺序：

1. 训练记录
2. 集锦设置
3. 集锦就绪
4. 集锦完成

Run:

```bash
for file in AppStoreScreenshots/2026-08-20-iphone-69/*.png \
  AppStoreScreenshots/2026-08-20-iphone-65/*.png; do
  sips -g pixelWidth -g pixelHeight -g hasAlpha "$file"
done
```

Expected: 6.9 英寸为 1320×2868，6.5 英寸为 1284×2778，无 alpha，内容与 1.2（3）一致。

- [ ] **Step 2: 重拍 13 英寸 iPad 截图**

使用 1.2（3）和从真机流程导出的合成训练记录，生成 4 张 2064×2752 竖屏 PNG，沿用 iPhone 的四步顺序；不要继续使用 2026-05-20 的旧布局图。

Expected: iPad 布局无大片错误空白、截断或仅在 iPhone 可用的误导按钮；截图日期和内容不包含真实用户数据。

- [ ] **Step 3: 重拍 Apple Watch 截图**

使用 Apple Watch Series 11 46mm / watchOS 26.5 和 1.2（3），生成至少两张 416×496 PNG：

1. `长按开始`
2. 训练中 `双击/旋钮打点，长按结束`

所有语言使用同一 Watch 尺寸，不混用旧的 422×514 与 416×496 素材。

- [ ] **Step 4: 验证新素材并提交到仓库**

Run:

```bash
for file in AppStoreScreenshots/2026-08-21-ipad-13/*.png \
  AppStoreScreenshots/2026-08-21-watch-46/*.png; do
  sips -g pixelWidth -g pixelHeight -g hasAlpha "$file"
done
git diff --check
git add AppStoreScreenshots/2026-08-21-ipad-13 \
  AppStoreScreenshots/2026-08-21-watch-46
git commit -m "chore: 更新 1.2 iPad 与手表商店截图"
```

Expected: iPad 4 张、Watch 至少 2 张，尺寸正确，无 alpha，commit 成功。

- [ ] **Step 5: 在 Media Manager 上传并逐 tab 复核**

在 English (U.S.) 和简体中文本地化下分别检查：

- iPhone：6.9 英寸 4 张；6.5 英寸可保留 4 张或由 6.9 自动缩放，但两组不得出现旧图混排；
- iPad：13 英寸 4 张；
- Apple Watch：416×496 至少 2 张；
- 每个 tab 保存成功，退出再进入后计数和顺序不变。

### Task 12：填写英文和简体中文版本元数据

**External fields:** Description、Keywords、Support URL、What’s New、localization。

- [ ] **Step 1: English (U.S.) Description**

替换当前声称“不需要 server connection”的旧描述，使用：

```text
ShotMarker helps basketball players turn training videos into quick highlight clips. Use Apple Watch to mark moments during a shooting workout. When training ends, the session syncs to iPhone. Select matching videos from Photos, review marker coverage, generate a highlight, play it, and save it back to Photos.

Features:
• Start and end a training session on Apple Watch
• Mark moments by double-tapping or turning the Digital Crown
• Reliably sync completed sessions to iPhone
• Select up to 20 videos and prepare videos stored in iCloud
• Adjust the time before and after each marker
• Review video coverage before generating
• Track queued and completed highlight jobs
• Play generated highlights and save them to Photos
• Export local diagnostic logs for troubleshooting

No account is required. Training records, markers, source videos, and generated videos are not uploaded to ShotMarker’s servers. The Release iPhone app sends limited product-usage events and diagnostic/crash information. It does not use advertising or cross-company tracking. See the privacy policy for details.
```

- [ ] **Step 2: 新增 Simplified Chinese localization**

Description：

```text
ShotMarker 帮助篮球训练者把训练视频快速制作成集锦。训练时使用 Apple Watch 标记想保留的精彩时刻；训练结束后，记录会同步到 iPhone。选择相册中的对应视频，检查打点覆盖范围，生成并播放集锦，再手动保存回相册。

主要功能：
• 在 Apple Watch 上开始和结束训练
• 双击屏幕或转动数码表冠打点
• 将已完成训练可靠同步到 iPhone
• 最多选择 20 个视频，并准备存储在 iCloud 中的视频
• 调整每个打点前后的片段时长
• 生成前检查视频对打点的覆盖情况
• 查看排队中和已完成的集锦任务
• 播放生成结果并手动保存到相册
• 导出本地诊断日志用于排查问题

使用 ShotMarker 不需要账户。训练记录、打点、源视频和生成视频不会上传到 ShotMarker 服务器。Release iPhone App 会发送少量产品使用事件和诊断/崩溃信息，不用于广告或跨公司跟踪。详情请查看隐私政策。
```

- [ ] **Step 3: Keywords**

English：

```text
basketball,training,highlights,video,markers,workout,watch
```

简体中文：

```text
篮球,训练,集锦,视频,打点,手表,投篮
```

Expected: 每组不超过 100 bytes，不重复 App 名，不使用竞品名。

- [ ] **Step 4: What’s New**

English：

```text
Improved reliability and diagnostics for training sync, highlight generation, and Photos saving. Added limited, privacy-documented product analytics and crash reporting to help identify failures. No training records, markers, or videos are uploaded.
```

简体中文：

```text
提升训练同步、集锦生成和相册保存的可靠性与诊断能力；增加已在隐私政策中说明的有限产品统计和崩溃上报，用于定位失败。训练记录、打点和视频不会上传。
```

- [ ] **Step 5: URL 与其他版本字段**

填写并重新访问：

- Support URL：`https://zhangrh.shop/shotmarker/support`
- Privacy Policy URL：`https://zhangrh.shop/shotmarker/privacy`

Run:

```bash
curl -fsSLI https://zhangrh.shop/shotmarker/support
curl -fsSLI https://zhangrh.shop/shotmarker/privacy
curl -fsSL https://zhangrh.shop/shotmarker/privacy \
  | rg -i 'analytics|GlitchTip|crash|device|installation|分析|崩溃|设备|安装'
```

Expected: 两页返回 200；Support 有可用联系途径；Privacy 中英文都覆盖 Analytics、GlitchTip、安装标识、照片/视频和 HealthKit 边界。名称、类别、版权和 Marketing URL 没有明确问题时保持不变。

### Task 13：完成 App Privacy、年龄分级、辅助功能和可用性

- [ ] **Step 1: 更新 App Privacy Data Types**

选择 `Yes, we collect data from this app`，并填写：

| Data type | Linked to identity | Purpose | Tracking |
| --- | --- | --- | --- |
| Device ID | Yes | Analytics | No |
| Product Interaction | Yes | Analytics | No |
| Crash Data | No | App Functionality | No |
| Performance Data | No | App Functionality | No |
| Other Diagnostic Data | No | App Functionality | No |

不选择 Health、Photos、Videos 或 User Content：这些业务内容没有传给开发者或第三方服务器。不得继续保留 `No Data Collected`。

- [ ] **Step 2: 对照 Product Page Preview**

Expected: 预览只出现上述五类；Analytics 两类显示为 linked，诊断三类显示为 not linked；全部为 not used to track。

- [ ] **Step 3: 获得用户确认后 Publish App Privacy 回答**

说明：App Privacy `Publish` 会立刻改变当前公开产品页，不等待 1.2 上线。应在候选和隐私页面都验收后、正式提交前执行，以尽量缩短 1.1 标签提前变化的时间。

- [ ] **Step 4: 完成新版年龄分级问题**

在 `App Information > Age Ratings` 复核新问题。ShotMarker 没有聊天、公开资料、社交 feed、用户公开内容或内建社交网络；系统分享表单不等同于 App 内社交平台，因此相关能力按实际实现回答 `No`。

Expected: 计算结果仍为当前的 4+。若评级升高，停止并复查具体答案，不手动覆盖评级。

- [ ] **Step 5: 保持辅助功能声明诚实**

当前没有完成 VoiceOver、Voice Control、Larger Text、Dark Interface 等整项真机审计，因此本次保持“未指明/Not Indicated”，不因局部 `.accessibilityLabel` 就宣称完整支持。辅助功能标签另开 Change 验收。

- [ ] **Step 6: 复核 Pricing and Availability**

确认：

- 免费价格和税务类别保持现状；
- 目标国家/地区与 1.1 一致；
- App Distribution Method 保持 Public；
- 没有意外预购、下架或地区限制变化。

- [ ] **Step 7: 收敛未验收平台可用性**

公开商店当前把 iPad 兼容版同时提供给 Apple silicon Mac 和 Apple Vision Pro，而本项目没有对应产品验收。向用户展示当前两个开关；获得确认后，在 `Pricing and Availability` 取消：

- `Make this app available on Mac`
- `Make this app available on Apple Vision Pro`

Expected: iPhone、iPad、Apple Watch 保持可用；Mac 和 Apple Vision Pro 不再作为未经验证的兼容平台分发。若用户决定保留任一平台，则必须先把该平台加入 TestFlight/真机矩阵并通过后再提交。

### Task 14：填写 App Review 信息并建立最终提交草稿

- [ ] **Step 1: 选择 Build 3**

在 iOS App 1.2 的 `Build` 区域选择 1.2（3）并保存。

Expected: Build 行显示正确上传日期、Build 3、无 Missing Compliance 或 warning；不得选择 Build 1。

- [ ] **Step 2: 复核 App Review 联系信息**

确认现有姓名、电话、邮箱仍能在审核期间收到联系。App 不需要登录，`Sign-in required` 保持关闭，不填写演示账号。

- [ ] **Step 3: 填写 App Review Notes**

```text
No sign-in or demo account is required.

Review flow:
1. Install the iPhone app and the bundled Apple Watch app on a paired iPhone and Apple Watch.
2. On Apple Watch, long-press the green button to start a workout. Double-tap the screen or turn the Digital Crown to add markers, then long-press to end. The completed session syncs to iPhone.
3. On iPhone, open the synced session, choose a matching video from Photos, generate a highlight, then play or save it.

HealthKit is used only to run and write an Apple Watch workout session so the training interface can remain active. ShotMarker does not read or upload Health data. Photos access is used only for videos selected by the reviewer and for saving a generated highlight. No training records, markers, source videos, or generated videos are uploaded.

The Release iPhone app sends four fixed product-usage events using a random installation ID and sends limited error/crash diagnostics to the developer's services. There is no advertising or cross-company tracking. Privacy details: https://zhangrh.shop/shotmarker/privacy

The iPad app supports local training-record import and highlight processing. Live Apple Watch sync requires a paired iPhone.
```

- [ ] **Step 4: 选择发布方式**

设置：

- `Manually release this version`
- 对自动更新启用 7 天 phased release
- 不设置自动批准后立即发布日期

Expected: 审核通过后状态进入 `Pending Developer Release`，仍需人工点击发布。

- [ ] **Step 5: 保存并做页面级完整性检查**

从页面顶部滚动到底部，确认没有红色必填提示；退出再进入后 Build、文字、截图、发布方式仍保留。

## Phase 4：提交、审核、发布与收尾

### Task 15：双重确认后提交 App Review

**External side effect gate:** 汇总下面的 Go/No-Go 表并交给用户确认。

| Gate | Go 条件 |
| --- | --- |
| Git | main，候选 commit 明确，无未归属修改 |
| Tests | iPhone、Watch、iPad 全通过 |
| Archive | 1.2（3）、签名、隐私、语言、dSYM UUID 全通过 |
| Validate | 无 warning/error |
| TestFlight | Build 3 Complete，可安装 |
| Real devices | 全新安装、1.1 升级、Watch 同步、生成/播放/保存、iPad 全通过 |
| Analytics | 四事件通过，非 iPhone/Debug 不发送 |
| GlitchTip | dSYM、符号化、告警通过 |
| Screenshots | iPhone、iPad、Watch 当前且尺寸正确 |
| Metadata | 英文、简中、URL、What’s New 全保存 |
| Privacy | 五类数据、政策、manifest 一致并已 Publish |
| Review | Build 3、联系信息、Notes、manual release 完整 |

- [ ] **Step 1: 点击 Add for Review**

在版本页右上角点击 `Add for Review`，创建或加入本次 iOS Draft Submission。

Expected: 版本状态变为 `Ready for Review`。这一步还没有把 App 发送给审核。

- [ ] **Step 2: 在 App Review 草稿复核项目**

进入左侧 `App Review` 或右下 `Draft Submissions`，确认草稿只包含 iOS App 1.2，不意外带入 In-App Purchase、In-App Event、Custom Product Page 或其他平台项目。

- [ ] **Step 3: 再次获得最终提交确认**

向用户展示 Draft Submission 摘要。只有用户明确说提交后，点击 `Submit for Review`。

Expected: 状态进入 `Waiting for Review`；若仍为 `Ready for Review`，说明只完成了 Add for Review，需要检查草稿。

- [ ] **Step 4: 记录提交证据**

在私有台账记录提交日期、版本、Build 和状态，不保存账号截图中的个人标识。

### Task 16：跟踪审核并处理消息

- [ ] **Step 1: 监控状态**

关注 `Waiting for Review`、`In Review`、`Pending Developer Release` 或拒绝状态；每次记录实际时间，不推测审核时长。

- [ ] **Step 2: 回答审核问题**

围绕以下事实作答：

- 不需要登录；
- Watch 负责训练打点并通过配对 iPhone 同步；
- HealthKit 只写 workout、不读取或上传健康数据；
- Photos 只处理用户选择和主动保存的视频；
- Analytics/GlitchTip 不含训练记录、打点或视频，不用于广告或 tracking。

若审核要求改代码，创建新的 Build 4+，重新执行受影响的候选门，不替换或伪装 Build 3。

### Task 17：批准后人工发布并做生产冒烟

**External side effect gate:** 状态必须为 `Pending Developer Release`，并再次获得用户明确发布确认。

- [ ] **Step 1: 点击 Release This Version**

确认弹窗中为 iOS 1.2，然后点击 `Confirm`。

Expected: 版本开始 phased release；Apple 说明公开可见可能需要最多 24 小时。

- [ ] **Step 2: 验证公开 App Store 页面**

检查至少两个 storefront：

- 版本为 1.2；
- Description 不再声称完全不联网；
- What’s New 正确；
- Privacy 不再显示 No Data Collected，五类数据与用途正确；
- 语言包含简体中文；
- iPhone、iPad、Watch 截图顺序正确；
- Mac/Vision 可用性与用户确认的决定一致；
- Support 和 Privacy 链接可访问。

- [ ] **Step 3: 从公开 App Store 安装并冒烟**

在不影响测试数据的设备上安装/升级公开 1.2，完成启动、Watch 同步、生成、播放和保存；确认 Analytics、GlitchTip 没有新异常峰值。

- [ ] **Step 4: 观察 phased release**

在 7 天内每日查看崩溃、关键 Analytics 成功事件和用户反馈。发现严重回归时暂停 phased release，并先评估修复 Build，不删除历史证据。

### Task 18：更新公开/私有事实并归档 Change

**Files:**

- Modify: `docs/current/status.md`
- Modify: `docs/current/architecture.md`
- Modify: `docs/current/quality.md`
- Modify: `docs/current/release.md`
- Modify when contract changed: `docs/current/analytics.md`
- Modify: `docs/README.md`
- Modify after sync: `docs/private.local/shotmarker/current/release.md`
- Modify after sync: `docs/private.local/shotmarker/current/observability.md`
- Move: this plan to `docs/archive/2026-08/`

- [ ] **Step 1: 先更新公开 current**

只写当次真实证据：

- `status.md`：1.2 当前审核/发布阶段和剩余风险；
- `architecture.md`：Build/语言配置、合并后的隐私 manifest 和 Sentry 边界；
- `quality.md`：实际测试数、模拟器、真机、Archive、Validate、dSYM/符号化结果；
- `release.md`：1.2（3）、截图、TestFlight、App Review、上线日期和公开商店复核；
- `analytics.md`：只在事件或隐私契约实际变化时修改；否则更新外部验收日期摘要即可。

每份 current 保持 300 行以内，不写开发流水账，不把“提交审核”写成“已经上线”。

- [ ] **Step 2: 同步并更新独立私有仓库**

Run:

```bash
git -C docs/private.local status --short --branch
git -C docs/private.local pull --rebase
```

只有同步成功且私有工作区干净时，才记录 App Store Connect、TestFlight、设备、Analytics 和 GlitchTip 的日期化结果。私有仓库单独提交：

```bash
git -C docs/private.local add shotmarker/current/release.md \
  shotmarker/current/observability.md
git -C docs/private.local commit -m "docs: 记录 ShotMarker 1.2 发布验收"
git -C docs/private.local push
```

Expected: 私有 commit/push 与公开仓库完全分开；无凭据或个人标识。

- [ ] **Step 3: 归档本计划并更新入口**

1. 从 `docs/README.md` 的“正在进行的变更”移除本计划；
2. 将本计划移动到 `docs/archive/2026-08/2026-08-21-app-store-1-2-submission-plan.md`；
3. 保留未实现的语音 Change 入口。

- [ ] **Step 4: 最终文档与仓库校验**

Run:

```bash
git diff --check
test ! -e docs/changes/2026-08-21-app-store-1-2-submission-plan.md
test -e docs/archive/2026-08/2026-08-21-app-store-1-2-submission-plan.md
find docs/current -name '*.md' -print0 \
  | xargs -0 wc -l
rg -n 'TO[D]O|TB[D]|FIXM[E]|PLACEHOLD[E]R|YOU[R]_' \
  docs/current docs/archive/2026-08/2026-08-21-app-store-1-2-submission-plan.md
rg -n 'No Data Collected|does not require.*server connection' docs/current
git status --short
```

Expected: diff 无空白错误；current 均不超过 300 行；没有未解释占位符或过期披露；工作区修改都能归属到本次发布。

- [ ] **Step 5: 提交公开文档收尾**

Run:

```bash
git add docs/current docs/README.md
git add -A docs/changes/2026-08-21-app-store-1-2-submission-plan.md \
  docs/archive/2026-08/2026-08-21-app-store-1-2-submission-plan.md
git commit -m "docs: 记录 1.2 商店提交与发布状态"
```

Expected: commit 成功；仅在用户明确授权时执行 `git push`。

## Stop Conditions

出现以下任一情况立即停止当前阶段并报告：

- Build 3 已在 App Store Connect 使用，或 Xcode Validate/Upload 自动改成其他构建号；
- 当前 `main` 出现无法归属的用户修改；
- 五类 App Privacy 回答与候选二进制/manifest 不一致；
- iPad 或 Watch 的必需截图缺失、尺寸不合法或仍展示旧 UI；
- TestFlight 不能安装、升级丢数据、Watch 同步失败或 iPad 主要布局不可用；
- 四个 Analytics 事件缺失、出现额外敏感字段，或 iPad/Watch/Debug 意外发送；
- GlitchTip dSYM UUID 不匹配、原生崩溃不符号化或告警不送达；
- Support/Privacy URL 非 200 或披露仍声称完全不联网；
- Organizer Validate、App Store Connect processing 或 Draft Submission 出现 warning/error；
- App Review 草稿意外包含其他审核项目；
- 任何外部 Publish、Submit 或 Release 动作尚未获得用户确认。

## Definition of Done

- [ ] 仓库与嵌入式 Watch App 均为 1.2（Build 3）。
- [ ] Privacy manifest、App Privacy 回答、公开隐私政策和实际网络行为一致。
- [ ] 二进制语言与中文 UI 一致，商店有英文和简体中文元数据。
- [ ] iPhone、iPad、Watch 截图均为当前候选且符合 Apple 尺寸要求。
- [ ] iPhone、Watch、iPad 自动化、Archive、签名、Validate、dSYM 全通过。
- [ ] TestFlight 全新安装、1.1 升级、Watch 主链路、iPad、Analytics、GlitchTip、告警全通过。
- [ ] App Review 信息完整，Build 3 被选中，发布方式为人工发布并启用 phased release。
- [ ] 用户分别确认了隐私发布、上传、提交审核和最终发布动作。
- [ ] 公开 1.2 上线后产品页与生产主流程完成复核。
- [ ] 公开 current、独立私有台账和归档计划均按真实证据收尾。

## Primary References

- [Apple：Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)
- [Apple：Choose a build to submit](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit/)
- [Apple：Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [Apple：TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)
- [Apple：Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Apple：Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Apple：App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple：Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
- [Apple：Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- [Apple：Select a release option](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option)
- [Apple：Release an update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases)
- [Apple：Manage Apple Vision Pro availability](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-apple-vision-pro)
- [Apple：Running iOS apps on macOS](https://developer.apple.com/documentation/apple-silicon/running-your-ios-apps-in-macos)
- [GlitchTip：CLI](https://glitchtip.com/documentation/cli/)
- [GlitchTip：Cocoa SDK](https://glitchtip.com/sdkdocs/cocoa/)
