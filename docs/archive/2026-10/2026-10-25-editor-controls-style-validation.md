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

本地 main `326b200` 的 generic iOS Debug 构建成功，App 为 1.3（Build 3），严格签名验证通过；随后完成开发签名安装、正常启动及进程存活检查，交由用户试用。真机事实的权威记录见[私有发布状态](../../private.local/shotmarker/current/release.md)。

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

本地 main `8831c5b` 的 generic iOS Debug 构建退出码 0，日志包含 `BUILD SUCCEEDED`，App 1.3（3）严格签名验证通过。已完成开发签名安装、正常前台启动和同一进程存活检查，继续供用户试用；真机权威记录仍见[私有发布状态](../../private.local/shotmarker/current/release.md)，不扩大为完整剪辑或商店分发验收。
