# 任务编辑入口验证

- 日期：2026-10-25。
- 实现提交：`7f3d18b`，基于 `be5ac70`；正式修改仅为 `HighlightTaskRow.swift` 与 `TrainingSessionHighlightView.swift`，同步调整 `EditableHighlightTaskUITests.swift` 的既有用例。
- 用户要求：编辑任务配置页移除“片段序数”；任务卡片通过明确的“编辑任务”按钮进入配置，摘要和空白处不导航。

## 实现

原卡片将摘要包在编辑按钮中，点击文字可导航。现在摘要为普通展示，编辑入口位于操作区域，沿用原按钮样式与至少 44 点高度。横向放不下时使用原有纵向布局。播放、保存相册、重新生成、删除和停止行为保持不变；保存期间仍只禁用原操作组，编辑入口保持原可用性。

已有任务配置页不再插入序数设置区块。新建流程的默认样式、已有任务保存的样式数据和逐片段序号调节保留。

## 验证

环境：Xcode 27.1（27A9275），iPhone 17 Pro / iOS 26.5 Simulator，专用设备 `ShotMarker Editable Tasks QA`，浅色外观。

- 修改前先运行两项扩展后的既有 UI 用例，均按预期失败：点击摘要仍进入编辑页；配置页仍出现“片段序数”。结果为 `/tmp/ShotMarkerTaskEntry-red.xcresult`。
- 修改后运行任务 UI 类全部 7 项及逐段序号模式用例，8 通过、0 失败、0 跳过；命令退出码 0，结果为 `/tmp/ShotMarkerTaskEntry-green.xcresult`。
- 覆盖摘要文字/右侧空白不导航、明确编辑按钮进入配置、删除确认、有符号偏移保存、无效范围阻止审核、保留已有确认、排队/生成仅停止、停止后恢复操作与最大辅助字号。
- 逐段序号用例确认模式互斥及收起操作列表后字号滑杆继续可用。
- 已检查普通字号及最大辅助字号卡片截图；按钮文字完整且操作可达。附件导出至 `/tmp/shotmarker-task-entry-all-attachments/`。结果包和截图是本地临时文件，可能被清理。
- 独立代码复核未发现待修问题；`git diff --check` 通过。

```sh
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker \
  -destination 'platform=iOS Simulator,id=098856ED-DC0A-4AC0-BCE7-419ABA6E359F' \
  -derivedDataPath /tmp/ShotMarkerFramingQA \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ShotMarkerUITests/EditableHighlightTaskUITests \
  -only-testing:ShotMarkerUITests/HighlightClipMediaNavigationUITests/testNumberOperationListSeparatesModesAndStaysActiveWhenCollapsed \
  -resultBundlePath /tmp/ShotMarkerTaskEntry-green.xcresult
```

上述自动验证为 Debug Simulator 专项检查，没有重跑完整单元/UI 套件、Watch、深色、iPad、完整真机剪辑或 Release，也未生成或安装新的分发产物。测试构建保留既有并发及 AppIntents 等警告，不宣称无警告。首页和底部导航改版不属于本次实现。

## 后续开发签名运行

同日按用户要求，将 main `7adac03`（包含实现 `7f3d18b`，其后仅追加文档）进行 generic iOS Debug 构建。构建退出码 0，日志含 `BUILD SUCCEEDED`；App 为 1.3（3），`codesign --verify --deep --strict` 通过。本次增量构建仍有 AppIntents metadata 提示。

已完成开发签名覆盖安装、正常前台启动与随后同一进程存活确认。真机核验的权威状态和安装记录由[私有发布状态](../../private.local/shotmarker/current/release.md)维护；启动验证不等同完整训练、编辑或导出验收。

公共构建与签名证据：`/tmp/shotmarker-task-entry-device-build.log`、`/tmp/shotmarker-task-entry-device-signing.log`。这些临时文件可能被清理。
