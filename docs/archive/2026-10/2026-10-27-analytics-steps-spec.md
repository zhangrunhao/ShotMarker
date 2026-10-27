# 手机侧流程埋点最小增强

## 已确认目标

用户于 2026-10-27 授权实施最小方案：区分自用、测试、正式来源，补同步、生成、保存尝试与失败；只完善埋点，不改业务架构，手表发送侧先不动。

## 范围与边界

- 沿用现有 Analytics 客户端、GET /track、Nginx JSONL 接收、Node 查询和 Analytics 页面。
- 不改 Watch 代码、同步 payload、业务存储 schema、任务调度、视频生成算法、业务结果或业务异常传播。
- Debug 和模拟器继续不向生产发送。Release iPhone 的开发安装/TestFlight归 test，已验证商店来源归 app_store，无法确认归 unknown。
- 单独的本机自用开关，默认为 false；通过现有诊断入口可设置；自用优先于分发渠道。仅影响后续事件，不倒改历史。
- 不部署生产，不写生产测试事件，不上传 App Store；本轮交付本地可审查代码、测试和部署说明。

## 请求与持久化契约

保留 project、event、device_id；服务器生成 time。只为新版 shotmarker 添加字符串字段：

| 字段 | 值 |
| --- | --- |
| distribution | app_store / test / unknown |
| is_self_use | true / false |
| app_version | 数字点分版本，最长32字符；缺失用 unknown |
| app_build | 数字构建号，最长32字符；缺失用 unknown |
| operation_id | 随机 UUID（小写标准36字符）；app_launch为空/省略 |
| stage | 下述白名单；app_launch为空/省略 |
| reason | 下述白名单；无原因为空/省略 |

不添加自由文本、客户端时间、原始错误、业务UUID、训练或媒体内容。新增字段是本任务批准范围内对旧三参数/四字段契约的扩展，旧网页与旧App仍兼容。Nginx示例配置使用 escape=json，不存IP、User-Agent、完整URL、Cookie；新增字段缺失/全空按旧记录处理为 unknown，混合非法字段拒绝参与聚合。不得把新版字段无效的记录降级成正式用户。

stage: received, decode, import, ack, validation, queue, export, commit, permission, photos_write, local_state。
reason: invalid_input, decode_failed, import_failed, ack_failed, before_cutover, background, busy, invalid_task, revision_conflict, source_unavailable, export_failed, output_commit_failed, permission_denied, missing_output, photos_write_failed, state_update_failed, user_cancelled, backgrounded, cancelled, interrupted, unknown。

## 事件与操作

保留 app_launch 和三个既有 succeeded 名称及成功语义；app_launch仍表示进程启动，不伪称前台会话。

每次手机可见有效同步、生成、保存尝试分配专用随机 operation_id，仅在埋点层持有，不复用训练/任务/output UUID、不新增业务存储字段。重复请求在查询中以安装+操作+流程归并。重复实际操作使用新编号。

- training_sync_started：收到已识别类型的同步消息，解码前。
- training_sync_succeeded：导入成功，ACK前（沿用）。
- training_sync_failed：decode/import阶段实际失败。
- training_sync_ignored：旧cutover载荷，reason=before_cutover，不算业务失败。
- training_sync_ack_failed：回执失败；是附属诊断，不撤销导入成功，不作为同步终态。
- highlight_generate_started：生成操作入口，校验前；排队/导出共享一个操作编号。
- highlight_generate_succeeded：稳定输出且任务引用提交成功（沿用）。
- highlight_generate_failed：validation/queue/export/commit的实际失败。
- highlight_generate_cancelled：主动停止、后台停止或实际取消；每次操作最多一次终态，迟到回调不得产生第二终态。仍按原逻辑停止，不新增调度控制。
- highlight_save_started：有效保存入口，权限/文件检查前；防止已有保存并发重入产生重复尝试。
- highlight_save_succeeded：Photos实际写入成功（沿用）。
- highlight_save_failed：validation/permission/photos_write阶段实际失败。
- highlight_save_cancelled：实际取消。
- highlight_save_state_failed：Photos成功后本地状态更新失败；附属诊断，不撤销成功，不作为保存终态。

现有无重试、静默丢弃、不阻塞业务的发送策略保留。没有终态显示结果未知，不自动标记失败；新版有 operation_id、因丢包或窗口边界而缺开始的终态单列。旧版没有 operation_id 的记录仅参与趋势，不推算操作次数或计入缺开始结果。无法观测 Watch 未发送或未送达手机的情形。

## 查询与页面

- 旧趋势接口无新增筛选时保持原结果格式与语义；允许ShotMarker增加audience及可选version筛选。网站默认ShotMarker audience=production。
- audience: self（is_self_use=true）、production（非自用且app_store）、test（非自用且test）、unknown（非自用且unknown/旧字段缺失）、all。
- 新增 /api/track/shotmarker 聚合，days限定1/7/30/90，默认production；支持同一audience/可选version。仅返回聚合，不返回安装/操作标识。
- 展示三个流程的尝试数、涉及安装数、成功、失败、取消、忽略、结果未知、缺开始结果、冲突结果，以及按stage/reason的失败或附属诊断计数。未配对或冲突不强算成功率。
- 终态可以先于开始到达；同操作重复相同终态去重，矛盾终态显示冲突；回执/保存状态错误单列诊断，不能作为主流程失败。
- 继续保留文件大小/行长/超时/并发限制。范围边界外的开始或结束不猜补，不展示虚假完成率。旧数据归unknown，不回填来源或操作信息。
- 网站仅添加筛选与简单表格，保持已有趋势图；切换筛选时不展示旧结果，兼容查询单并发限制。

## 验证与交付

- Swift：序列化字段与隐私、分发unknown兜底、自用标记、Debug/模拟器不发送、同步各分支、生成失败/停止/排队/迟到回调、保存权限拒绝/成功后状态失败、业务结果不变。
- Node/网页：新旧混合记录、非法字段、来源筛选、跨安装同操作号不合并、去重/乱序/缺开始/缺终态/冲突、附属诊断、窗口边界、不泄露标识、旧网页趋势回归。
- 两仓库定向测试和要求的完整检查，iPhone全单元/既有UI回归及Release模拟器构建；不以模拟器验证替代真机分发渠道或生产验收。
- 更新current与公开隐私说明；完成的spec/plan归档。现有隐私类别是否需调整按实际采集字段核验，不代替App Store后台提交。
