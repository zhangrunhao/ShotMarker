# 片段取景实现与验证

日期：2026-10-23

代码范围：`9d078a5..b744efa`，分支 `codex/clip-framing`。最终完整测试覆盖 `b744efa`；之后仅更新文档。

## 结果与范围

- 完整 iPhone suite：460 项通过，0 失败，0 跳过；441 项单元测试、19 项 UI 测试。测试构建及 xcodebuild 均退出 0。
- Task 1 模型/存储/规划、Task 2 编辑器/导航/预览、Task 3 逐片段导出均通过独立规格与质量审查。导出新引入的两处协议 Sendable 声明已修复并复审通过。
- 整体分支独立审查通过，无可操作问题；核对了模型、事务、继承/撤销、预览与导出集成，以及完整测试成功日志。没有遗留或暂缓问题。
- 本次没有合并 main、推送、安装真机、运行 Watch suite 或生成分发产物。同日较早 `ca7b956` 的手机安装证据不覆盖此变更。

实现提交：

- `a764836 feat: 增加片段取景模型与兼容存储规划`
- `69b2acf feat: 导出每段独立取景并保持编号布局`
- `8bf3fb7 fix: 对齐视频合成器的可发送属性契约`
- `b744efa feat: 支持连续审核继承取景与手动独立切换`

## 最终完整测试

环境：Xcode 27.1（27A9275），iPhone 17 Pro / iOS 26.5 Simulator，Debug，`/tmp/ShotMarkerFramingQA`。所有构建串行执行，关闭并行测试及自动诊断采集。

```sh
xcrun simctl bootstatus 098856ED-DC0A-4AC0-BCE7-419ABA6E359F -b
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker \
  -destination 'platform=iOS Simulator,id=098856ED-DC0A-4AC0-BCE7-419ABA6E359F' \
  -derivedDataPath /tmp/ShotMarkerFramingQA \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/ShotMarkerFramingFinal.xcresult
xcrun xcresulttool get test-results summary \
  --path /tmp/ShotMarkerFramingFinal.xcresult
```

- 日志：`/tmp/shotmarker-framing-final.log`
- 结果包：`/tmp/ShotMarkerFramingFinal.xcresult`
- 结束时间：2026-10-23 15:53；`TEST SUCCEEDED`，summary 的 `passedTests` / `totalTestCount` 均为 460，`failedTests` / `skippedTests` 均为 0。
- UI 分布：4 项任务操作、6 项确认审核、5 项真实媒体导航/取景、4 项时间轴拖动。
- 真实取消用例记录一项 QoS 运行警告：User-interactive 调用方取消时等待 AVFoundation Utility 线程；测试通过，无崩溃或超时。SDK 日志仍有 operatingSystemBuild `invalidDigitCount` / debugger lookup 提示。
- 任务阶段编译曾有既有测试 actor 隔离/Sendable、AppIntents 提示；最终构建复用同一 DerivedData，不能把增量日志没有重复编译警告解释为全新构建 warning-free。

## 规格验收对应

| 验收 | 实际证据 |
| --- | --- |
| 1 同源保留、排除传递取景 | `HighlightClipFramingEditorTests` 验证只有持久化成功才发一次性导航；真实界面测试精确设置 2.2×、保留和排除后的取景 |
| 2 分阶段调整独立保存 | 工作副本与保存快照测试证明后续调整不回改前项；真实 UI 确认后手动回看已保存取景。未逐一人工操作 15 段完整示例 |
| 3 手动跳转自身值或原画面 | 状态测试覆盖已保存/未保存目标；真实底部缩略图跳转核对恢复 |
| 4 继承不 dirty、主动修改、失败不串 | 临时入口基线、全部改回基线、失败保持草稿与目标无变化测试；既有未保存导航 UI 通过 |
| 5 已保存目标临时覆盖 | 进入继承值、离开不写盘、手动重开旧值的状态测试 |
| 6 两种恢复独立 | 范围恢复保持取景、原画面恢复保持范围的状态断言；真实恢复按钮回到 1× |
| 7 跨源、末项、退出不残留 | 状态测试、既有末项与跨源 UI；自动导航携带明确目标/来源，普通打开不读取全局值 |
| 8 完整撤销与迟到加载 | nil / 明确原画面 / 放大取景三种撤销前值；新增迟到元数据单元测试与真实媒体加载中撤销 UI |
| 9 合并、重复范围与时长 | 纯规划等价取景合并、不同取景分段且保留重叠；真实成片时长及关系文案断言 |
| 10 可见区域、方向、编号 | 真实导出像素覆盖 1×、2×、2.2×、4× 中心/四角、旋转、镜像、原生竖屏、多源和首段竖屏画布；透明编号仍裁切；编号在缩放前后大小/位置不变且切点正确；真实 UI 竖屏与旋转预览像素、拖动/pinch/暂停 |
| 11 兼容、保护、事务与旧成片 | schema 1 文件读取/无变化保持字节，正常写入 2；旧快照缺字段兼容，明确 null 与非法值拒绝；损坏/未来版本保护、预期 revision、真实 Runner 替换/重启及旧成片保留 |
| 12 最大字号、可访问性与旧流程 | 显式 accessibility5 下恢复/倍率/保留/排除/底部条完整可见；未载入预览内拖动可滚动页面；顶部前后按钮移除；19 项 UI 含完整时间轴回归。VoiceOver 倍率/四向动作与边界提示经过代码检查，未宣称人工朗读验收 |

媒体验证还覆盖 silent → tone → silent 的逐采样音频对齐、真实开始渲染后的取消与残留文件清理、执行快照不受后续修改影响。

## 过程中的实际问题与修正

- Simulator 冷启动曾返回 Busy；显式 boot/bootstatus 后成功，不作为产品失败。
- 原生 layer instruction + Core Animation 编号原型在该 Simulator 的 QuartzCore/IOSurface 路径产生 SIGTRAP。采用一个 CI 自定义 compositor 完成方向、裁切、画布适配和位图编号，保持单 composition、单次编码。该证据不能推断所有设备的 Core Animation 都不可靠。原日志 `/tmp/shotmarker-export-green.log`。
- 两处新合成器属性使用的 `[String: Any]` 与当前 SDK `NS_SWIFT_SENDABLE` 导入不符，改为 `[String: any Sendable]`，聚焦像素测试和复审通过。
- 恢复按钮的 44pt 约束移入实际 Button label；预览可访问元素固定在视口，防止被缩放的播放器子视图扩大其坐标。
- 当前 Simulator 的动态字号 launch argument 未实际生效，改用 DEBUG harness 的 `.accessibility5`，并断言控件位于导航栏与固定底栏之间。
- 未载入时仅在手势回调 guard 仍会挡住页面滚动；新增真实 UI 失败探针后，对禁用手势层关闭 hit testing，最终滚动与正常手势回归均通过。
- 导出像素测试使用原视频解码像素作比较，音频按逐采样时间统计内部窗口，避免把有损编码颜色和跨边界 PCM buffer 误当作产品错误。

## 聚焦证据与目视检查

- 基础模型/存储/规划最终 67 项通过。
- 导出聚焦 38 项通过：`/tmp/shotmarker-export-final.log`、`/tmp/ShotMarkerFramingQA/Logs/Test/Test-ShotMarker-2026.10.23_15-34-32-+0800.xcresult`；Sendable 静态修正后另一个混合来源像素用例通过，日志 `/tmp/shotmarker-export-sendable.log`。
- 编辑器聚焦运行覆盖 87 项相关单元与 11 项相关 UI，最终修正证据 `/tmp/ShotMarkerFramingQA-task2-final-green.xcresult`，竖屏/旋转像素证据 `/tmp/ShotMarkerFramingQA-task2-ui-fixes.xcresult`。最终整套测试重新覆盖全部用例。
- 已查看 `/tmp/ShotMarkerFramingEvidence/` 的中心、边缘、旋转、镜像、混合画布和编号 PNG，编号正向且位置稳定；也查看真实 UI 的横屏 2.2×、竖屏/旋转 2× 与最大字号截图。
- UI 截图：`/tmp/ShotMarkerFramingQA-task2-landscape-2.2x.png`、`/tmp/ShotMarkerFramingQA-task2-portrait-2x.png`、`/tmp/ShotMarkerFramingQA-task2-rotated-2x.png`、`/tmp/ShotMarkerFramingQA-task2-max-type-controls.png`、`/tmp/ShotMarkerFramingQA-task2-max-type-strip-visible.png`。
- 最终公开文档本地链接检查通过；current 各文件均不超过 300 行。工作树没有私有仓库挂载，保留的私有验证链接不可在此工作树解析；未改动私有台账。`git diff --check` 通过。

## 实施判断及代价

1. 已批准完整规格后直接实施，不另设批准关卡；若对规格理解有误，会产生返工。
2. 任务阶段只跑相关测试，最后统一跑完整 iPhone suite；集成问题可能到最终阶段才暴露并需要返工。
3. 基础接口稳定后并行开发互不重叠的 UI 与导出，构建保持串行；若共享接口假设有误，需要集成修正。
4. 原生编号渲染实际崩溃后改用 CI 合成；保持用户批准的行为，但增加缓冲区、请求完成与取消管理代码，需要专门的媒体测试和审查。

## 未覆盖边界

- 没有新真机安装或用户原始训练视频验收；没有 VoiceOver 人工朗读、完整 iPad、Watch 联机、Release/Archive、App Store、生产 Analytics 或 GlitchTip 验收。
- 当前 BGRA SDR 路径；HDR/广色域保真未验收。测试源为全画幅方形像素 H.264，非方形像素、非零 clean aperture、任意斜切变换未新增支持或验收。
- 本记录与临时日志反映本次代码与环境，不代表分发版本，也不替代未来手机实用反馈。

## 同日后续：合并、开发签名安装与正常启动

用户随后明确要求合并主分支并在连接的手机运行。main 从 `9d078a5` 快进到 `291a0a4`；与 `b744efa` 比较，产品、单元/UI 测试及工程目录无差异，因此沿用前述完整测试证据，没有重复运行相同代码的 Simulator suite。以下设备证据仅属于后续安装阶段。

- 验证日期：2026-10-23（Asia/Shanghai）。
- 授权范围：将已完成的片段取景方案合并到公开仓库本地 main，并在当前连接的 iPhone 上安装、运行，供用户实测。
- 代码基线：公开仓库本地 main，`291a0a48a67cfa9b71923ca09182b00e43b4e852`。
- App：ShotMarker 1.3（Build 3），`com.heji.ShotMarker`。
- 环境：Xcode 27.1，Debug 真机构建；iPhone 16，iOS 26.6.1，有线连接，开发者模式启用。

### 结果与证据

1. main 已快进合并取景分支。真机构建退出码为 0，日志包含 `BUILD SUCCEEDED`；App 包版本和 Bundle ID 核对通过。
2. `codesign --verify --deep --strict` 退出码为 0，签名验证通过。
3. `devicectl install app` 退出码为 0，安装结果 JSON 的 `outcome` 为 `success`。
4. 正常前台启动并终止旧实例，启动退出码为 0，JSON 的 `outcome` 为 `success`。未传入测试启动参数，未附加调试器。
5. 随后的进程查询成功，已核对同一 ShotMarker 进程仍在运行。

本次本地临时证据：

- `/tmp/shotmarker-framing-device-build.log`
- `/tmp/shotmarker-framing-device-signature.log`
- `/tmp/shotmarker-framing-device-install.json` 及同名 `.log`
- `/tmp/shotmarker-framing-device-launch.json` 及同名 `.log`
- `/tmp/shotmarker-framing-device-processes.json` 及同名 `.log`

已再次读取构建成功标记、三份 JSON 成功状态，并比较启动与进程查询结果中的进程身份。临时文件可能被系统清理，路径不构成永久留存保证。原始设备 JSON、签名输出与构建日志不进入文档仓库；本记录不保存设备名、UDID、容器路径、个人签名信息或登录凭据。

### 验证范围

- 已验证本版开发签名构建、签名、安装、正常前台启动和启动后的进程存活。
- 构建仍有既有 handler Sendable 警告和 AppIntents 元数据提示，不宣称构建无警告。
- 本次没有代替用户执行篮球训练、个人视频导入、完整取景剪辑与导出验收，也没有执行 Watch 真机、升级、VoiceOver 或生产观测验收。
- 未生成或上传分发 Archive，未查询 App Store Connect、TestFlight、审核或上架状态。
- 本轮只做本地提交，没有推送远端。
