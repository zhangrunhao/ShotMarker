# ShotMarker 观测验证

- 最后外部验证：2026-08-16；后续生产状态未重新核验。
- 本页只保存脱敏后的验证结果；客户端实现、请求与隐私契约见[产品埋点](analytics.md)和[技术架构](architecture.md#日志与远端观测)。

## Analytics

- 2026-08-16 已完成共享 Track 服务的四字段写入、趋势查询、Analytics 页面和公开隐私页验收。
- 真实 iPhone Release/TestFlight 的四个 ShotMarker 事件尚未完成端到端验收，服务端可用不能替代真实客户端链路通过。
- 服务端存储字段与保留状态的最后核验摘要见[产品埋点](analytics.md#外部状态摘要)；共享服务的公开部署契约由[网站仓库](https://github.com/zhangrunhao/zhangrh.shop/blob/main/docs/current/deployment.md)维护。

## GlitchTip

- 2026-08-16 已在 ShotMarker 对应项目中看到受控接入验证事件和多条业务错误事件。
- 未确认正式 Release 真机原生崩溃、对应 dSYM 符号化和邮件或 Webhook 告警送达。不能把历史事件接收成功扩展为当前告警或符号化可用。

## 证据与边界

- 详细历史结果见[2026-08-16 观测验收](../archive/2026-08/2026-08-16-observability-validation.md)，保留当时日期和验证限制。
- 主机、网络、数据库、权限和备份等敏感实例配置由独立私有台账维护，本页不复制内部管理定位。
- 不保存原始事件 payload、真实用户或设备标识、后台截图敏感值、Auth Token、管理凭据、训练记录、视频或原始日志。
