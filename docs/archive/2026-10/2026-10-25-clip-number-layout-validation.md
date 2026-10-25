# 片段独立序号布局验证

- 日期：2026-10-25。
- 范围：操作列表、取景/序号互斥模式、逐段位置与字号、连续继承、固定画布预览、逐段导出和兼容存储。
- 代码：`38c88c0`（功能与测试提交）；本记录不代表真机或商店分发验收。
- 环境：Xcode 27.1，iPhone 17 Pro / iOS 26.5 Simulator，专用 DerivedData `/tmp/ShotMarkerFramingQA`。

## 自动验证

| 执行 | 结果 | 证据 |
| --- | --- | --- |
| 基线取景编辑与标签布局 | 16 通过 | `/tmp/ShotMarkerNumberLayout-baseline.xcresult` |
| 新操作入口红测试 | 缺少操作列表入口，按预期失败 | `/tmp/ShotMarkerNumberLayout-red.xcresult` |
| schema 4 与超长标签红测试 | 旧实现拒绝 schema 4、长标签宽度超出画布，按预期失败 | `/tmp/ShotMarkerNumberLayout-data-red.xcresult` |
| 合法中心精度回归红测试 | 2 项失败，6 个断言定位 setter 量化合法中心 | `/tmp/ShotMarkerNumberLayout-precision-red.xcresult` |
| 首轮完整 iPhone 回归 | 499 项，497 通过、2 失败、0 跳过：按钮点击高度不足，以及新增控件后旧 helper 仍要求播放一屏可见 | `/tmp/ShotMarkerNumberLayout-full1.xcresult` |
| 修复后完整 iPhone 回归 | 499 通过，0 失败、0 跳过；475 单元 + 24 UI | `/tmp/ShotMarkerNumberLayout-full2.xcresult` |
| 最终代码单元与深色序号 UI 复测 | 477 通过，0 失败、0 跳过；全部 475 单元 + 2 新增 UI | `/tmp/ShotMarkerNumberLayout-final-dark.xcresult` |

所有 xcodebuild 由主代理串行执行，关闭并行测试；使用真实临时文件、任务 Store、AVFoundation 导出及原生 UI，未使用用户视频。

复现命令（以专用模拟器名称表达 destination，不记录设备标识；结果包路径在重跑时需换为未使用的名称）：

```sh
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=ShotMarker Editable Tasks QA' \
  -derivedDataPath /tmp/ShotMarkerFramingQA \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/ShotMarkerNumberLayout-full2.xcresult
```

完整 499 项通过后仅补充了自定义解码器的 `nonisolated` 注解与保存位置的 UI 非空断言。最终限定复测使用相同构建设置，选择全部 `ShotMarkerTests` 及 `HighlightClipMediaNavigationUITests` 中两项 `testNumberOperationListSeparatesModesAndStaysActiveWhenCollapsed`、`testNumberPlacementSavesInheritsAndManualNavigationRestoresOwnLayout`，并在测试前切换专用 Simulator 为深色、结束后恢复原浅色外观。

## 验收对应

| 契约 | 证据 |
| --- | --- |
| 取景默认开、序号默认关、两者可全关、序号关恢复取景；主动开取景关闭序号 | 原生操作模式 UI 用例 |
| 收起列表不改变模式，字号滑杆仍可调整 | 原生折叠操作列表用例及截图 |
| 只调整字号不污染已保存中心；恢复入口值清除 dirty | `HighlightClipLabelEditorTests` 精度往返、确认保存回归 |
| 保留/排除一起保存，失败不导航；保存目标优先，连续同源未设值继承，手动/跨源不继承 | `HighlightClipLabelEditorTests`、任务 Store 回归及原生保存重开用例 |
| 任务默认、透明度、重算及重置边界 | `HighlightTaskLabelPlacementTests`、既有任务配置与重算测试 |
| schema 1/2/3/4、缺字段和非法字段、无变化不写盘、未来版本保护 | 任务 Store、布局解码与严格校验测试 |
| 不同有效布局保留完整重叠；相同布局与默认等价；关系提示使用相同规划 | `MarkerLabelPlacementTests`、审核上下文与规划器回归 |
| 不同段同编号仍分别使用各自位置/大小；混合来源固定在第一段完整画布 | `ClipFramingExportTests` 解码后像素检查 |
| 超长编号最大字号完整适配，预览与导出共用图片和边界 | 标签几何测试及长编号实际导出像素对比 |
| 透明标签不跳过取景，旋转/镜像、音轨及取消清理保持 | `ClipFramingExportTests` 既有实际媒体回归 |
| 迟到画布和源尺寸不覆盖当前片段、释放后不回写 | `ClipOutputCanvasTests`、播放控制器及迟到加载 UI 回归 |
| 缺源尺寸保留播放能力并可重试；空间编辑不可用时提示原因 | 播放控制器失败/重试/重置测试和视图失败分支独立审查 |
| 最大系统辅助字号和浅深色下主要操作可达 | 完整 UI 通过；人工查看浅/深色普通字号下调整与折叠截图、浅色最大辅助字号截图。新增控件允许滚动至播放和缩略图，保留/排除固定可用；未验证深色最大辅助字号组合 |

## 独立复核

模型/存储/导出与 UI 分别接受独立复核，之后进行完整代码审查。修复了两项 P2：仅改字号时量化合法保存中心；当前源尺寸读取失败时缺少说明与重试。完整代码审查没有新增可确认缺陷。原生 UI 随后发现操作按钮的最小高度放在 Button 外，点击区仍只有 32 点；将三个按钮的最小高度放入 label，使点击区满足 44 点。新增控件使展开时内容变长，测试改为仅在序号模式滚动至播放按钮后检查其完整显示与可点击性，取景模式保留原来直接可见的断言。该调整不改变产品范围，独立复核认可；修复后的完整 499 项回归通过。最后编译检查发现新增的 Codable extension 解码器使用了默认 MainActor 隔离，已明确 initializer 与 CodingKeys 为 nonisolated；此处仅修正隔离声明，不改数据行为，另行重跑全部单元与深色新增 UI，共 477 项通过；日志没有新增的 ConformanceIsolation 警告。最终限定代码审查认可上述修复，无未解决的可操作发现。

## 截图检查

实际检查的结果包附件包含操作列表收起后的字号滑杆、字号 16% 的拖动位置与选中轮廓、保存后下一段及手动重开。最终深色附件 `number-placement-adjusted` 中导航标题、状态、字号说明、操作按钮及保留/排除文字清楚可见；未发现缺字或颜色对比问题。低分辨率合成视频标签随预览放大，截图不作为真实高分辨率素材的清晰度结论；实际导出像素、完整长编号及固定画布由媒体测试验证。

## 验证边界

本次没有真机完整剪辑验收、iPad 完整测试、VoiceOver 真机朗读、Watch 新回归、Release/Archive、商店或生产服务核验。现有 actor/Sendable、AppIntents 和媒体运行提示不作为 warning-free 构建声明。编辑轮廓与方向无障碍动作有实现审查，未将代码审查等同人工辅助功能验收。
