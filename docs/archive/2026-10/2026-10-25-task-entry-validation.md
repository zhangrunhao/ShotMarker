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

## 同日后续：开发签名安装与正常启动

- 验证日期：2026-10-25（Asia/Shanghai）。
- 授权范围：将刚提交的任务编辑入口版本运行到连接的 iPhone，启动 App 后供用户试用。
- 实际构建代码基线：公开仓库本地 main，`7adac039b7a0383c7c6987d5a5baa23e51caa00d`；包含任务入口实现 `7f3d18b`。
- App：ShotMarker 1.3（Build 3），`com.heji.ShotMarker`。
- 构建环境：Xcode 27.1，generic iOS Debug；构建开始时公开工作区干净。
- 本轮重新读取设备详情并核验：iPhone 16，iOS 26.6.1，开发者模式启用；连接类型未核对。

### 结果与证据

1. Debug 真机构建退出码为 0，日志包含 `BUILD SUCCEEDED`；App 包的 Bundle ID 和版本核对通过。
2. `codesign --verify --deep --strict` 返回码为 0，日志确认 `valid on disk` 与满足 Designated Requirement。
3. 覆盖安装退出码为 0，安装 JSON 的 `outcome` 为 `success`，返回的 App Bundle ID 正确。
4. 解锁后启动退出码为 0，启动 JSON 的 `outcome` 为 `success`；`activatedWhenStarted` 为 true，启动参数为空，`startStopped` 为 false，是正常 App 入口的前台激活启动。
5. 随后进程查询退出码为 0，JSON 的 `outcome` 为 `success`；比较成功启动与运行中进程结果，确认同一 ShotMarker 进程仍在运行，匹配数为 1。

首次启动因手机锁屏未成功；用户解锁后按上述正常入口启动并完成进程存活核验。

本次本地临时证据：

- `/tmp/shotmarker-task-entry-device-build.log`
- `/tmp/shotmarker-task-entry-device-signing.log`
- `/tmp/shotmarker-task-entry-device-details.json`
- `/tmp/shotmarker-task-entry-device-install.json`
- `/tmp/shotmarker-task-entry-device-install.log`
- `/tmp/shotmarker-task-entry-device-launch-unlocked.json`
- `/tmp/shotmarker-task-entry-device-launch-unlocked.log`
- `/tmp/shotmarker-task-entry-device-processes-unlocked.json`
- `/tmp/shotmarker-task-entry-device-processes-unlocked.log`

已重新核对构建成功标记、签名结果、设备与安装/启动/进程查询 JSON 的成功摘要、正常启动选项及同一进程存活。证据仅记录摘要与临时文件路径；不保存设备名、设备标识、进程标识、容器路径、签名身份或原始日志。临时文件可能被系统清理，路径不构成永久留存保证。

### 验证范围

- 已验证任务编辑入口更新版本的开发签名构建、签名、覆盖安装、正常前台启动与随后进程存活，交由用户试用。
- 本次未验收完整训练、剪辑与导出流程，也没有执行 Watch 真机、升级、VoiceOver 或生产服务验收。
- 未生成或上传分发 Archive，未查询 App Store Connect、TestFlight、审核或上架状态。

本轮增量构建仍有 AppIntents metadata 提示，不声称无警告。
