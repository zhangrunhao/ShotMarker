# 编辑控件样式验证

- 日期：2026-10-25。
- 首轮实现：`326b200`，生产改动限于 `HighlightClipEditorView.swift`；UI 测试仅增加展开面板截图留存。用户试用后的最终微调为 `8831c5b`，见文末。
- 范围：用户选择靛蓝播放/暂停按钮，优化“操作”入口及展开按钮面板。模式互斥、折叠不退出序号操作、字号滑杆、保存继承和恢复逻辑保持原有行为。

## 实现与检查

播放按钮使用适配浅深色的靛蓝实底。操作入口使用浅靛蓝圆角底、当前模式标记及展开箭头；展开面板的当前模式用实底和勾选区分，恢复按钮保持中性。普通字号下三个按钮等宽，辅助字号下按钮纵排且图标文字横排，允许自然换行。

首次验证发现展开面板挤占高度：最大辅助字号的第三项操作不可达，普通字号播放按钮低于既有可见区域断言。调整面板间距、内边距和辅助字号标签布局后，原断言全部通过，没有放宽测试条件。随后实际截图发现普通字号模式标记换行，最终移除入口装饰图标并固定模式标记的自然宽度；辅助字号分支未改变。

独立代码复核检查了交互逻辑、禁用反馈、44/52 点最小点击高度及辅助字号布局，未留下待修问题。最终浅色/深色普通字号截图和调整后的浅色最大辅助字号截图均已查看。

## 自动验证

环境：Xcode 27.1，iPhone 17 Pro / iOS 26.5 Simulator，专用设备 `ShotMarker Editable Tasks QA`。测试串行运行，最终恢复浅色外观。

| 结果包（位于 `/tmp/`） | 范围 | 结果 |
| --- | --- | --- |
| `ShotMarkerEditorControls-light.xcresult` | 初版样式的 4 项专项 UI | 2 通过、2 失败；上述高度问题 |
| `ShotMarkerEditorControls-light3.xcresult` | 空间与辅助字号布局修正后的 4 项专项 UI | 4 通过、0 失败、0 跳过 |
| `ShotMarkerEditorControls-final-light.xcresult` | 最终入口宽度调整，浅色模式/折叠用例 | 1 通过、0 失败、0 跳过 |
| `ShotMarkerEditorControls-final-dark.xcresult` | 同一最终源码，深色模式/折叠用例 | 1 通过、0 失败、0 跳过 |

中间的 `light2` 运行因继续调整辅助字号入口而主动中止，不作为通过证据；较早深色运行由最终深色验证替代。

4 项专项覆盖：最大辅助字号下决定/导航/播放可达；取景保存、连续继承及手动恢复；序号与取景互斥、折叠后滑杆继续显示；序号布局保存、继承及手动恢复。运行命令：

```sh
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=ShotMarker Editable Tasks QA' \
  -derivedDataPath /tmp/ShotMarkerFramingQA \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ShotMarkerUITests/HighlightClipConfirmationUITests/testMaximumDynamicTypeKeepsDecisionsAndNavigationAccessible \
  -only-testing:ShotMarkerUITests/HighlightClipMediaNavigationUITests/testFramingControlsPersistContinueAndManualNavigationRestoresOwnValue \
  -only-testing:ShotMarkerUITests/HighlightClipMediaNavigationUITests/testNumberOperationListSeparatesModesAndStaysActiveWhenCollapsed \
  -only-testing:ShotMarkerUITests/HighlightClipMediaNavigationUITests/testNumberPlacementSavesInheritsAndManualNavigationRestoresOwnLayout \
  -resultBundlePath /tmp/ShotMarkerEditorControls-light3.xcresult
```

最终浅深色运行只选择上述模式/折叠用例。最后入口宽度调整未重复执行最大辅助字号等其余 3 项；相关辅助字号分支未改变。测试附件为实际原生界面截图，媒体使用合成视频。结果包和导出附件位于本地临时目录，可能被系统清理。

## 构建、安装与范围

- 验证日期：2026-10-25（Asia/Shanghai）。
- 授权范围：安装用户选择的靛蓝播放按钮与操作面板样式更新，启动 App 后供用户试用。
- 实际构建代码基线：公开仓库本地 main，`326b2001e0b82fff6f1e9b91d10517c50b23ca93`。
- App：ShotMarker 1.3（Build 3），`com.heji.ShotMarker`。
- 构建环境：Xcode 27.1，generic iOS Debug。
- 设备型号、系统与开发者模式沿用本任务稍早实际设备详情核验：iPhone 16，iOS 26.6.1，开发者模式启用；本次未重复核验设备详情，连接类型未核对。

### 结果与证据

1. Debug 真机构建退出码为 0，日志包含 `BUILD SUCCEEDED`；App 包的 Bundle ID 和版本核对通过。
2. `codesign --verify --deep --strict` 返回码为 0，签名验证通过。签名日志为空，成功依据为本次命令返回码。
3. 安装 JSON 的 `outcome` 为 `success`，返回的 App Bundle ID 正确。
4. 启动 JSON 的 `outcome` 为 `success`，为正常前台激活启动；启动参数为空，`startStopped` 为 false，没有使用 UI 测试启动参数。
5. 随后的进程查询 JSON 的 `outcome` 为 `success`；比较启动与进程列表，确认同一 ShotMarker 进程仍在运行。用户已可开始试用。

本次本地临时证据：

- `/tmp/shotmarker-editor-controls-device-build.log`
- `/tmp/shotmarker-editor-controls-device-signing.log`
- `/tmp/shotmarker-editor-controls-device-install.json`
- `/tmp/shotmarker-editor-controls-device-launch.json`
- `/tmp/shotmarker-editor-controls-device-processes.json`
- 本任务稍早的设备详情：`/tmp/shotmarker-number-device-details.json`

已重新读取构建成功标记、安装/启动/进程查询三份 JSON 的成功摘要，比较启动与进程查询结果中的进程身份，并核对本任务稍早设备详情中的型号、系统与开发者模式。临时文件可能被系统清理，路径不构成永久留存保证。原始设备 JSON、签名输出和构建日志不进入文档仓库；本记录不保存设备名、设备标识、进程标识、容器路径、个人签名信息或登录凭据。

### 验证范围

- 已验证样式更新版本的开发签名构建、签名、安装、正常前台启动与随后进程存活，安装完成后交由用户试用。
- 本次未验收个人训练视频的完整剪辑与导出，也没有执行 Watch 真机、升级、VoiceOver 或生产服务验收。
- 未生成或上传分发 Archive，未查询 App Store Connect、TestFlight、审核或上架状态。

本轮未重复底层单元全套、完整 iPhone UI 套件、Watch、Release 或分发验证。最终普通字号浅深色经过专项复测；最大辅助字号只检查浅色。安装启动不等同个人视频的完整剪辑、导出或真机 VoiceOver 验收。此前序号布局全量回归见[序号布局验证](2026-10-25-clip-number-layout-validation.md)。

## 同日试用后的配色与入口微调

用户进一步要求播放按钮恢复最初蓝色、减轻“操作 · 取景”入口本身的视觉重量，并保留展开面板。实现提交 `8831c5b` 仅修改 `HighlightClipEditorView.swift`：移除播放按钮的 tint 覆盖，恢复历史代码的系统默认蓝色；入口改为次要灰色常规文字和小箭头，移除底色、边框及胶囊。展开面板的颜色值与布局不变，原共享色属性仅更名为 `panelSelectedTint`。

入口继续保留至少 44 点点击高度、完整触区、当前模式、展开/收起无障碍名称及辅助字号自然增高。模式、保存、恢复与折叠逻辑没有改动。独立代码复核及 `git diff --check` 通过；未新增测试或放宽既有断言。

同一模拟器、相同测试命令和 DerivedData，仅调整所选用例及结果包：

| `/tmp/` 结果包 | 所选既有用例 | 结果 |
| --- | --- | --- |
| `ShotMarkerEditorControls-blue-light.xcresult` | `testMaximumDynamicTypeKeepsDecisionsAndNavigationAccessible`、`testNumberOperationListSeparatesModesAndStaysActiveWhenCollapsed` | 2 通过、0 失败、0 跳过 |
| `ShotMarkerEditorControls-blue-dark.xcresult` | `testNumberOperationListSeparatesModesAndStaysActiveWhenCollapsed` | 1 通过、0 失败、0 跳过 |

已查看浅深色实际展开截图、浅色序号模式收起后滑杆截图及浅色最大辅助字号截图；播放为系统蓝，入口保持单行且无外框，展开面板保持靛蓝。结束后恢复模拟器浅色外观。本次未重新执行取景继承/序号保存用例、完整单元/UI 套件、Watch 或 Release 验证。

### 同日最终样式的开发签名安装

- 验证日期：2026-10-25（Asia/Shanghai）。
- 授权范围：安装系统蓝播放按钮与灰色轻量操作入口调整，展开后的操作面板保持已确认样式，启动 App 后供用户试用。
- 实际构建代码基线：公开仓库本地 main，`8831c5b64c65d7cd65a9cdeaba982f7faa08e359`。
- App：ShotMarker 1.3（Build 3），`com.heji.ShotMarker`；Xcode 27.1，generic iOS Debug。
- 本轮重新读取设备详情并核验：iPhone 16，iOS 26.6.1，开发者模式启用。连接类型未核对。

#### 结果与证据

1. Debug 真机构建退出码为 0，日志包含 `BUILD SUCCEEDED`；App 包的 Bundle ID 和版本核对通过。
2. `codesign --verify --deep --strict` 返回码为 0，签名验证通过。签名日志为空，成功依据为本次命令返回码。
3. 本轮设备详情、安装、启动和后续进程查询四份 JSON 的 `outcome` 均为 `success`；安装返回的 App Bundle ID 正确。
4. 最终成功启动为正常前台激活，启动参数为空、`startStopped` 为 false，没有使用 UI 测试启动参数。
5. 比较成功启动结果与后续进程列表，确认同一 ShotMarker 进程仍在运行，用户已可试用。

本轮本地临时证据：

- `/tmp/shotmarker-editor-controls-blue-device-build.log`
- `/tmp/shotmarker-editor-controls-blue-device-signing.log`
- `/tmp/shotmarker-editor-controls-blue-device-details.json`
- `/tmp/shotmarker-editor-controls-blue-device-install.json`
- `/tmp/shotmarker-editor-controls-blue-device-launch.json`
- `/tmp/shotmarker-editor-controls-blue-device-processes.json`

已重新核对构建成功标记、四份 JSON 的成功摘要、正常启动选项及同一进程存活。证据仅记录摘要与临时文件路径；不保存设备名、设备标识、进程标识、签名身份或原始日志。临时文件路径不构成永久留存保证。

#### 验证范围

- 本轮仅验证新样式版本的开发签名构建、签名、安装、正常前台启动及随后进程存活，交由用户试用。
- 未验收完整剪辑、Watch 真机、升级、VoiceOver、商店分发或生产服务；未生成或上传分发 Archive，未查询 App Store Connect、TestFlight、审核或上架状态。
- 首轮 `326b200` 安装事实保留在本文前部；后续状态见[发布状态](../../current/release.md)中注明日期的核验。
