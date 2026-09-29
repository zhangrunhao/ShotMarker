# ShotMarker 1.3 App Store 提交计划

> 2026-09-29 提交工作已完成并归档。以下原计划作为历史保留，不作为新的审批或验收要求。用户后续明确确认 iPhone/Watch 均能正常打开，决定跳过后续验收并授权直接提交。

## 实际完成与范围调整

- 用户完成 1.3（3）Archive、上传和 TestFlight 内部分发，并报告手机与 Watch 均可打开。
- Codex 通过 Chrome 电脑控制核对 Build 3，保存实际 English (U.S.) 更新说明、描述与审核备注；披露旧本地数据清理、前台生成、权限与有限远端观测。
- 核对商店五类隐私披露，沿用已有 iPhone/iPad/Watch 截图；未重新拍摄或声称旧截图已覆盖 1.3 新界面。
- 执行 Add for Review，再执行 Submit for Review；后台显示 Waiting for Review。当前事实见 [发布状态](../../current/release.md)，详细私有证据由独立私有台账维护。
- 发布方式保留审核通过后手动发布；本次未发布到商店。
- 新自动测试、完整真机/升级/iPad/VoiceOver 验收、生产观测及最终签名/dSYM 复核没有新增通过证据。原清单中未勾选项不是已通过，也不再是本次提交的待执行前置任务。
- 准备时测试命令因许可未接受以 69 退出；后续实际 Archive 与上传成功，旧阻塞不能继续代表当前分发状态。

同日后续按用户要求拍摄新素材、撤回并重新提交，见 [商店截图记录](2026-09-29-app-store-screenshots.md)。上面的旧截图说明仅描述首次送审，不代表当前商店素材。

## 原计划

> **For agentic workers:** 后续执行使用 `superpowers:executing-plans`，逐项更新真实结果；本计划不是已完成发布的证明。

**Goal:** 将当前 1.3 功能整理为可审阅的提交材料，并完成候选构建、分发验收和商店准备，直至用户确认实际送审。

**Architecture:** 使用现有 iPhone App 与嵌入式 Watch App，不增加业务功能。对同一代码基线完成测试、Archive、TestFlight 和商店资料核验；公开事实、私有分发证据和 Notion 提交文案各自维护。

**Tech Stack:** SwiftUI、XCTest、Swift Package Manager、Xcode、App Store Connect、TestFlight、Notion。当前安装 Xcode 27.0（27A266a），许可未接受；既有验证使用 Xcode 26.6。

**Spec:** 用户于 2026-09-29 确认“当前版本没啥问题了，开始准备 1.3 的提交”。产品与有效决定见 [产品事实](../../current/product.md)、[发布状态](../../current/release.md)；本次没有新增功能规格。

## 已确认范围与边界

- 商店目标版本为 1.3；当前 App/Watch Debug、Release 配置均为 Build 3。该构建号能否上传仍需后台核验，不把“配置为 3”写成“3 可用”。
- 当前代码基线为 `10a9f354de480e31e8a45cff5cb2f987ff603926`，开始准备时公开、私有工作区均干净。
- 本版包括序数位置/字号/透明度、逐片段范围调整与保留/排除、可编辑集锦任务，以及连续确认预览与时间轴修复；不加入语音口令或技术统计。
- 已生效的数据世代清理决定保持不变；必须在更新说明前部披露。不能把预期的一次清理算作回归，也不能忽略范围外删除或反复清理。
- 产品范围为 iPhone + Watch；二进制仍支持 iPad，因此商店截图和候选验收必须覆盖 iPad。部署下限保持 iOS 26.4、watchOS 26.2。
- 本次授权为提交准备。上传、实际送审和发布前，展示已核验的候选与材料，依据届时用户授权执行。准备工作不等待额外确认。
- 不覆盖用户修改，不安装候选到带有待保留数据的用户设备，不替用户接受软件许可或账户协议。
- App Store Connect、TestFlight、签名 Archive、真机及生产观测的详细事实只记入独立私有台账；编辑前先检查干净并同步，分别提交和推送。

## Review Focus

1. 旧版升级只清理已披露的 App 自有数据；Photos、HealthKit、App 外文件不受影响，第二次启动不清理新数据。
2. 旧 Watch 尚未同步的数据不得在切割后重新出现；新训练应正常同步。
3. 合并片段后跳到远处或另一个视频，预览、胶片和局部时间轴应对应新片段。
4. 停止、后台、异常退出或生成失败不损坏任务和旧成片；手动重新生成成功后才替换。
5. iPad 布局、真实 Release 网络边界与隐私披露不能由 iPhone Debug 测试替代。

## Task 1：固定材料与核验记录

**Files / Objects:** 本计划、`docs/current/{status,quality,release,architecture}.md`、`docs/README.md`、[Notion 1.3 条目](https://app.notion.com/p/3cc387d074aa808bbffae296051b2918)。

- [x] 核对 Git 状态、当前版本、现有 Change 和用户确认的范围。
- [x] 静态检查 App/Watch 四个配置均为 1.3（3），两个 Info.plist 声明 `zh-Hans`，主 App `ITSAppUsesNonExemptEncryption=false`。
- [x] `plutil -lint` 检查工程、两个 Info.plist 和隐私清单；用 Python 读取 plist 验证隐私类型及属性精确集合。
- [x] 核对五类数据：Device ID、Product Interaction 为 linked/Analytics；Crash、Performance、Other Diagnostic 为 unlinked/App Functionality；全部不用于 Tracking。
- [x] 核对 Required Reason API：UserDefaults `CA92.1`、File Timestamp `C617.1`、System Boot Time `35F9.1`。
- [x] 在现有 Notion 1.3 条目准备中英文 What's New、英文 App Review Notes、升级披露、验收与截图清单；更新项目首页。另一个 Uncertain 的同名条目不合并或删除。
- [x] 检查公开链接：Support/Privacy/How-to 返回 HTTP 200，但仅取得 SPA 入口，不能宣称正文已验收。
- [x] Apple Lookup 美区返回版本 1.2、更新时间 2026-08-29；中国区结果为空。Notion 的 1.2.1 记录与实际商店版本需区分，后台地区与版本仍待核验。

更新说明必须包含：旧 iPhone/Watch 训练及打点、任务、审核、App 内视频副本和成片、待同步数据、缓存、日志、偏好不自动迁移；系统相册、HealthKit、App 外导出及远端历史保留。提醒升级前把所需成片保存到相册。不得声称后台持续生成、语音识别或业务云同步已实现。

Notion 保留可粘贴文案；仓库 current 是实现与验证事实源。Notion 的 `Waiting for Review` 仅为已有内部分类，页面已明确本次未实际送审。

## Task 2：恢复工具链并运行候选测试

**Files:** 不预设代码改动；结果先保存到忽略的 `build/release-1.3/`，再按证据更新 `docs/current/quality.md`。

- [ ] 用户在本机完成 Xcode 27.0 许可确认及所需组件安装。
- [ ] 运行以下只读命令，确认实际可用工具链和 Simulator destination：

```bash
xcodebuild -version
xcrun simctl list devices available
xcodebuild -project ShotMarker.xcodeproj -scheme ShotMarker -showdestinations
xcodebuild -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -showdestinations
```

- [ ] 在专用测试 Simulator 运行完整 iPhone、Watch 测试；iPad 运行 iPhone scheme 的兼容测试和主要布局验收。使用上述输出中实际存在、满足部署下限的设备 ID，分别设置 `SHOTMARKER_PHONE_SIM`、`SHOTMARKER_WATCH_SIM`、`SHOTMARKER_IPAD_SIM` 后执行：

```bash
mkdir -p build/release-1.3
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker \
  -destination "platform=iOS Simulator,id=${SHOTMARKER_PHONE_SIM:?请选择可用测试模拟器}" \
  -resultBundlePath build/release-1.3/phone.xcresult
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp \
  -destination "platform=watchOS Simulator,id=${SHOTMARKER_WATCH_SIM:?请选择可用测试模拟器}" \
  -resultBundlePath build/release-1.3/watch.xcresult
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker \
  -destination "platform=iOS Simulator,id=${SHOTMARKER_IPAD_SIM:?请选择可用测试模拟器}" \
  -resultBundlePath build/release-1.3/ipad.xcresult
```

首次执行使用新结果路径；重试保留既有结果，改用带时间后缀的路径。通过条件为各命令退出 0，结果包无未解释失败或跳过；记录实际测试数、系统和代码，不能直接沿用 393/31。

- [ ] 从干净 DerivedData 执行 Release Simulator 构建：

```bash
xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarker \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/release-1.3/simulator-derived-data
```

核对 App/Watch 最终 Info.plist、隐私清单、dSYM 和 DEBUG 专用入口不进入 Release。构建警告逐项确认，不记录为 warning-free。

2026-09-29 实际尝试 `xcodebuild test`，命令以 69 退出，提示 Xcode 许可尚未接受；测试未启动，未生成本次通过证据。

## Task 3：生成签名候选并核对分发条件

**Objects:** App Store Connect 1.3、Xcode Organizer、忽略目录中的 Archive、独立私有 `shotmarker/current/release.md`。

- [ ] 后台只读核对线上版本、1.3 版本记录、Build 占用、协议和地区。当前浏览器连接超时，尚无该项证据。
- [ ] 若 Build 3 已被使用，先选定首个可用的更大构建号，统一 App/Watch 配置并重新验证；不得复用、覆盖或依赖自动改号。
- [ ] 使用通过测试的同一代码生成 Archive：

```bash
xcodebuild archive -project ShotMarker.xcodeproj -scheme ShotMarker \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/release-1.3/ShotMarker-1.3.xcarchive \
  -derivedDataPath build/release-1.3/archive-derived-data
```

- [ ] 对主 App 和嵌入 Watch 分别核对版本、Bundle ID、签名、最低系统、语言；用 `codesign --verify --strict` 校验，逐个用 `dwarfdump --uuid` 比对二进制与 dSYM。确认实际产物包含隐私声明，DEBUG 测试场景没有打包。
- [ ] 执行 Organizer Validate，保存版本/构建号及真实结果。发现自动管理构建号与候选不一致时先协调，不把本地 Build 3 当作上传事实。
- [ ] 候选通过后展示摘要，由用户确定上传；上传后等 processing 完成，再核对 TestFlight 实际 Build 和可安装性。

## Task 4：TestFlight、升级与生产链路验收

**Objects:** 专用 iPhone/Watch/iPad 测试设备、同一正式候选、私有发布与观测台账。

- [ ] 全新安装完成训练、同步、选视频、审核、生成、播放和保存。
- [ ] 专用设备从当前商店版本升级：预先准备旧训练、任务、成片及待同步 Watch 记录；记录升级前后 App 沙盒与系统资源边界，不记录用户标识。验证一次清理、固定 cutover、旧载荷只 ACK、新训练正常导入、第二次启动保留新数据。
- [ ] 合并片段后连续确认到远处片段、跨源视频和退出重开；核对预览/胶片/时间轴与实际导出。
- [ ] 修改视频、时长、样式、确认项，验证任务重开、旧成片保留、新成片替换和相册保存。
- [ ] 验证主动停止、后台、进程退出、导出失败；任务保留且不会自动继续。重新生成后结果正确。
- [ ] iPad 核对布局、权限弹窗和主要操作；Watch 核对真实配对、联机升级与重试。补充 VoiceOver 核验并记录覆盖边界。
- [ ] Release iPhone 核验四个固定 Analytics 事件和字段；Debug、Watch、iPad 不发产品事件。线上响应、存储、崩溃符号化/dSYM 与告警需单独证据，不能只依据客户端测试。

## Task 5：商店截图与元数据

**Files / Objects:** 当前候选截图、Notion 文案、App Store Connect 1.3 草稿；网站由 `zhangrh.shop` 仓库维护。

- [ ] 使用合成或已获许可的视频和训练，拍摄真实候选 UI：训练/任务首页、视频与样式设置、片段图集、范围编辑、成片播放/保存。
- [ ] 拍摄 iPad 主要流程、Watch 开始/训练/结束状态；保留已有历史素材，不能把旧 1.2 页面标为 1.3 新 UI。
- [ ] 按 [Apple 截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) 校验：可选 iPhone 1320×2868、13 英寸 iPad 2064×2752 或 2048×2732、Watch 416×496；无 alpha 通道。提供合规 6.9 英寸图时，6.5 英寸是否补图按后台实际需要处理。
- [ ] 核对并填写现有本地化的 What's New 和审核 Notes；检查描述中不再承诺后台持续生成或完全不联网。
- [ ] 确认 App Review 联系方式、无需登录、Watch/HealthKit/Photos 操作说明，选择已验收的 Build；联系信息不进文档。
- [ ] 用真实浏览器打开 Support、Privacy、How-to，检查正文、路由和 1.3 流程。需要改网站时在其所属仓库处理；HTTP 200 不代替正文验收。
- [ ] 核对 App Privacy 与实际二进制、SDK、政策一致：五类数据、用途、linked 与 tracking；检查年龄分级和加密问卷，不能推定旧回答仍有效。
- [ ] 核对地区、Mac/Vision 兼容可用性与发布方式。人工发布可作为建议供用户确定，不把未确认的 phased release 选项写为生效决定。

## Task 6：送审与收尾

- [ ] 候选、测试、Validate、TestFlight、升级、截图、隐私、网站、联系信息和发布方式全部有证据后，展示最终 1.3 提交摘要。
- [ ] 在用户明确要求实际提交后，按 [Apple 提交流程](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app) 操作：Add for Review 形成草稿，核对仅含预期项目，再 Submit for Review；记录后台返回的真实状态。
- [ ] 审核问题、批准与最终发布分别按实际进展处理；“已送审”不等于“已上线”。最终发布需有用户授权。
- [ ] 先更新公开 current，再单独同步和更新私有证据，更新 Notion 进度；完成本 Change 后将计划移至 `docs/archive/2026-09/` 并更新入口。

## 准备阶段完成界限（历史）

提交材料和静态准备已完成；测试、签名 Archive、TestFlight 和实际送审尚未完成。解除 Xcode 许可阻塞后从 Task 2 继续，不能依据用户的日常使用反馈或历史测试跳过候选验收。
