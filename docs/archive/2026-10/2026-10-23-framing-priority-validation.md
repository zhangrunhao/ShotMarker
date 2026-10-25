# 已保存取景优先验证

日期：2026-10-23
基线：`5b23ff1`；实现代码：`3fe813f`。

## 用户确认的行为

- 目标片段已保存取景时始终使用它，包括明确保存的 1× 原画面；连续保留或排除也不能用上一段取景覆盖它。
- 目标没有保存取景，且通过同源上一段的保留/排除成功后自动进入时，临时复用上一段。未再次确认前不写入目标片段。
- 点击全部片段中的任何一项（包括当前高亮项）只打开该段自己的保存值；没有则显示 1×。已有主动未保存调整继续使用放弃确认，继承本身不算主动修改。
- 跨来源不继承，保存失败不发布导航；时间范围、存储 schema、导出及取景手势不变。

## 实现

编辑器仅在目标 `framing == nil` 时采用传入取景，并据实际采用情况设置继承标记。每次打开编辑器使用独立导航身份，片段身份仍用于数据和缩略图查找；点击当前项也重新建立时间轴及媒体任务。

显式跳转前释放旧媒体一次，离开回调避免重复释放，防止同片段重开时旧视图取消新胶片加载。播放器继续每次独立创建，迟到结果仍受原有加载代次校验。

## 验证证据

先修改回归，再观察旧实现失败：`/tmp/ShotMarkerFramingPriority-red.xcresult` 与 `/tmp/shotmarker-framing-priority-red.log`。9 项相关单元中保存值优先场景有 16 个预期断言失败；1 项真实媒体 UI 在重点击当前段后仍显示 2.2×，而预期 1×。无编译错误作为 RED 证据。

全部 464 项通过，含 453 项单元测试与 11 项审核/媒体 UI；0 失败、0 跳过，xcodebuild 退出码 0。结果包 `/tmp/ShotMarkerFramingPriority-green.xcresult`，日志 `/tmp/shotmarker-framing-priority-green.log`。

GREEN 覆盖全部 iPhone 单元测试、片段审核 UI 和真实媒体导航 UI。实际流程验证自动继承、目标既有 2× 优先、手动打开保存值/无保存值、当前项重开后的 8 帧加载及播放推进；单元验证保留/排除两种入口、明确 1× 与放大值、无效跨源导航、失败不导航及 dirty 基线。

~~~sh
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker \
  -destination 'platform=iOS Simulator,id=098856ED-DC0A-4AC0-BCE7-419ABA6E359F' \
  -derivedDataPath /tmp/ShotMarkerFramingQA \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ShotMarkerTests \
  -only-testing:ShotMarkerUITests/HighlightClipConfirmationUITests \
  -only-testing:ShotMarkerUITests/HighlightClipMediaNavigationUITests \
  -resultBundlePath /tmp/ShotMarkerFramingPriority-green.xcresult
~~~

本轮没有改配置或独立时间轴控件，未重复其他 11 项配置/独立时间轴 UI。最近全量 475 项通过仍属于此前 `111303d`，不把它宣称为新优先级版本的全量测试。未改 Watch、未重跑 Watch 或新建分发 Archive。

独立代码审查检查完整本轮差异、现有导航路径及同片段清理边界，无未解决问题。文档先更新 current 再保存本完成记录；旧取景规格保留为历史，当前优先级以 product 和本记录为准。

## 同日后续：开发签名安装与正常启动

本轮合并后的本地 main `3d79e72` 与实现 `3fe813f` 的产品及测试目录一致，未重复运行相同代码的 Simulator suite。

- 验证日期：2026-10-23（Asia/Shanghai）。
- 授权范围：将取景保存值优先与点击片段重新打开规则合并到公开仓库本地 main，并安装、运行到用户已重新连接和解锁的 iPhone，供用户实测。
- 实际构建代码基线：公开仓库本地 main，`3d79e72341e1262239de34adef33c27406c7ba13`；之后的 `c139f4f` 仅追加文档，不改变本次安装产物。
- App：ShotMarker 1.3（Build 3），`com.heji.ShotMarker`。
- 环境：Xcode 27.1，generic iOS Debug 构建；iPhone 16，iOS 26.6.1，有线连接、已配对，开发者模式启用。

### 结果与证据

1. main 已快进合并本轮改动。Debug 真机构建退出码为 0，日志包含 `BUILD SUCCEEDED`；App 包的 Bundle ID 和版本核对通过。
2. `codesign --verify --deep --strict` 退出码为 0，签名验证通过。
3. 本轮重新连接后的设备详情确认设备在线、有线连接、已配对且开发者模式启用。
4. 安装 JSON 的 `outcome` 为 `success`，返回的 App Bundle ID 正确。
5. 启动 JSON 的 `outcome` 为 `success`，记录为前台激活启动。启动参数为空，没有 UI 测试启动参数；未附加调试器。
6. 稍后的进程查询 JSON 的 `outcome` 为 `success`，已核对同一 ShotMarker 进程仍在运行。

本次本地临时证据：

- `/tmp/shotmarker-framing-priority-device-build.log`
- `/tmp/shotmarker-framing-priority-signing.log`
- `/tmp/shotmarker-framing-priority-device-connected.json`
- `/tmp/shotmarker-framing-priority-device-install.json`
- `/tmp/shotmarker-framing-priority-device-launch.json`
- `/tmp/shotmarker-framing-priority-device-processes.json`

已再次读取构建成功标记、安装/启动/进程查询三份 JSON 成功状态，并比较启动与进程查询结果中的进程身份。临时文件可能被系统清理，路径不构成永久留存保证。原始设备 JSON、签名输出和构建日志不进入文档仓库；本记录不保存设备名、UDID、进程标识、容器路径、个人签名信息或登录凭据。

### 验证范围

- 已验证本版开发签名构建、签名、安装、正常前台启动和启动后的进程存活。
- 本次没有代替用户完成个人训练视频的完整剪辑与导出验收，也没有执行 Watch 真机、升级、VoiceOver 或生产观测验收。
- 未生成或上传分发 Archive，未查询 App Store Connect、TestFlight、审核或上架状态。
- 本轮只做本地提交，没有推送远端。
