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

本轮已合并到本地 main `3d79e72`，产品及测试目录与 `3fe813f` 一致；generic iOS Debug 构建退出码 0、codesign 深度严格验证通过，App 为 1.3（3）。日志 `/tmp/shotmarker-framing-priority-device-build.log` 和 `/tmp/shotmarker-framing-priority-signing.log`。本轮尚未安装到手机；设备工具在构建前后均显示未连接，已告知用户重新连接。此前安装成功的 `b5aa379` 不代表本轮优先级修改已在设备上运行。
