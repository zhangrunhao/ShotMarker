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

本地 main 从 `7cd8eb3` 快进至 `b5aa379`；产品及测试目录与 `111303d` 无差异。

### 同日后续：开发签名安装与正常启动

- 验证日期：2026-10-23（Asia/Shanghai）。
- 授权范围：将片段编辑精简与带符号时间偏移改动合并到公开仓库本地 main，并安装、运行到用户已重新连接和解锁的 iPhone，供用户实测。
- 构建代码基线：公开仓库本地 main，`b5aa3797d8ca2386b9cca50ee5f4d7faefa4abe3`。
- App：ShotMarker 1.3（Build 3），`com.heji.ShotMarker`。
- 环境：Xcode 27.1，Debug 真机构建；iPhone 16，iOS 26.6.1，有线连接、已配对，开发者模式启用。

#### 结果与证据

1. main 已快进合并本轮改动。Debug iphoneos 构建退出码为 0，日志包含 `BUILD SUCCEEDED`；App 包的 Bundle ID 和版本核对通过。
2. `codesign --verify --deep --strict` 退出码为 0，签名验证通过。
3. 安装 JSON 的 `outcome` 为 `success`，返回的 App Bundle ID 正确。
4. 启动 JSON 的 `outcome` 为 `success`，记录为前台激活启动。启动参数为空，没有测试启动参数或测试环境变量；未附加调试器。
5. 稍后的进程查询 JSON 的 `outcome` 为 `success`，已核对同一 ShotMarker 进程仍在运行。

本次本地临时证据：

- `/tmp/shotmarker-simplify-device-build.log`
- `/tmp/shotmarker-simplify-device-signing.log`
- `/tmp/shotmarker-simplify-device-install.json`
- `/tmp/shotmarker-simplify-device-launch.json`
- `/tmp/shotmarker-simplify-device-processes.json`

已再次读取构建成功标记、三份 JSON 成功状态，并比较启动与进程查询结果中的进程身份。首次进程查询使用了不适用于 URL 字段的过滤表达式，命令失败；随后改用 App 名称搜索并成功核对。这是查询命令问题，没有据此判断 App 启动失败。

临时文件可能被系统清理，路径不构成永久留存保证。原始设备 JSON、签名输出和构建日志不进入文档仓库；本记录不保存设备名、UDID、进程标识、容器路径、个人签名信息或登录凭据。

#### 验证范围

- 已验证本版开发签名构建、签名、安装、正常前台启动和启动后的进程存活。
- 本次没有代替用户完成个人训练视频的完整剪辑与导出验收，也没有执行 Watch 真机、升级、VoiceOver 或生产观测验收。
- 未生成或上传分发 Archive，未查询 App Store Connect、TestFlight、审核或上架状态。
- 本轮只做本地提交，没有推送远端。

## 覆盖边界

本轮不扩展为语音剪辑，没有改 Watch 代码；未重跑 Watch 完整套件。真机完整训练/剪辑、iPad、VoiceOver 人工操作、HDR/广色域、生产观测和正式 Archive 仍无本轮完整验收证据。已通过的自动回归和安装启动不替代这些项目。既有 SDK/AppIntents/Sendable 与媒体取消的 QoS 提示按实际日志保留，不宣称无警告。
