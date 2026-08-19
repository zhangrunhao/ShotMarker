# ShotMarker 文档入口

这里是 ShotMarker 文档的唯一入口。当前代码和当次验证优先于任何文档。

## 当前事实

- [项目状态](current/status.md)：总体结论、风险和下一步
- [产品事实](current/product.md)：当前用户流程、业务规则和有效产品决定
- [技术架构](current/architecture.md)：Targets、数据流、持久化和外部集成
- [产品埋点](current/analytics.md)：事件语义、发送契约、存储和隐私边界
- [质量状态](current/quality.md)：测试、构建、静态检查和未覆盖范围
- [发布状态](current/release.md)：版本、披露要求和外部状态

current 只保存简洁、仍然有效且有证据支持的事实和决定，不保存开发流水账。

ShotMarker 对外网站、支持页和 how-to 由 `zhangrh.shop` 仓库维护，不在本仓库保存副本。

## 正在进行的变更

- [iOS 语音口令打点与技术统计](changes/2026-07-29-ios-voice-command-marking-spec.md)：设计已确认，尚未实现

changes 使用扁平文件：

~~~text
YYYY-MM-DD-topic-spec.md
YYYY-MM-DD-topic-plan.md
~~~

## 历史资料

archive 保存已经结束的设计、计划、讨论、排查、发布验证和旧文档。它不是当前事实来源。

归档文件使用：

~~~text
YYYY-MM-DD-topic.md
YYYY-MM-DD-topic-spec.md
YYYY-MM-DD-topic-plan.md
~~~

不为只有一至两个 Markdown 的主题创建子目录。

## 维护流程

~~~text
提出变更
→ 在 changes 编写 spec
→ 在 changes 编写 plan
→ 实施与验证
→ 更新受影响的 current 文档
→ 将完成的 spec 和 plan 移入 archive
~~~

外部服务、App Store、TestFlight 等变化状态如果没有在当前任务重新验证，必须保留最后验证日期或标为未确认。
