# 1.3 商店截图准备与核验

- 日期：2026-09-29
- 范围：用当前界面替换旧商店图片；继续使用已上传的 1.3（Build 3）
- 决定：用户明确要求先准备截图，再撤回审核、替换并重新提交

## 素材来源

使用当前工作副本（含用户已有配置修改），通过 Xcode 27.0 的普通 App 入口拍摄。没有修改生产代码、启用截图测试入口或生成新的分发 Archive。

构建命令：

```sh
xcodebuild -project ShotMarker.xcodeproj -scheme ShotMarker \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/store-screenshots-derived \
  CODE_SIGNING_ALLOWED=NO build
```

结果为 `BUILD SUCCEEDED`；构建包的主 App 与 Watch 均为 1.3（3）。日志存在播放回调 Sendable、链接器及 AppIntents 提示，不能称为无警告构建。

每种设备使用独立的新建 Simulator。iPhone/iPad 的合成训练记录只写入这些设备的 App 沙盒；90 秒篮球场演示视频由本地 AVFoundation 创建，不含真实用户视频、姓名或第三方素材。普通 App 完成了第一片段起点调整、确认保留、第二片段排除，并实际生成 38.5 秒的演示集锦。

通过 Device Hub 原生 Screenshot 按钮保存 PNG，再以 `sips` 转为质量 95、无 Alpha 的同尺寸 JPEG。未裁切、缩放或绘制 App 界面。

## 文件与内容

| 槽位 | 模拟器 | 原始尺寸 | 张数 | 内容 |
| --- | --- | --- | --- | --- |
| iPhone 6.9 英寸 | iPhone 17 Pro Max / iOS 26.5 | 1320 × 2868 | 5 | 片段审核、单片段编辑、标签样式、任务配置、已完成任务 |
| iPad 13 英寸 | iPad Pro 13-inch (M5) / iPadOS 26.5 | 2064 × 2752 | 3 | 片段审核、单片段编辑、标签样式 |
| Apple Watch Ultra 3 | Ultra 3 49mm / watchOS 26.5 | 422 × 514 | 1 | 长按开始训练的起始界面 |

- [iPhone 素材](../../../AppStoreScreenshots/2026-09-29-iphone-69/README.md)
- [iPad 素材](../../../AppStoreScreenshots/2026-09-29-ipad-13/README.md)
- [Watch 素材](../../../AppStoreScreenshots/2026-09-29-watch-49/README.md)

各目录根部保存原始 PNG；`upload-ready/` 保存上传 JPEG；iPad 另有两张从 JPEG 转码、无 Alpha 的 RGB PNG 兼容版；`manifest.json` 保存精确尺寸及 SHA-256。全部 9 张截图已逐张查看，JPEG 尺寸与无 Alpha 校验通过。尺寸规则按当日 [Apple 官方截图规范](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) 核对。

## 完成结果

- 截图准备完成后，按用户授权撤回原审核，替换 iPhone/iPad/Watch 素材，再使用同一 1.3（3）重新送审。
- iPhone 上传 5 张 JPEG，Watch 上传 1 张 JPEG；iPad 使用 1 张 JPEG 与 2 张 RGB PNG。两张兼容 PNG 的 2064 × 2752 尺寸、无 Alpha 及全部 11 个清单文件的 SHA-256 均已核对。
- 后台最终接受 9 张新素材并完成重新提交；发布方式仍为审核通过后手动发布。具体提交时间与审核状态由私有台账维护，公开摘要见 [发布状态](../../current/release.md)。

## 验证边界

- 此次验证覆盖截图页面及上述合成演示流程，没有重新执行完整自动测试、真机验收、Watch 同步/升级或生产观测验收。
- Debug Simulator 版本号一致，不构成已上传正式 Archive 的源码、签名或 dSYM 映射证明。
- 截图发布后的最新审核状态以 [发布状态](../../current/release.md) 的摘要与私有分发台账为准。
