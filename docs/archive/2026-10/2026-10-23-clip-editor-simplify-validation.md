# 片段编辑精简与有符号范围验证

日期：2026-10-23

## 范围与实现

基线为本地 main `7cd8eb3`；产品与测试最终代码为 `111303d`。本次删除单独继承提示、四列绝对时间、上次决定/撤销提示及单段恢复默认范围，显示片段内进度与总长，保留取景和时间轴行为。两侧默认偏移支持 -20…20，和至少 1 秒；任务写入 schema 3，兼容读取 1/2。

修改默认偏移时，安全的已确认范围、排除状态和取景继续保留；新默认窗口完全落到来源之外时保留旧合法基线。配置入口使用实际协调结果，仍有确认片段时允许进入审核。既有来源匹配、范围裁切与最短片段规则不变。

## 自动验证

- 相关范围/存储测试先观察到失败，再实现。50 项相关单元测试与 7 项配置 UI 测试通过，0 失败/跳过；日志 `/tmp/ShotMarkerSimplify-offsets-green.log`，结果 `/tmp/ShotMarkerSimplify-offsets-green.xcresult`。
- 覆盖前 11 / 后 -2、前后零值、负前值、非法及非有限输入；UserDefaults、真实任务文件和执行快照往返；schema 1/2 读取/no-op 不改字节、写入 3、未来版本保护；默认窗口移出来源时确认/取景不丢失。
- 配置 UI 操作真实 Stepper，提交和重开前 11 / 后 -2；零长禁用后纠正可提交；默认窗口移出源仍能审核确认项。使用合成 H.264、本地真实 Store 和正式配置界面。
- 编辑 UI 聚焦覆盖重开排除项改为保留、同源取景继承/手动恢复、跨来源迟到媒体隔离、未载入预览区域滚动、竖屏取景手势及最大字号真实播放与底部导航。
- 完整测试结果：475 项通过，含 453 项单元测试与 22 项 UI 测试；0 失败、0 跳过，xcodebuild 退出码 0。。

完整回归命令：

~~~sh
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker \
  -destination 'platform=iOS Simulator,id=098856ED-DC0A-4AC0-BCE7-419ABA6E359F' \
  -derivedDataPath /tmp/ShotMarkerFramingQA \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/ShotMarkerSimplifyFinal.xcresult
~~~

环境：Xcode 27.1（27A9275），专用 iPhone 17 Pro / iOS 26.5 Simulator。完整日志 `/tmp/shotmarker-simplify-final.log`。合成媒体与 DEBUG 测试入口未写入用户手机，不使用用户原视频作测试夹具。

## 界面复核与诊断边界

普通字号截图中，预览、单行 `0.0 / 17.0 秒`、播放及固定保留/排除按钮完整显示。accessibility5 使用实际媒体，播放/暂停、确认后下一段、全部片段重开及恢复原画面均可滚动到可见区域。

最初最大字号用例从空白边距起手，没有触发 ScrollView。内容内文字起手可正常滚动；测试辅助改为在可见非交互文字区域拖动，保留几何可见性断言。尝试的 contentShape 产品改动无效，已撤回；没有把测试手势问题记作产品修复。

聚焦 `06` 用例通过后，多图缩放预览曾把蓝色按钮文字显示为空。对相同原始 PNG 做像素校准，按钮中央白色文字比例为 20.1975%；单图 original 读取显示完整文字，`07` 临时像素诊断也通过，排除了产品缺陷。未修改 AnyLayout/按钮样式，临时诊断测试已移除。

本地截图：`/tmp/ShotMarkerSimplifyUI-normal-editor.png`、`/tmp/ShotMarkerSimplifyUI-max-playback.png`、`/tmp/ShotMarkerSimplifyUI-max-strip.png`、`/tmp/ShotMarkerSimplifyUI-max-framing.png`。最大字号正式通过结果为 `/tmp/ShotMarkerSimplifyUI-max-20261023-06.xcresult`；这些临时文件不是仓库交付依赖。

## 独立审查与整合

独立审查完整 `7cd8eb3..111303d` 变更及周边配置、持久化、规划和导航代码，最终无未解决问题。修正了仍推荐“恢复默认范围”的两处旧错误提示，以及 current 中一条旧正值范围说明。审查没有把此前的 460 项结果冒充本轮验证；随后本轮完整 475 项回归通过。

本地 main 从 `7cd8eb3` 快进至 `b5aa379`；产品及测试目录与 `111303d` 无差异。同日 main `b5aa379` 的 Debug iphoneos 构建退出码 0，App 为 1.3（3），codesign 深度严格验证通过。安装、正常前台启动及后续同一进程存活均已核实；没有使用测试启动参数。构建日志 `/tmp/shotmarker-simplify-device-build.log`，签名日志 `/tmp/shotmarker-simplify-device-signing.log`。

设备安装详情由私有仓库当前发布状态及 `2026-10-23-clip-editor-simplify-iphone-install.md` 维护。公开仓库不保存设备标识、原始用户数据或凭据。没有远程推送、商店提交或新分发 Archive。

## 覆盖边界

本轮不扩展为语音剪辑，没有改 Watch 代码；未重跑 Watch 完整套件。真机完整训练/剪辑、iPad、VoiceOver 人工操作、HDR/广色域、生产观测和正式 Archive 仍无本轮完整验收证据。已通过的自动回归和安装启动不替代这些项目。既有 SDK/AppIntents/Sendable 与媒体取消的 QoS 提示按实际日志保留，不宣称无警告。
