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

## 后台替换与重新提交

验证方式为 Chrome 原生电脑控制，查看 App Store Connect 版本、Media Manager 和审核详情页面。以下均为 2026-09-29 当次操作事实，不代表后续或当前审核状态。

1. 原提交于当日 15:05 进入等待审核。新素材准备完成后执行 Cancel Submission，版本变为 Developer Rejected。
2. 删除旧 iPhone 6.9 与 6.5 英寸独立截图，以及旧 iPad 13 英寸和 Watch 素材；上传当前界面截图。
3. iPhone 6.9 英寸最终 5 张，顺序为审核、编辑、样式、任务配置、完成任务；其他 iPhone 尺寸使用 6.9 英寸素材。
4. iPad 13 英寸最终 3 张，顺序为审核、编辑、样式；其他 iPad 尺寸使用 13 英寸素材。Watch Ultra 3 槽位为新的开始训练截图 1 张。
5. 重新核对 Build 3 / Version 1.3、英文更新说明、Description、Review Notes 和手动发布选项，保留已保存内容及原有构建。
6. Add for Review 后草稿仅含 iOS App 1.3 / 1.3（3）；执行 Submit for Review，成功提示为 1 Item Submitted。
7. 新审核详情显示 Waiting for Review，提交时间为 2026-09-29 16:33；没有发布上线。

实际上传 iPhone 5 张 JPEG、Watch 1 张 JPEG，iPad 1 张 JPEG 与 2 张 RGB PNG。本地两张兼容 PNG 的 2064 × 2752 尺寸、无 Alpha 及全部 11 个清单文件的 SHA-256 均已核对，后台最终接受 9 张新素材。

### 上传残留排查

- iPad 的两张 JPEG 最初留下灰色占位图，Add for Review 返回 There are still screenshot uploads in progress。
- 清理失败记录后，改用同尺寸、无 Alpha 的 RGB PNG 单张上传编辑和样式截图，实际缩略图正常显示。
- 版本页一度只显示 3 张成功图片，但重新打开 Media Manager 时仍显示一条失败 JPEG 记录。删除该记录后，后台允许加入审核并正式提交。
- 这是已观察到的上传残留及恢复过程，没有证明 JPEG 编码或网络服务是根因。
- 本地证据保存在公开项目忽略目录 build/release-1.3/，含 ipad-new-assets-complete.png、resubmitted-new-screenshots.png 和同名状态文本；不把包含账号信息的原始页面状态纳入文档 Git。

## 验证边界

- 此次验证覆盖截图页面及上述合成演示流程，没有重新执行完整自动测试、真机验收、Watch 同步/升级或生产观测验收。
- Debug Simulator 版本号一致，不构成已上传正式 Archive 的源码、签名或 dSYM 映射证明。
- 截图发布后的最新审核状态以 [发布状态](../../current/release.md) 中注明日期的核验为准；本记录仅保留当日事实。
