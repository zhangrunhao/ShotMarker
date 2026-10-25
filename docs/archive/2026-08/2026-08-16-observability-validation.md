# ShotMarker 远端观测生产验收

- 日期：2026-08-16
- 状态：历史验证已结束
- 范围：ShotMarker 对应 GlitchTip 项目与 Analytics 服务端链路

## GlitchTip

- ShotMarker 对应项目中确认出现受控接入验证事件和多条业务错误事件。
- 当时尚未完成正式 Release 真机原生崩溃、对应 dSYM 符号化和邮件或 Webhook 告警送达验证。
- 本记录不保存原始事件 payload、用户标识、后台截图或 Auth Token。

## Analytics

- 旧 Analytics schema 曾使用一个随机合成安装标识完成服务端写入与聚合验证；原始安装标识和请求标识未写入台账。
- 同日完成四字段生产切换与服务端验收，但没有真实 Release/TestFlight ShotMarker 客户端事件。
- 服务端数据契约的历史设计见 [Analytics 规格](2026-08-16-shotmarker-analytics-spec.md)。共享基础设施的具体实例值与运维材料不在本记录复制。

## 结论

- 这次验证证明服务端接收、查询和观测入口当时可用，不证明当前线上状态，也不代表真实 ShotMarker 客户端端到端验收已经完成。
- 真机客户端事件、真机崩溃、dSYM 符号化和告警仍需在正式 Release 或 TestFlight Build 上重新验证。
